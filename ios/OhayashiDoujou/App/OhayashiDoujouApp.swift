import SwiftUI

/// お囃子道場アプリのエントリポイント。
@main
struct OhayashiDoujouApp: App {
  init() {
    // 譜面保存ディレクトリを初回起動時に用意しておく。
    Task.detached {
      try? await ChartStorage.shared.ensureDirectory()
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .preferredColorScheme(.dark)
    }
  }
}
