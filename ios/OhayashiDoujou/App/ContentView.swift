import SwiftUI

/// アプリのルートビュー。
///
/// Phase 2 では「プレイ画面 → リザルト画面」の 2 状態を持つ。
/// Phase 3 以降で ChartLibraryView / TitleView などが加わる想定。
struct ContentView: View {
  enum Screen {
    case playing
    case result(ScoreState)
  }

  @State private var screen: Screen = .playing
  @State private var playRunID: UUID = UUID()

  private let chart: Chart = DemoChart.phase2Demo

  var body: some View {
    ZStack {
      switch screen {
      case .playing:
        PlayView(
          chart: chart,
          onFinished: { finalScore in
            withAnimation(.easeInOut(duration: 0.25)) {
              screen = .result(finalScore)
            }
          },
          onQuit: {
            // Phase 3 以降で ChartLibrary に戻る。Phase 2 ではリザルト画面に遷移して代替。
            withAnimation(.easeInOut(duration: 0.25)) {
              screen = .result(ScoreState())
            }
          }
        )
        .id(playRunID)

      case .result(let score):
        ResultView(
          chart: chart,
          score: score,
          onRetry: {
            playRunID = UUID()
            withAnimation(.easeInOut(duration: 0.25)) {
              screen = .playing
            }
          },
          onDismiss: {
            // Phase 3 以降で ChartLibrary へ。Phase 2 ではリトライと同じ挙動で代替。
            playRunID = UUID()
            withAnimation(.easeInOut(duration: 0.25)) {
              screen = .playing
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
