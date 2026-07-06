import SwiftUI
import SpriteKit

/// プレイ画面。
///
/// Phase 1 では SpriteKit の `PlayScene` を全画面表示する最小構成。
/// Phase 2 以降でヘッダ(スコア / コンボ)、ポーズ、リザルト遷移を追加。
struct PlayView: View {
  @State private var scene: PlayScene = {
    let scene = PlayScene(size: CGSize(width: 390, height: 780))
    scene.scaleMode = .resizeFill
    return scene
  }()

  var body: some View {
    ZStack {
      Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x1d / 255.0)
        .ignoresSafeArea()

      SpriteView(scene: scene, options: [.ignoresSiblingOrder])
        .ignoresSafeArea()
    }
    .statusBarHidden(true)
    .onAppear {
      AudioEngine.shared.start()
      Haptics.shared.prepare()
    }
  }
}

#Preview {
  PlayView()
}
