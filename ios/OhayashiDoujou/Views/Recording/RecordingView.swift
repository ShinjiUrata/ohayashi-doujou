import SwiftUI
import SpriteKit

/// 録音画面(SwiftUI)。
///
/// - 録音中は REC バッジと経過時間を表示
/// - 停止 → 録音した Chart を編集画面へ渡す
struct RecordingView: View {
  var onStopped: (Chart) -> Void
  var onCancel: () -> Void

  @State private var scene: RecordingScene = {
    let s = RecordingScene(size: CGSize(width: 390, height: 780))
    s.scaleMode = .resizeFill
    return s
  }()

  @State private var elapsedMs: Int = 0
  @State private var recentSymbols: [Note] = []
  @State private var timerTask: Task<Void, Never>?

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
    }
    .statusBarHidden(true)
    .onAppear {
      AudioEngine.shared.start()
      Haptics.shared.prepare()
      scene.onNoteRecorded = { note in
        Task { @MainActor in
          recentSymbols.append(note)
          if recentSymbols.count > 16 { recentSymbols.removeFirst() }
        }
      }
      startTimer()
    }
    .onDisappear {
      timerTask?.cancel()
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 12) {
      Button(action: {
        timerTask?.cancel()
        onCancel()
      }) {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(gold.opacity(0.7))
          .frame(width: 32, height: 32)
          .background(Color.black.opacity(0.3))
          .clipShape(Circle())
      }

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

      Button(action: {
        timerTask?.cancel()
        let chart = scene.makeChartDraft()
        onStopped(chart)
      }) {
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
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 6)
  }

  private var recentSymbolsRow: some View {
    HStack(spacing: 4) {
      ForEach(Array(recentSymbols.enumerated()), id: \.offset) { _, note in
        symbolBadge(for: note)
      }
      Spacer()
    }
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

  // MARK: - Timer

  private func startTimer() {
    timerTask?.cancel()
    let start = Date()
    timerTask = Task { @MainActor in
      while !Task.isCancelled {
        elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
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
