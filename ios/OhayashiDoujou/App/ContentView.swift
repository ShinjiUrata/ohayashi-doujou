import SwiftUI

/// アプリのルートビュー。
///
/// ルーティングハブ:
/// - メインメニュー(root)
/// - メニュー → ライブラリ → プレイ → リザルト → ライブラリ
/// - メニュー → 録音 → 編集 → 保存 → ライブラリ
/// - 編集からの試遊: 編集 → 試遊プレイ → 試遊リザルト → 編集
/// - メニュー → 譜面DL → ライブラリ
struct ContentView: View {
  enum Route: Equatable {
    case mainMenu
    case library
    case playing(Chart)
    case result(Chart, ScoreState)
    case recording
    case editing(Chart)
    /// 編集画面からの試遊プレイ。終了時は編集画面へ戻る。
    case previewingDraft(Chart)
    /// 試遊のリザルト画面。「もう一度」で試遊再突入、「戻る」で編集へ戻る。
    case previewResult(Chart, ScoreState)
    /// 譜面検索 / DL 画面。ID 入力 → GCS 取得 → ライブラリへ戻る。
    case downloading
    /// 譜面公開画面。編集画面から遷移、公開成功でライブラリへ。
    case publishing(Chart)
  }

  @State private var route: Route = .mainMenu
  @State private var playRunID: UUID = UUID()

  var body: some View {
    ZStack {
      switch route {
      case .mainMenu:
        MainMenuView(
          onSelectLibrary: {
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .library
            }
          },
          onRecord: {
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .recording
            }
          },
          onDownload: {
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .downloading
            }
          }
        )
        .transition(.opacity)

      case .library:
        ChartLibraryView(
          onPlay: { chart in
            playRunID = UUID()
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .playing(chart)
            }
          },
          onDownload: {
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .downloading
            }
          },
          onBack: {
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .mainMenu
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
              route = .mainMenu
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
          onPublish: { draft in
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .publishing(draft)
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
        // 試遊 = 自動再生プレビュー(タッチ判定なし、譜面通りに音のみ再生)
        // 停止中はノーツ位置微調整が可能。編集された chart は onAutoPlayExit
        // で受け取り、編集画面へ復帰する際に反映する。
        PlayView(
          chart: draft,
          mode: .autoPlay,
          onFinished: { _ in },  // autoPlay では未使用
          onQuit: {},            // autoPlay では未使用
          onAutoPlayExit: { editedChart in
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .editing(editedChart)
            }
          }
        )
        .id(playRunID)
        .transition(.opacity)

      case .previewResult(let draft, let score):
        // 現状の自動再生プレビューでは経由しないが、Route enum の
        // 互換性維持のため case は残す。到達したら編集画面へ復帰。
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
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .editing(draft)
            }
          }
        )
        .transition(.opacity)

      case .downloading:
        ChartDownloadView(
          onDownloaded: { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .library
            }
          },
          onCancel: {
            withAnimation(.easeInOut(duration: 0.2)) {
              route = .library
            }
          }
        )
        .transition(.opacity)

      case .publishing(let chart):
        ChartPublishView(
          chart: chart,
          onDismiss: {
            // 公開せず戻る場合は編集画面に復帰(入力内容を保持)
            withAnimation(.easeInOut(duration: 0.25)) {
              route = .editing(chart)
            }
          },
          onPublished: { _ in
            // 公開成功 → ライブラリへ復帰
            withAnimation(.easeInOut(duration: 0.25)) {
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
