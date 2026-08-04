import SwiftUI
import SpriteKit

/// プレイ画面。
///
/// - `Chart` を受け取って再生
/// - 開始前に 3-2-1 カウントダウンを表示、終わってから `PlayScene` に load
/// - **mode: .interactive** → 通常プレイ(タッチ判定・スコア加算)
/// - **mode: .autoPlay**   → 自動再生プレビュー(タッチ判定なし、譜面通りに
///                            音のみ再生。画面下部に再生/停止ボタン)
/// - `PlayScene` からの終了コールバックで onFinished を呼ぶ
///
/// mockup: `mockups/play_wafuu_modern.html`
struct PlayView: View {
  let chart: Chart
  var mode: PlayScene.Mode = .interactive
  var onFinished: (ScoreState) -> Void
  var onQuit: () -> Void
  /// 自動再生プレビューを離れる時に呼ばれる。停止中に編集された調整が
  /// 反映済みの Chart を受け取る。autoPlay モードでのみ意味を持つ。
  /// 呼ばれるタイミング:
  ///  - ×(戻る)ボタン
  ///  - 譜面終端に達して自動的に完了
  var onAutoPlayExit: (Chart) -> Void = { _ in }

  enum Phase: Equatable {
    case countdown(Int)
    case playing
  }

  @State private var score = ScoreState()
  @State private var scene: PlayScene = {
    let s = PlayScene(size: CGSize(width: 390, height: 780))
    s.scaleMode = .resizeFill
    return s
  }()

  @State private var phase: Phase = .countdown(3)
  @State private var countdownTask: Task<Void, Never>?

  /// 自動再生モード時の再生/停止トグル状態。
  @State private var isPaused: Bool = false

  /// 自動再生モード時のシークバー表示・操作用状態。
  /// SwiftUI Slider は Double バインディングが必要。
  @State private var sliderSec: Double = 0
  @State private var isSliderDragging: Bool = false
  /// スクラブ(ドラッグ)開始時点の再生状態(true = 元は再生中だった)。
  /// ドラッグ終了時に元の状態に戻すために使う。
  @State private var wasPlayingBeforeScrub: Bool = false

  /// 停止中に選択されているノーツの情報(SwiftUI の ± ボタン表示用)。
  /// nil = 未選択(ボタンは非表示)。
  @State private var selectedNoteInfo: PlayScene.NoteSelectionInfo? = nil

  /// 保存済みの chart(nil = まだ一度も保存していない)。
  /// × ボタンで編集画面に戻る時、これがあれば返す。無ければ元の chart を返す。
  /// 保存を経ないと adjustments は破棄される仕組み。
  @State private var lastSavedChart: Chart? = nil

  /// 保存されていない編集がある(前回保存以降 or 初期状態からの adjustment あり)。
  @State private var hasUnsavedChanges: Bool = false

  /// 保存直後の視覚フィードバック(短時間だけ ✓ を出す)。
  @State private var showSavedFeedback: Bool = false
  @State private var savedFeedbackTask: Task<Void, Never>?

  var body: some View {
    ZStack {
      WafuuBackground()

      SpriteView(scene: scene, options: [.ignoresSiblingOrder, .allowsTransparency])
        .ignoresSafeArea()
        .background(Color.clear)

      VStack {
        header
        // 自動再生モードではヘッダーの直下に「ノーツ追加」ボタン列(4 レーン分)
        if mode == .autoPlay && phase == .playing {
          addNoteButtonsRow
        }
        Spacer()
      }

      countdownOverlay

      // 自動再生モードのコントロール(画面下部、太鼓と被って OK)
      if mode == .autoPlay && phase == .playing {
        VStack {
          Spacer()
          // ノーツ選択中はシークバーの真上に ± 調整ボタンを表示
          if let info = selectedNoteInfo {
            noteAdjustControls(for: info)
              .padding(.horizontal, 16)
              .padding(.bottom, 8)
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
          autoPlayControls
            .padding(.bottom, 36)
        }
      }
    }
    .statusBarHidden(true)
    .onAppear {
      AudioEngine.shared.start()
      Haptics.shared.prepare()
      scene.mode = mode
      wireScene()
      startCountdown()
    }
    .onDisappear {
      countdownTask?.cancel()
      savedFeedbackTask?.cancel()
    }
  }

  // MARK: - Countdown overlay

  @ViewBuilder
  private var countdownOverlay: some View {
    switch phase {
    case .countdown(let n):
      Text("\(n)")
        .font(WafuuUI.serif(140, weight: .black))
        .foregroundStyle(WafuuUI.don)
        .shadow(color: WafuuUI.don.opacity(0.35), radius: 16, x: 0, y: 6)
        .transition(.asymmetric(
          insertion: .scale(scale: 0.4).combined(with: .opacity),
          removal: .scale(scale: 1.6).combined(with: .opacity)
        ))
        .id("count-\(n)")
    case .playing:
      EmptyView()
    }
  }

  // MARK: - Countdown logic

  private func startCountdown() {
    countdownTask?.cancel()
    countdownTask = Task { @MainActor in
      for n in [3, 2, 1] {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
          phase = .countdown(n)
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }
      }
      withAnimation(.easeInOut(duration: 0.2)) {
        phase = .playing
      }
      // カウントダウン完了後に譜面をロード → PlayScene が startTime を CACurrentMediaTime() で
      // 記録し、ノーツのスケジューリング(および autoPlay 時の音再生)を開始する
      scene.load(chart: chart)
      // シークバーの位置更新は seekBar 内の TimelineView が行うため
      // ポーリング Task は不要。
    }
  }

  // MARK: - Auto-play controls(再生/停止トグル + シークバー)

  private var autoPlayControls: some View {
    HStack(spacing: 14) {
      playPauseToggle
      seekBar
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(WafuuUI.paper.opacity(0.92))
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
    )
    .padding(.horizontal, 16)
  }

  /// 左端の再生/停止トグル(1 個のボタンでアイコン切替)。
  private var playPauseToggle: some View {
    Button(action: togglePlayPause) {
      Text(isPaused ? "▶" : "❚❚")
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 54, height: 54)
        .background(
          Circle()
            .fill(
              LinearGradient(
                colors: [WafuuUI.donHi, WafuuUI.don, WafuuUI.donDim],
                startPoint: .top,
                endPoint: .bottom
              )
            )
        )
        .overlay(Circle().stroke(WafuuUI.donDim, lineWidth: 1.5))
        .shadow(color: WafuuUI.don.opacity(0.35), radius: 4, x: 0, y: 2)
    }
    .buttonStyle(.plain)
  }

  /// 右側のシークバー + 経過時刻 / 総時間表示。
  ///
  /// 実装方針:
  /// TimelineView で 100ms 毎に body を再評価する。Binding の get は
  /// - isSliderDragging が true → sliderSec(ユーザーの指位置)を返す
  /// - false → scene.currentPlaybackTimeSec() を返す
  /// この方針にすると、@State の polling Task を持たなくてよくなり、
  /// Task の再走・state 同期・キャンセルなど「シークバーが動かなくなる」
  /// 系のバグが構造的に発生しなくなる。
  private var seekBar: some View {
    let totalSec = Double(chart.durationMs) / 1000.0
    return TimelineView(.periodic(from: .now, by: 0.1)) { _ in
      let displaySec: Double = isSliderDragging ? sliderSec : scene.currentPlaybackTimeSec()
      VStack(spacing: 4) {
        Slider(
          value: Binding(
            get: { displaySec },
            set: { newVal in sliderSec = newVal }
          ),
          in: 0...max(totalSec, 0.001),
          onEditingChanged: { editing in
            if editing {
              // ドラッグ開始時に sliderSec を現在の表示時刻に初期化
              // (ドラッグ中は sliderSec がユーザーの指の位置を表す)
              sliderSec = displaySec
              beginScrub()
            } else {
              endScrub()
            }
          }
        )
        .tint(WafuuUI.donDim)
        .onChange(of: sliderSec) { _, new in
          // ドラッグ中はスライダー移動に追従して scene を silent seek
          // (視覚だけ更新、音は鳴らさない)
          if isSliderDragging {
            scene.seek(toSec: new, silent: true)
          }
        }

        HStack {
          Text(formatMSS(displaySec))
          Spacer()
          Text(formatMSS(totalSec))
        }
        .font(WafuuUI.num(10, weight: .medium))
        .tracking(1)
        .foregroundStyle(WafuuUI.sumiSoft)
      }
    }
  }

  /// スクラブ開始: 元が再生中だったら pause(scene.speed = 0 で SKAction 停止)。
  /// 元の再生状態を記憶して、endScrub で復元する。
  private func beginScrub() {
    isSliderDragging = true
    wasPlayingBeforeScrub = !isPaused
    if !isPaused {
      // 再生中 → 一時停止(スクラブ中は音を止めた状態で視覚だけ動かす)
      scene.pauseGame()
      isPaused = true
    }
  }

  /// スクラブ終了: 最終位置に音付きで seek 再スケジュール。
  /// 元が再生中だったら再開、停止中だったらそのまま。
  private func endScrub() {
    isSliderDragging = false
    // 音付きで最終位置に再スケジュール(silent = false)
    scene.seek(toSec: sliderSec, silent: false)
    if wasPlayingBeforeScrub {
      scene.resumeGame()
      isPaused = false
    }
  }

  private func togglePlayPause() {
    if isPaused {
      isPaused = false
      scene.resumeGame()
    } else {
      isPaused = true
      scene.pauseGame()
    }
  }

  // 再生時間のポーリングは廃止。シークバー内の TimelineView が
  // 100ms 周期で再描画するため、Slider の表示は常に最新の
  // scene.currentPlaybackTimeSec() を反映する。

  private func formatMSS(_ sec: Double) -> String {
    let total = Int(sec.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  // MARK: - Note adjust controls(選択中ノーツの ± ボタン)

  /// シークバー真上に表示する ± 調整ボタン。
  /// - 右矢印 ▶ = 0.1s 早める(deltaMs = -100)
  /// - 左矢印 ◀ = 0.1s 遅らせる(deltaMs = +100)
  @ViewBuilder
  private func noteAdjustControls(for info: PlayScene.NoteSelectionInfo) -> some View {
    HStack(spacing: 12) {
      // 左矢印: 遅らせる
      Button(action: {
        scene.applyExternalAdjustment(deltaMs: 100)
        markUnsaved()
      }) {
        Text("◀")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 60, height: 48)
          .background(
            LinearGradient(
              colors: [WafuuUI.donHi, WafuuUI.don, WafuuUI.donDim],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(WafuuUI.donDim, lineWidth: 1.5))
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .shadow(color: WafuuUI.don.opacity(0.35), radius: 3, x: 0, y: 2)
      }
      .buttonStyle(.plain)

      // 中央: ノーツ種別 + 累積調整量
      VStack(spacing: 2) {
        Text(noteTypeLabel(info.typeRawValue))
          .font(WafuuUI.serif(11, weight: .bold))
          .tracking(1)
          .foregroundStyle(WafuuUI.sumi)
        Text(formatDelta(info.deltaMs))
          .font(WafuuUI.num(15, weight: .medium))
          .tracking(1)
          .foregroundStyle(info.deltaMs == 0 ? WafuuUI.sumiSoft : WafuuUI.donDim)
      }
      .frame(maxWidth: .infinity)

      // 右矢印: 早める
      Button(action: {
        scene.applyExternalAdjustment(deltaMs: -100)
        markUnsaved()
      }) {
        Text("▶")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 60, height: 48)
          .background(
            LinearGradient(
              colors: [WafuuUI.donHi, WafuuUI.don, WafuuUI.donDim],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(WafuuUI.donDim, lineWidth: 1.5))
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .shadow(color: WafuuUI.don.opacity(0.35), radius: 3, x: 0, y: 2)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(WafuuUI.paper.opacity(0.92))
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
    )
  }

  // MARK: - Add note buttons(ヘッダー直下、4 レーン分)

  /// 各レーンの最上部に配置される「ノーツ追加」ボタン列。
  /// autoPlay モード時のみ表示、押すと現在の再生位置にそのレーンの
  /// ノーツを追加する。追加すると未保存フラグが立ち、保存ボタンで確定。
  private var addNoteButtonsRow: some View {
    HStack(spacing: 0) {
      addNoteButton(typeRaw: "ka_l", color: WafuuUI.ka, dimColor: WafuuUI.kaDim, label: "左カ")
      addNoteButton(typeRaw: "don_l", color: WafuuUI.don, dimColor: WafuuUI.donDim, label: "左ド")
      addNoteButton(typeRaw: "don_r", color: WafuuUI.don, dimColor: WafuuUI.donDim, label: "右ド")
      addNoteButton(typeRaw: "ka_r", color: WafuuUI.ka, dimColor: WafuuUI.kaDim, label: "右カ")
    }
    .padding(.horizontal, 0)
    .padding(.top, 4)
  }

  private func addNoteButton(typeRaw: String, color: Color, dimColor: Color, label: String) -> some View {
    Button(action: {
      scene.addNoteAtCurrentTime(typeRawValue: typeRaw)
      markUnsaved()
    }) {
      VStack(spacing: 2) {
        Text("＋")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(.white)
        Text(label)
          .font(WafuuUI.serif(9, weight: .bold))
          .tracking(1)
          .foregroundStyle(.white.opacity(0.85))
      }
      .frame(maxWidth: .infinity)
      .frame(height: 42)
      .background(
        LinearGradient(
          colors: [color, dimColor],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(dimColor, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 1)
      .padding(.horizontal, 2)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Save button(autoPlay モード時、ヘッダー右端)

  /// 保存ボタン。押すと現在の adjustments を lastSavedChart に commit する。
  /// hasUnsavedChanges = false なら disabled(押しても意味なし)。
  private var saveButton: some View {
    Button(action: saveAdjustments) {
      VStack(spacing: 2) {
        Text(showSavedFeedback ? "✓" : "保存")
          .font(WafuuUI.serif(13, weight: .bold))
          .tracking(2)
          .foregroundStyle(showSavedFeedback ? WafuuUI.moss : WafuuUI.sumi)
        Text("SAVE")
          .font(WafuuUI.num(8, weight: .semibold))
          .tracking(3)
          .foregroundStyle(WafuuUI.sumiMist)
      }
      .frame(width: 62)
      .padding(.vertical, 8)
      .background(
        LinearGradient(
          colors: [WafuuUI.woodLight, WafuuUI.woodMid],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
      )
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    .disabled(!hasUnsavedChanges && !showSavedFeedback)
    .opacity(hasUnsavedChanges || showSavedFeedback ? 1 : 0.45)
  }

  /// ± ボタン押下時に呼ばれる。未保存フラグを立てる。
  private func markUnsaved() {
    hasUnsavedChanges = true
    // 直前の "✓" フィードバックが残っていたら消す
    if showSavedFeedback {
      savedFeedbackTask?.cancel()
      showSavedFeedback = false
    }
  }

  /// 保存ボタン押下時。現在の scene の chart を lastSavedChart に commit。
  /// これで × / 完了時に adjustments が編集画面へ持ち帰られる。
  private func saveAdjustments() {
    lastSavedChart = scene.currentAdjustedChart() ?? chart
    hasUnsavedChanges = false
    // 短時間だけ ✓ を表示して保存できたことを可視化
    savedFeedbackTask?.cancel()
    withAnimation(.easeInOut(duration: 0.15)) {
      showSavedFeedback = true
    }
    savedFeedbackTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      if !Task.isCancelled {
        withAnimation(.easeInOut(duration: 0.25)) {
          showSavedFeedback = false
        }
      }
    }
  }

  /// 編集画面に持ち帰る chart(保存済みが無ければ元の chart)。
  private func chartToReturnOnExit() -> Chart {
    return lastSavedChart ?? chart
  }

  private func noteTypeLabel(_ raw: String) -> String {
    switch raw {
    case "don_l": return "左ドン"
    case "don_r": return "右ドン"
    case "don_both": return "両手ドン"
    case "ka_l": return "左カッ"
    case "ka_r": return "右カッ"
    default: return raw
    }
  }

  private func formatDelta(_ ms: Int) -> String {
    if ms == 0 { return "±0.0s" }
    let sign = ms > 0 ? "+" : "-"
    let sec = Double(abs(ms)) / 1000.0
    return String(format: "%@%.1fs", sign, sec)
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      Button(action: handleQuit) {
        Text("×")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(WafuuUI.sumiSoft)
          .frame(width: 32, height: 32)
      }

      if mode == .interactive {
        // SCORE 掛け札(通常プレイ時のみ)
        WoodPlate(width: 68) {
          Text("SCORE")
            .font(WafuuUI.num(8, weight: .semibold))
            .tracking(3)
            .foregroundStyle(WafuuUI.sumiMist)
          Text(formattedScore(score.totalScore))
            .font(WafuuUI.num(18, weight: .medium))
            .tracking(1)
            .foregroundStyle(WafuuUI.sumi)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
      }

      // 曲名バナー(両モードで表示)
      VStack(spacing: 2) {
        Text(mode == .autoPlay ? "PREVIEW" : "NOW PLAYING")
          .font(WafuuUI.num(8, weight: .semibold))
          .tracking(3)
          .foregroundStyle(WafuuUI.sumiMist)
        Text(chart.name.isEmpty ? "無題" : chart.name)
          .font(WafuuUI.serif(14, weight: .bold))
          .tracking(2)
          .foregroundStyle(WafuuUI.sumi)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Text(chart.region.isEmpty ? "—" : chart.region)
          .font(WafuuUI.gothic(9))
          .tracking(1)
          .foregroundStyle(WafuuUI.sumiSoft)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity)
      .background(
        LinearGradient(
          colors: [Color(hex: 0xF6E9C9), Color(hex: 0xEAD7A4)],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 5)
          .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
      )
      .clipShape(RoundedRectangle(cornerRadius: 5))
      .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 2)

      if mode == .interactive {
        // COMBO 掛け札(通常プレイ時のみ)
        WoodPlate(width: 68) {
          Text("COMBO")
            .font(WafuuUI.num(8, weight: .semibold))
            .tracking(3)
            .foregroundStyle(WafuuUI.sumiMist)
          Text("\(score.combo)")
            .font(WafuuUI.num(18, weight: .medium))
            .tracking(1)
            .foregroundStyle(WafuuUI.donDim)
        }
      } else {
        // autoPlay モードでは右端に保存ボタン
        saveButton
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .background(
      LinearGradient(
        colors: [WafuuUI.moss.opacity(0.06), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .overlay(
      Rectangle()
        .fill(WafuuUI.sumi.opacity(0.12))
        .frame(height: 1),
      alignment: .bottom
    )
  }

  private func wireScene() {
    scene.onScoreChanged = { newScore in
      score = newScore
    }
    scene.onFinished = { finalScore in
      if mode == .autoPlay {
        // 自動再生プレビュー: 保存済みの chart(あれば)を返す。
        // 未保存の adjustments は破棄される仕様。
        onAutoPlayExit(chartToReturnOnExit())
      } else {
        score = finalScore
        onFinished(finalScore)
      }
    }
    scene.onNoteSelectionChanged = { info in
      withAnimation(.easeInOut(duration: 0.15)) {
        selectedNoteInfo = info
      }
    }
  }

  /// ×(戻る)ボタンハンドラ。
  /// autoPlay 時は保存済み chart を返す(未保存の adjustments は破棄)。
  private func handleQuit() {
    if mode == .autoPlay {
      onAutoPlayExit(chartToReturnOnExit())
    } else {
      onQuit()
    }
  }

  private func formattedScore(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
  }
}

#Preview("Interactive") {
  PlayView(
    chart: DemoChart.phase2Demo,
    onFinished: { _ in },
    onQuit: {}
  )
}

#Preview("AutoPlay") {
  PlayView(
    chart: DemoChart.phase2Demo,
    mode: .autoPlay,
    onFinished: { _ in },
    onQuit: {}
  )
}
