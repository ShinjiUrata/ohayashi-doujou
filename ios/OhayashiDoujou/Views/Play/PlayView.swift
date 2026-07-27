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
    }
  }

  // MARK: - Auto-play controls(再生/停止トグル)

  private var autoPlayControls: some View {
    HStack(spacing: 24) {
      controlButton(
        icon: "▶",
        label: "再生",
        active: !isPaused,
        action: resume
      )
      controlButton(
        icon: "■",
        label: "停止",
        active: isPaused,
        action: pause
      )
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(WafuuUI.paper.opacity(0.9))
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
    )
  }

  private func controlButton(
    icon: String,
    label: String,
    active: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Text(icon)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(active ? .white : WafuuUI.sumiSoft)
        Text(label)
          .font(WafuuUI.serif(11, weight: .semibold))
          .tracking(2)
          .foregroundStyle(active ? .white : WafuuUI.sumiSoft)
      }
      .frame(width: 68, height: 60)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(active ? WafuuUI.don : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(active ? WafuuUI.donDim : WafuuUI.woodDark, lineWidth: 1.5)
      )
    }
    .buttonStyle(.plain)
  }

  private func pause() {
    guard !isPaused else { return }
    isPaused = true
    scene.pauseGame()
  }

  private func resume() {
    guard isPaused else { return }
    isPaused = false
    scene.resumeGame()
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      Button(action: onQuit) {
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
      score = finalScore
      onFinished(finalScore)
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
