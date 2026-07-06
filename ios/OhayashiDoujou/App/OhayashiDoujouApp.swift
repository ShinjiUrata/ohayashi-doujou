import SwiftUI

/// お囃子道場アプリのエントリポイント。
@main
struct OhayashiDoujouApp: App {
  init() {
    // 譜面保存ディレクトリの初期化 + 初回起動時のデモ譜面シード。
    Task.detached {
      try? await ChartStorage.shared.ensureDirectory()
      try? await ChartStorage.shared.seedIfEmpty(DemoChart.phase2Demo)
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .preferredColorScheme(.dark)
    }
  }
}
