import SwiftUI
import SpriteKit

/// 録音画面(SwiftUI)。
///
/// フェーズ:
/// - `.ready`: 中央に「録音開始」ボタン、まだタップは記録されない
/// - `.countdown(n)`: 中央に大きな数字 (3 → 2 → 1) を 1 秒ごとに表示
/// - `.recording`: REC バッジ + タイマー、実際の録音中
///
/// mockup: `mockups/06_recording_wafuu.html`
struct RecordingView: View {
  var onStopped: (Chart) -> Void
  var onCancel: () -> Void

  enum Phase: Equatable {
    case ready
    case countdown(Int)
    case recording
  }

  @State private var scene: RecordingScene = {
    let s = RecordingScene(size: CGSize(width: 390, height: 780))
    s.scaleMode = .resizeFill
    return s
  }()

  @State private var phase: Phase = .ready
  @State private var elapsedMs: Int = 0
  @State private var recentSymbols: [Note] = []
  @State private var timerTask: Task<Void, Never>?
  @State private var countdownTask: Task<Void, Never>?

  var body: some View {
    ZStack {
      WafuuBackground()

      SpriteView(scene: scene, options: [.ignoresSiblingOrder, .allowsTransparency])
        .ignoresSafeArea()
        .background(Color.clear)

      VStack(spacing: 0) {
        header
        recentSymbolsRow
        Spacer()
      }

      centerOverlay
    }
    .statusBarHidden(true)
    .onAppear {
      AudioEngine.shared.start()
      Haptics.shared.prepare()
      scene.onNoteRecorded = { note in
        Task { @MainActor in
          recentSymbols.append(note)
          if recentSymbols.count > 10 { recentSymbols.removeFirst() }
        }
      }
    }
    .onDisappear {
      timerTask?.cancel()
      countdownTask?.cancel()
    }
  }

  // MARK: - Header

  @ViewBuilder
  private var header: some View {
    HStack(spacing: 10) {
      // 中断ボタン
      Button(action: cancel) {
        Text("×")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(WafuuUI.sumiSoft)
          .frame(width: 32, height: 32)
      }

      if case .recording = phase {
        recordingHeaderContents
      } else {
        Spacer()
        Text(phase == .ready ? "録音準備" : "")
          .font(WafuuUI.gothic(12))
          .tracking(2)
          .foregroundStyle(WafuuUI.sumiSoft)
        Spacer()
        Color.clear.frame(width: 32, height: 32)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 6)
    .background(
      LinearGradient(
        colors: [WafuuUI.don.opacity(0.08), .clear],
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

  private var recordingHeaderContents: some View {
    Group {
      HStack(spacing: 8) {
        Circle()
          .fill(WafuuUI.don)
          .frame(width: 9, height: 9)
          .shadow(color: WafuuUI.don, radius: 3)
          .opacity(elapsedMs % 1200 < 600 ? 1.0 : 0.4)
        Text("REC")
          .font(WafuuUI.num(11, weight: .semibold))
          .tracking(3)
          .foregroundStyle(WafuuUI.sumi)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(WafuuUI.cardBackground)
      .overlay(
        Capsule().stroke(WafuuUI.woodDeep, lineWidth: 1.5)
      )
      .clipShape(Capsule())

      Spacer()

      Text(formatTimer(elapsedMs))
        .font(WafuuUI.num(24, weight: .medium))
        .tracking(2)
        .foregroundStyle(WafuuUI.sumi)

      Spacer()

      Button(action: stop) {
        Text("停止")
          .font(WafuuUI.gothic(11, weight: .semibold))
          .tracking(2)
          .foregroundStyle(WafuuUI.sumiSoft)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
      }
    }
  }

  // MARK: - Recent Symbols

  private var recentSymbolsRow: some View {
    HStack(spacing: 4) {
      ForEach(Array(recentSymbols.enumerated()), id: \.offset) { _, note in
        symbolBadge(for: note)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .frame(height: 30)
  }

  private func symbolBadge(for note: Note) -> some View {
    let (color, size): (Color, CGFloat)
    switch note.type {
    case .don_l, .don_r:
      color = WafuuUI.don
      size = 16
    case .don_both:
      color = WafuuUI.don
      size = 22
    case .ka_l, .ka_r:
      color = WafuuUI.ka
      size = 12
    }
    return Circle()
      .fill(color)
      .frame(width: size, height: size)
      .overlay(
        Circle().stroke(
          note.type == .don_both ? WafuuUI.gold :
            (note.isHold ? WafuuUI.gold : color.opacity(0.7)),
          lineWidth: note.type == .don_both ? 1.5 : (note.isHold ? 2 : 1)
        )
      )
  }

  // MARK: - Center overlay

  @ViewBuilder
  private var centerOverlay: some View {
    switch phase {
    case .ready:
      Button(action: startCountdown) {
        VStack(spacing: 10) {
          Circle()
            .fill(WafuuUI.don)
            .frame(width: 32, height: 32)
            .shadow(color: WafuuUI.don.opacity(0.5), radius: 8)
          Text("録音開始")
            .font(WafuuUI.serif(18, weight: .bold))
            .tracking(4)
            .foregroundStyle(WafuuUI.sumi)
        }
        .frame(width: 180, height: 180)
        .background(WafuuUI.paper.opacity(0.9))
        .clipShape(Circle())
        .overlay(
          Circle()
            .stroke(WafuuUI.donDim, lineWidth: 2)
        )
        .shadow(color: WafuuUI.don.opacity(0.3), radius: 12, x: 0, y: 4)
      }
      .buttonStyle(.plain)

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

    case .recording:
      EmptyView()
    }
  }

  // MARK: - Actions

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
        phase = .recording
      }
      scene.beginCapture()
      startTimer()
    }
  }

  private func stop() {
    timerTask?.cancel()
    countdownTask?.cancel()
    let chart = scene.makeChartDraft()
    onStopped(chart)
  }

  private func cancel() {
    timerTask?.cancel()
    countdownTask?.cancel()
    onCancel()
  }

  private func startTimer() {
    timerTask?.cancel()
    let start = Date()
    timerTask = Task { @MainActor in
      while !Task.isCancelled {
        elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
    }
  }

  private func formatTimer(_ ms: Int) -> String {
    let totalTenths = ms / 100
    let seconds = totalTenths / 10
    let tenths = totalTenths % 10
    return String(format: "%02d:%02d.%d", seconds / 60, seconds % 60, tenths)
  }
}

#Preview {
  RecordingView(
    onStopped: { _ in },
    onCancel: {}
  )
}
