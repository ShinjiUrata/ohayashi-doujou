import SwiftUI
import SpriteKit

/// 録音画面(SwiftUI)。
///
/// フェーズ:
/// - `.ready`: 中央に「録音開始」ボタン、まだタップは記録されない
/// - `.countdown(n)`: 中央に大きな数字 (3 → 2 → 1) を 1 秒ごとに表示
/// - `.recording`: REC バッジ + タイマー、実際の録音中
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

  private let gold = Color(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0)
  private let cream = Color(red: 0xf5 / 255.0, green: 0xea / 255.0, blue: 0xd0 / 255.0)
  private let rec = Color(red: 0xff / 255.0, green: 0x3b / 255.0, blue: 0x3b / 255.0)

  var body: some View {
    ZStack {
      Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x1d / 255.0)
        .ignoresSafeArea()

      SpriteView(scene: scene, options: [.ignoresSiblingOrder])
        .ignoresSafeArea()

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
    HStack(spacing: 12) {
      // 中断ボタンは常に表示
      Button(action: cancel) {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(gold.opacity(0.7))
          .frame(width: 32, height: 32)
          .background(Color.black.opacity(0.3))
          .clipShape(Circle())
      }

      if case .recording = phase {
        recordingHeaderContents
      } else {
        Spacer()
        Text(phase == .ready ? "録音準備" : "")
          .font(.system(size: 12))
          .tracking(2)
          .foregroundStyle(cream.opacity(0.5))
        Spacer()
        // 右側の空きを X ボタンと対称にするためのダミー
        Color.clear.frame(width: 32, height: 32)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 6)
  }

  private var recordingHeaderContents: some View {
    Group {
      HStack(spacing: 6) {
        Circle()
          .fill(rec)
          .frame(width: 10, height: 10)
          .shadow(color: rec, radius: 6)
          .opacity(elapsedMs % 1200 < 600 ? 1.0 : 0.35)
        Text("REC")
          .font(.system(size: 13, weight: .bold))
          .tracking(2)
          .foregroundStyle(rec)
      }

      Spacer()

      Text(formatTimer(elapsedMs))
        .font(.system(size: 20, weight: .bold, design: .monospaced))
        .tracking(3)
        .foregroundStyle(gold)
        .shadow(color: gold.opacity(0.4), radius: 6)

      Spacer()

      Button(action: stop) {
        Text("■ 停止")
          .font(.system(size: 11, weight: .bold))
          .tracking(2)
          .foregroundStyle(rec)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(rec.opacity(0.12))
          .overlay(
            RoundedRectangle(cornerRadius: 20)
              .stroke(rec.opacity(0.4), lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 20))
      }
    }
  }

  // MARK: - Recent Symbols

  private var recentSymbolsRow: some View {
    HStack(spacing: 4) {
      ForEach(Array(recentSymbols.enumerated()), id: \.offset) { _, note in
        symbolBadge(for: note)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .frame(height: 30)
  }

  private func symbolBadge(for note: Note) -> some View {
    let text: String
    let color: Color
    let size: CGFloat
    switch note.type {
    case .don_l:
      text = "左"; color = Color(red: 0xff / 255.0, green: 0x6b / 255.0, blue: 0x6b / 255.0); size = 22
    case .don_r:
      text = "右"; color = Color(red: 0xff / 255.0, green: 0x6b / 255.0, blue: 0x6b / 255.0); size = 22
    case .don_both:
      text = "両"; color = Color(red: 0xff / 255.0, green: 0x6b / 255.0, blue: 0x6b / 255.0); size = 24
    case .ka_l:
      text = "左"; color = Color(red: 0x8f / 255.0, green: 0xd1 / 255.0, blue: 0xf4 / 255.0); size = 18
    case .ka_r:
      text = "右"; color = Color(red: 0x8f / 255.0, green: 0xd1 / 255.0, blue: 0xf4 / 255.0); size = 18
    }
    return Text(text)
      .font(.system(size: 9, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color)
      .clipShape(Circle())
      .overlay(
        Circle().stroke(
          note.isHold ? gold : .clear,
          lineWidth: note.isHold ? 2 : 0
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
          Image(systemName: "circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(rec)
            .shadow(color: rec.opacity(0.7), radius: 10)
          Text("録音開始")
            .font(.system(size: 18, weight: .bold))
            .tracking(4)
            .foregroundStyle(cream)
        }
        .frame(width: 180, height: 180)
        .background(Color.black.opacity(0.65))
        .clipShape(Circle())
        .overlay(
          Circle()
            .stroke(rec.opacity(0.6), lineWidth: 2)
        )
        .shadow(color: rec.opacity(0.4), radius: 16)
      }
      .buttonStyle(.plain)

    case .countdown(let n):
      Text("\(n)")
        .font(.system(size: 140, weight: .bold, design: .rounded))
        .foregroundStyle(gold)
        .shadow(color: gold.opacity(0.6), radius: 24)
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
