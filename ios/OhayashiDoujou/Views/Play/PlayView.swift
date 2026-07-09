import SwiftUI
import SpriteKit

/// プレイ画面。
///
/// Phase 2:
/// - `Chart` を受け取って再生
/// - ヘッダにスコア + コンボ表示
/// - `PlayScene` からの終了コールバックで onFinished を呼ぶ
struct PlayView: View {
  let chart: Chart
  var onFinished: (ScoreState) -> Void
  var onQuit: () -> Void

  @State private var score = ScoreState()
  @State private var scene: PlayScene = {
    let s = PlayScene(size: CGSize(width: 390, height: 780))
    s.scaleMode = .resizeFill
    return s
  }()

  private let gold = Color(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0)
  private let cream = Color(red: 0xf5 / 255.0, green: 0xea / 255.0, blue: 0xd0 / 255.0)

  var body: some View {
    ZStack {
      Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x1d / 255.0)
        .ignoresSafeArea()

      SpriteView(scene: scene, options: [.ignoresSiblingOrder])
        .ignoresSafeArea()

      VStack {
        header
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
    }
    .statusBarHidden(true)
    .onAppear {
      AudioEngine.shared.start()
      Haptics.shared.prepare()
      wireScene()
      scene.load(chart: chart)
    }
  }

  private var header: some View {
    HStack(alignment: .top) {
      Button(action: onQuit) {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(gold.opacity(0.7))
          .frame(width: 32, height: 32)
          .background(Color.black.opacity(0.3))
          .clipShape(Circle())
      }

      VStack(alignment: .leading, spacing: 2) {
        Text("♪ お囃子の練習")
          .font(.system(size: 13, weight: .semibold))
          .tracking(2)
          .foregroundStyle(gold)
        Text("\(chart.name) / \(chart.region)")
          .font(.system(size: 10))
          .foregroundStyle(cream.opacity(0.6))
      }
      .padding(.leading, 4)

      Spacer()

      VStack(alignment: .trailing, spacing: 2) {
        Text(formattedScore(score.totalScore))
          .font(.system(size: 20, weight: .bold, design: .monospaced))
          .foregroundStyle(gold)
        HStack(spacing: 6) {
          Text("COMBO")
            .font(.system(size: 9))
            .tracking(1)
            .foregroundStyle(cream.opacity(0.6))
          Text("\(score.combo)")
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(gold)
        }
      }
    }
  }

  private func wireScene() {
    scene.onScoreChanged = { newScore in
      score = newScore
    }
    scene.onFinished = { finalScore in
      score = finalScore
      onFinished(finalScore)
    }
  }

  private func formattedScore(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
  }
}

#Preview {
  PlayView(
    chart: DemoChart.phase2Demo,
    onFinished: { _ in },
    onQuit: {}
  )
}
