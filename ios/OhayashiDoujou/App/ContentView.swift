import SwiftUI

/// アプリのルートビュー。
///
/// Phase 3 では以下のルーティングハブとして機能する:
/// - ライブラリ(root)
/// - プレイ → リザルト → ライブラリ
/// - 録音 → 編集 → 保存 → ライブラリ
/// - 編集からの試遊: 編集 → 試遊プレイ → 試遊リザルト → 編集
///
/// Phase 6 でタイトル / メニュー画面を root に追加予定。
struct ContentView: View {
  enum Route: Equatable {
    case library
    case playing(Chart)
    case result(Chart, ScoreState)
    case recording
    case editing(Chart)
    /// 編集画面からの試遊プレイ。終了時は編集画面へ戻る。
    case previewingDraft(Chart)
    /// 試遊のリザルト画面。「もう一度」で試遊再突入、「戻る」で編集へ戻る。
    case previewResult(Chart, ScoreState)
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
              try? await ChartStorage.shared.save(edited)
              await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                  route = .library
                }
              }
            }
          },
          onPreview: { draft in
            playRunID = UUID()
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .previewingDraft(draft)
            }
          },
          onDiscard: {
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .library
            }
          }
        )
        .transition(.opacity)

      case .previewingDraft(let draft):
        PlayView(
          chart: draft,
          onFinished: { finalScore in
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .previewResult(draft, finalScore)
            }
          },
          onQuit: {
            // 試遊中の中断は編集画面に戻る(録音した内容を失わない)
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .editing(draft)
            }
          }
        )
        .id(playRunID)
        .transition(.opacity)

      case .previewResult(let draft, let score):
        ResultView(
          chart: draft,
          score: score,
          onRetry: {
            playRunID = UUID()
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .previewingDraft(draft)
            }
          },
          onDismiss: {
            // 試遊のリザルトから戻ると編集画面へ復帰
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .editing(draft)
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
