import SwiftUI

/// リザルト画面。
///
/// - 総合スコア(大表示)
/// - ランク(漢字 1 文字 / 甲・乙・丙・丁)
/// - 良 / 可 / 不可 / 最大コンボ の内訳
/// - リトライ / タイトルへ戻る
///
/// mockup: `mockups/05_result_wafuu.html`
struct ResultView: View {
  let chart: Chart
  let score: ScoreState
  var onRetry: () -> Void
  var onDismiss: () -> Void

  var body: some View {
    ZStack {
      WafuuBackground()

      VStack(spacing: 0) {
        chartHeader
        scoreHero
        judgeBreakdown
        statsRow
        Spacer(minLength: 12)
        actions
      }
    }
  }

  // MARK: - Header (chart info)

  private var chartHeader: some View {
    VStack(spacing: 4) {
      Text(clearedText)
        .font(WafuuUI.num(11, weight: .semibold))
        .tracking(4)
        .foregroundStyle(WafuuUI.gold)
      Text(chart.name)
        .font(WafuuUI.serif(17, weight: .bold))
        .tracking(3)
        .foregroundStyle(WafuuUI.sumi)
        .padding(.top, 2)
      Text("\(chart.region.isEmpty ? "—" : chart.region) / \(formatDuration(chart.durationMs))")
        .font(WafuuUI.gothic(11))
        .tracking(2)
        .foregroundStyle(WafuuUI.sumiSoft)
    }
    .padding(.top, 68)
    .padding(.bottom, 12)
  }

  /// 譜面が生成する判定の総数。
  /// - 単発ノーツ: 1 判定
  /// - ホールドノーツ (duration > 0): 頭 + 尾 = 2 判定
  private var totalJudgments: Int {
    let holdCount = chart.notes.filter { ($0.duration ?? 0) > 0 }.count
    return chart.notes.count + holdCount
  }

  private var clearedText: String {
    if totalJudgments == 0 { return "PLAY END" }
    // PERFECT: 判定が全て「良」(可・不可なし)
    if score.miss == 0 && score.ok == 0 && score.good == totalJudgments {
      return "PERFECT CLEAR"
    }
    // FULL COMBO: 不可なし
    if score.miss == 0 { return "FULL COMBO" }
    return "CLEAR"
  }

  // MARK: - Score hero

  private var scoreHero: some View {
    VStack(spacing: 6) {
      Text(rank)
        .font(WafuuUI.serif(60, weight: .black))
        .tracking(4)
        .foregroundStyle(WafuuUI.don)
        .shadow(color: WafuuUI.don.opacity(0.35), radius: 8, x: 0, y: 4)
        .lineLimit(1)

      Text("RANK")
        .font(WafuuUI.num(10, weight: .semibold))
        .tracking(4)
        .foregroundStyle(WafuuUI.sumiMist)

      Text(formattedScore(score.totalScore))
        .font(WafuuUI.num(48, weight: .medium))
        .tracking(3)
        .foregroundStyle(WafuuUI.sumi)
        .padding(.top, 8)
        .minimumScaleFactor(0.6)
        .lineLimit(1)

      Text("TOTAL SCORE")
        .font(WafuuUI.num(10, weight: .semibold))
        .tracking(4)
        .foregroundStyle(WafuuUI.sumiMist)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 24)
    .frame(maxWidth: .infinity)
    .background(
      LinearGradient(
        colors: [WafuuUI.gold.opacity(0.08), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .overlay(
      Rectangle()
        .fill(WafuuUI.sumi.opacity(0.12))
        .frame(height: 1),
      alignment: .bottom
    )
  }

  private var rank: String {
    let total = max(totalJudgments, 1)
    // 良判定の比率でランク(可はランクに加算しない)
    let ratio = Double(score.good) / Double(total)
    switch ratio {
    case 1.0: return "甲"
    case 0.8...: return "乙"
    case 0.5...: return "丙"
    default: return "丁"
    }
  }

  // MARK: - Judge breakdown

  private var judgeBreakdown: some View {
    HStack(spacing: 10) {
      judgeCell(kanji: "良", count: score.good, valueColor: WafuuUI.gold)
      judgeCell(kanji: "可", count: score.ok, valueColor: WafuuUI.kaDim)
      judgeCell(kanji: "不可", count: score.miss, valueColor: WafuuUI.sumiSoft)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 20)
  }

  private func judgeCell(kanji: String, count: Int, valueColor: Color) -> some View {
    VStack(spacing: 4) {
      Text(kanji)
        .font(WafuuUI.serif(13, weight: .bold))
        .tracking(3)
        .foregroundStyle(WafuuUI.sumi)
      Text("\(count)")
        .font(WafuuUI.num(26, weight: .medium))
        .tracking(1)
        .foregroundStyle(valueColor)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(
      LinearGradient(
        colors: [WafuuUI.woodLight, WafuuUI.woodMid],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 2)
  }

  // MARK: - Stats

  private var statsRow: some View {
    HStack(spacing: 10) {
      statCard(label: "MAX COMBO", value: "\(score.maxCombo)", color: WafuuUI.donDim)
      statCard(label: "ACCURACY", value: accuracyText, color: WafuuUI.sumi)
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 16)
  }

  private var accuracyText: String {
    guard totalJudgments > 0 else { return "—" }
    let hits = score.good + score.ok
    // ホールドは頭 + 尾 の 2 判定なので分母も 2 倍しないと 100% を超え得る
    let pct = min(100, Int(Double(hits) / Double(totalJudgments) * 100))
    return "\(pct)%"
  }

  private func statCard(label: String, value: String, color: Color) -> some View {
    VStack(spacing: 2) {
      Text(label)
        .font(WafuuUI.num(9, weight: .semibold))
        .tracking(3)
        .foregroundStyle(WafuuUI.sumiMist)
      Text(value)
        .font(WafuuUI.num(22, weight: .medium))
        .tracking(1)
        .foregroundStyle(color)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(WafuuUI.paper.opacity(0.55))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(WafuuUI.sumi.opacity(0.28), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  // MARK: - Actions

  private var actions: some View {
    VStack(spacing: 10) {
      Button(action: onRetry) {
        Text("もう一度")
      }
      .buttonStyle(PrimaryButtonStyleWafuu(fontSize: 15))

      Button(action: onDismiss) {
        Text("ライブラリへ戻る")
      }
      .buttonStyle(SecondaryButtonStyleWafuu(fontSize: 14))
    }
    .padding(.horizontal, 24)
    .padding(.top, 12)
    .padding(.bottom, 28)
    .background(
      LinearGradient(
        colors: [.clear, WafuuUI.moss.opacity(0.08)],
        startPoint: .top,
        endPoint: .bottom
      )
      .overlay(
        Rectangle()
          .fill(WafuuUI.sumi.opacity(0.12))
          .frame(height: 1),
        alignment: .top
      )
    )
  }

  // MARK: - Helpers

  private func formatDuration(_ ms: Int) -> String {
    let seconds = ms / 1000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func formattedScore(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
  }
}

#Preview {
  ResultView(
    chart: DemoChart.phase2Demo,
    score: {
      var s = ScoreState()
      for _ in 0..<42 { s.record(.good) }
      for _ in 0..<8 { s.record(.ok) }
      for _ in 0..<3 { s.record(.miss) }
      return s
    }(),
    onRetry: {},
    onDismiss: {}
  )
}
