import SwiftUI

/// アプリのルートビュー。
///
/// Phase 1 ではプレイ画面を直接表示する。
/// Phase 6 でタイトル / メニュー画面を経由するようにする。
struct ContentView: View {
  var body: some View {
    PlayView()
  }
}

#Preview {
  ContentView()
}
