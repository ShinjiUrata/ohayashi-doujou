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
  @State private var playbackTimerTask: Task<Void, Never>?

  var body: some View {
    ZStack {
      WafuuBackground()

      SpriteView(scene: scene, options: [.ignoresSiblingOrder, .allowsTransparency])
        .ignoresSafeArea()
        .background(Color.clear)

      VStack {
        header
        Spacer()
      }

      countdownOverlay

      // 自動再生モードのコントロール(画面下部、太鼓と被って OK)
      if mode == .autoPlay && phase == .playing {
        VStack {
          Spacer()
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
      playbackTimerTask?.cancel()
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
      // 自動再生モードではシークバー用に再生時間ポーリングを開始
      if mode == .autoPlay {
        startPlaybackTimePolling()
      }
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
  private var seekBar: some View {
    let totalSec = Double(chart.durationMs) / 1000.0
    return VStack(spacing: 4) {
      Slider(
        value: $sliderSec,
        in: 0...max(totalSec, 0.001),
        onEditingChanged: { editing in
          if editing {
            isSliderDragging = true
          } else {
            isSliderDragging = false
            scene.seek(toSec: sliderSec)
          }
        }
      )
      .tint(WafuuUI.donDim)

      HStack {
        Text(formatMSS(sliderSec))
        Spacer()
        Text(formatMSS(totalSec))
      }
      .font(WafuuUI.num(10, weight: .medium))
      .tracking(1)
      .foregroundStyle(WafuuUI.sumiSoft)
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

  /// 再生時間を 100ms 毎にポーリングしてスライダー位置を更新。
  /// ドラッグ中はユーザー操作を優先(更新しない)。
  private func startPlaybackTimePolling() {
    playbackTimerTask?.cancel()
    playbackTimerTask = Task { @MainActor in
      while !Task.isCancelled {
        if !isSliderDragging {
          sliderSec = scene.currentPlaybackTimeSec()
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
    }
  }

  private func formatMSS(_ sec: Double) -> String {
    let total = Int(sec.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
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
        // 自動再生プレビューでは編集された chart を返して編集画面に戻る
        onAutoPlayExit(scene.currentAdjustedChart() ?? chart)
      } else {
        score = finalScore
        onFinished(finalScore)
      }
    }
  }

  /// ×(戻る)ボタンハンドラ。autoPlay 時は編集チャートを返す。
  private func handleQuit() {
    if mode == .autoPlay {
      onAutoPlayExit(scene.currentAdjustedChart() ?? chart)
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
