import SwiftUI

/// アプリのルートビュー。
///
/// Phase 3 では以下 5 画面のルーティングハブとして機能する:
/// - ライブラリ(root)
/// - プレイ → リザルト
/// - 録音 → 編集
///
/// Phase 6 でタイトル / メニュー画面を root に追加予定。
struct ContentView: View {
  enum Route: Equatable {
    case library
    case playing(Chart)
    case result(Chart, ScoreState)
    case recording
    case editing(Chart)
  }

  @State private var route: Route = .library
  @State private var playRunID: UUID = UUID()

  var body: some View {
    ZStack {
      switch route {
      case .library:
        ChartLibraryView(
          onPlay: { chart in
            playRunID = UUID()
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .playing(chart)
            }
          },
          onRecord: {
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .recording
            }
          }
        )
        .transition(.opacity)

      case .playing(let chart):
        PlayView(
          chart: chart,
          onFinished: { finalScore in
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .result(chart, finalScore)
            }
          },
          onQuit: {
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .library
            }
          }
        )
        .id(playRunID)
        .transition(.opacity)

      case .result(let chart, let score):
        ResultView(
          chart: chart,
          score: score,
          onRetry: {
            playRunID = UUID()
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .playing(chart)
            }
          },
          onDismiss: {
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .library
            }
          }
        )
        .transition(.opacity)

      case .recording:
        RecordingView(
          onStopped: { draft in
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .editing(draft)
            }
          },
          onCancel: {
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .library
            }
          }
        )
        .transition(.opacity)

      case .editing(let chart):
        ChartEditView(
          chart: chart,
          onSave: { edited in
            Task {
              // 実際の永続化 ID を確定させる(ドラフト UUID から譜面名ベースにするか、
              // 現状は同じ UUID を維持する簡素な運用)
              try? await ChartStorage.shared.save(edited)
              await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                  route = .library
                }
              }
            }
          },
          onDiscard: {
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .library
            }
          }
        )
        .transition(.opacity)
      }
    }
  }
}

#Preview {
  ContentView()
    .preferredColorScheme(.dark)
}
