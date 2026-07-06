import SwiftUI

/// リザルト画面。
///
/// Phase 2 の最小構成:
/// - 総合スコア(大表示)
/// - 星評価(5 段階)
/// - 良 / 可 / 不可 / 最大コンボの内訳
/// - リトライ / タイトルへ戻る
struct ResultView: View {
  let chart: Chart
  let score: ScoreState
  var onRetry: () -> Void
  var onDismiss: () -> Void

  private let gold = Color(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0)
  private let cream = Color(red: 0xf5 / 255.0, green: 0xea / 255.0, blue: 0xd0 / 255.0)
  private let panel = Color(red: 0x1d / 255.0, green: 0x1a / 255.0, blue: 0x2a / 255.0)
  private let accent = Color(red: 0xc8 / 255.0, green: 0x21 / 255.0, blue: 0x1d / 255.0)

  var body: some View {
    ZStack {
      // 背景グラデーション
      RadialGradient(
        colors: [
          Color(red: 0x2a / 255.0, green: 0x1a / 255.0, blue: 0x2a / 255.0),
          Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x1d / 255.0),
        ],
        center: .top,
        startRadius: 40,
        endRadius: 600
      )
      .ignoresSafeArea()

      VStack(spacing: 16) {
        header
        chartInfo
        stars
        scoreValue
        breakdown
        Spacer()
        buttons
      }
      .padding(.horizontal, 24)
      .padding(.top, 40)
      .padding(.bottom, 32)
    }
    .foregroundStyle(cream)
  }

  private var header: some View {
    VStack(spacing: 2) {
      Text("RESULT")
        .font(.system(size: 11, weight: .semibold))
        .tracking(4)
        .foregroundStyle(gold.opacity(0.7))
      Text("結果発表")
        .font(.system(size: 24, weight: .bold))
        .tracking(6)
        .foregroundStyle(gold)
        .shadow(color: gold.opacity(0.5), radius: 12)
    }
  }

  private var chartInfo: some View {
    VStack(spacing: 2) {
      Text(chart.name)
        .font(.system(size: 14, weight: .semibold))
      Text("\(chart.region) / \(formatDuration(chart.durationMs))")
        .font(.system(size: 10))
        .foregroundStyle(cream.opacity(0.5))
        .tracking(1)
    }
  }

  private var stars: some View {
    let count = score.stars(totalExpected: chart.notes.count)
    return HStack(spacing: 6) {
      ForEach(0..<5, id: \.self) { i in
        Image(systemName: i < count ? "star.fill" : "star")
          .font(.system(size: 26))
          .foregroundStyle(i < count ? gold : gold.opacity(0.2))
          .shadow(color: i < count ? gold.opacity(0.6) : .clear, radius: 8)
      }
    }
    .padding(.vertical, 4)
  }

  private var scoreValue: some View {
    VStack(spacing: 2) {
      Text("SCORE")
        .font(.system(size: 10, weight: .semibold))
        .tracking(3)
        .foregroundStyle(gold.opacity(0.7))
      Text(formattedScore(score.totalScore))
        .font(.system(size: 52, weight: .bold, design: .monospaced))
        .tracking(2)
        .foregroundStyle(gold)
        .shadow(color: gold.opacity(0.4), radius: 20)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
  }

  private var breakdown: some View {
    HStack {
      statCell(label: "良", value: score.good, color: gold)
      statCell(label: "最大コンボ", value: score.maxCombo, color: gold)
      statCell(label: "可", value: score.ok, color: Color(red: 0x6b / 255.0, green: 0xc9 / 255.0, blue: 0x8a / 255.0))
      statCell(label: "不可", value: score.miss, color: Color(white: 0.55))
    }
    .padding(12)
    .background(panel)
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(gold.opacity(0.25), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private func statCell(label: String, value: Int, color: Color) -> some View {
    VStack(spacing: 4) {
      Text(label)
        .font(.system(size: 10))
        .tracking(1)
        .foregroundStyle(cream.opacity(0.6))
      Text("\(value)")
        .font(.system(size: 18, weight: .bold, design: .monospaced))
        .foregroundStyle(color)
    }
    .frame(maxWidth: .infinity)
  }

  private var buttons: some View {
    VStack(spacing: 10) {
      Button(action: onRetry) {
        Text("もう一度 プレイ")
          .font(.system(size: 15, weight: .bold))
          .tracking(3)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 15)
          .background(
            LinearGradient(
              colors: [Color(red: 0xdd / 255.0, green: 0x42 / 255.0, blue: 0x38 / 255.0), accent],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .clipShape(RoundedRectangle(cornerRadius: 14))
          .shadow(color: accent.opacity(0.5), radius: 12)
      }

      Button(action: onDismiss) {
        Text("一覧に戻る")
          .font(.system(size: 15, weight: .bold))
          .tracking(3)
          .foregroundStyle(cream)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 15)
          .background(panel)
          .overlay(
            RoundedRectangle(cornerRadius: 14)
              .stroke(gold.opacity(0.25), lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 14))
      }
    }
  }

  // MARK: - Helpers

  private func formatDuration(_ ms: Int) -> String {
    let seconds = ms / 1000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func formattedScore(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
  }
}

#Preview {
  ResultView(
    chart: DemoChart.phase2Demo,
    score: {
      var s = ScoreState()
      for _ in 0..<18 { s.record(.good) }
      for _ in 0..<3 { s.record(.ok) }
      s.record(.miss)
      return s
    }(),
    onRetry: {},
    onDismiss: {}
  )
  .preferredColorScheme(.dark)
}
