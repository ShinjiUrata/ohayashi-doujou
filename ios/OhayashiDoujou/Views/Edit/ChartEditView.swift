import SwiftUI

/// 譜面編集画面。
///
/// - 譜面名 / 地域名 のテキスト入力
/// - 収録時間・ノーツ数のサマリ
/// - ノーツリスト(時系列、種別バッジ、ホールドマーク)
/// - 調整 / 保存 / 公開する
/// - 破棄 → ライブラリへ(保存せず)
///
/// mockup: `mockups/07_edit_wafuu.html`
struct ChartEditView: View {
  @State private var chart: Chart
  var onSave: (Chart) -> Void
  var onPreview: (Chart) -> Void
  var onPublish: (Chart) -> Void
  var onDiscard: () -> Void

  init(
    chart: Chart,
    onSave: @escaping (Chart) -> Void,
    onPreview: @escaping (Chart) -> Void,
    onPublish: @escaping (Chart) -> Void,
    onDiscard: @escaping () -> Void
  ) {
    self._chart = State(initialValue: chart)
    self.onSave = onSave
    self.onPreview = onPreview
    self.onPublish = onPublish
    self.onDiscard = onDiscard
  }

  var body: some View {
    ZStack {
      WafuuBackground()

      VStack(spacing: 0) {
        AppHeader(title: "譜面を編集", onBack: onDiscard) {
          Button(action: onDiscard) {
            Text("破棄")
              .font(WafuuUI.gothic(11))
              .tracking(2)
              .foregroundStyle(.red.opacity(0.75))
          }
        }
        editBody
        footer
      }
    }
  }

  // MARK: - Body

  private var editBody: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        infoSection
        summarySection
        noteListSection
      }
      .padding(.horizontal, 18)
      .padding(.top, 14)
      .padding(.bottom, 20)
    }
  }

  private var infoSection: some View {
    section(title: "CHART INFO") {
      VStack(alignment: .leading, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text("譜面名")
            .font(WafuuUI.num(9, weight: .semibold))
            .tracking(3)
            .foregroundStyle(WafuuUI.sumiMist)
          TextField("例: 獅子舞 入り囃子", text: $chart.name)
            .textFieldStyle(.plain)
            .font(WafuuUI.gothic(14))
            .foregroundStyle(WafuuUI.sumi)
            .padding(10)
            .background(WafuuUI.paper.opacity(0.7))
            .overlay(
              RoundedRectangle(cornerRadius: 4)
                .stroke(WafuuUI.woodDark, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("地域")
            .font(WafuuUI.num(9, weight: .semibold))
            .tracking(3)
            .foregroundStyle(WafuuUI.sumiMist)
          TextField("例: 下田町", text: $chart.region)
            .textFieldStyle(.plain)
            .font(WafuuUI.gothic(14))
            .foregroundStyle(WafuuUI.sumi)
            .padding(10)
            .background(WafuuUI.paper.opacity(0.7))
            .overlay(
              RoundedRectangle(cornerRadius: 4)
                .stroke(WafuuUI.woodDark, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
      }
    }
  }

  private var summarySection: some View {
    section(title: "SUMMARY") {
      HStack(spacing: 14) {
        summaryCell(k: "時間", v: formatDuration(chart.durationMs))
        summaryCell(k: "ノーツ数", v: "\(chart.notes.count)")
      }
    }
  }

  private func summaryCell(k: String, v: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(k)
        .font(WafuuUI.num(9, weight: .semibold))
        .tracking(2)
        .foregroundStyle(WafuuUI.sumiMist)
      Text(v)
        .font(WafuuUI.num(15, weight: .medium))
        .tracking(1)
        .foregroundStyle(WafuuUI.sumi)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var noteListSection: some View {
    section(title: "NOTES · 時系列") {
      if chart.notes.isEmpty {
        Text("ノーツがまだ記録されていません")
          .font(WafuuUI.gothic(12))
          .foregroundStyle(WafuuUI.sumiSoft)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 12)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(chart.notes.enumerated()), id: \.offset) { _, note in
            HStack(spacing: 10) {
              Text(formatTime(note.t))
                .font(WafuuUI.num(11, weight: .medium))
                .foregroundStyle(WafuuUI.sumiSoft)
                .frame(width: 70, alignment: .leading)
              typeBadge(note.type)
              Spacer()
              if note.isHold, let duration = note.duration {
                HStack(spacing: 4) {
                  Rectangle()
                    .fill(WafuuUI.gold)
                    .frame(width: 18, height: 3)
                    .clipShape(Capsule())
                  Text("\(duration)ms")
                    .font(WafuuUI.num(10, weight: .medium))
                    .foregroundStyle(WafuuUI.gold)
                    .tracking(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(WafuuUI.gold.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
              }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
              Rectangle()
                .fill(WafuuUI.sumi.opacity(0.06))
                .frame(height: 1),
              alignment: .bottom
            )
          }
        }
        .padding(.vertical, 4)
      }
    }
  }

  private func typeBadge(_ type: NoteType) -> some View {
    let text = type.rawValue
    let (bgColor, fg): (Color, Color)
    switch type {
    case .don_l, .don_r:
      bgColor = WafuuUI.don.opacity(0.15)
      fg = WafuuUI.donDim
    case .don_both:
      bgColor = WafuuUI.don.opacity(0.3)
      fg = WafuuUI.donDim
    case .ka_l, .ka_r:
      bgColor = WafuuUI.ka.opacity(0.15)
      fg = WafuuUI.kaDim
    }
    return Text(text)
      .font(WafuuUI.num(10, weight: .semibold))
      .tracking(1)
      .foregroundStyle(fg)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(bgColor)
      .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func section<Content: View>(
    title: String,
    @ViewBuilder _ content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Rectangle().fill(WafuuUI.gold).frame(width: 3, height: 10)
        Text(title)
          .font(WafuuUI.num(10, weight: .semibold))
          .tracking(3)
          .foregroundStyle(WafuuUI.sumiMist)
      }
      content()
    }
    .padding(12)
    .background(WafuuUI.cardBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 2)
  }

  // MARK: - Footer

  private var footer: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        Button(action: { onPreview(trimmed()) }) {
          HStack(spacing: 6) {
            Text("▶")
              .font(.system(size: 12, weight: .bold))
            Text("調整")
          }
        }
        .buttonStyle(SecondaryButtonStyleWafuu(fontSize: 14))
        .disabled(chart.notes.isEmpty)
        .opacity(chart.notes.isEmpty ? 0.4 : 1)

        Button(action: { onSave(trimmed()) }) {
          Text("保存")
        }
        .buttonStyle(GhostButtonStyleWafuu(fontSize: 14))
        .disabled(!isSaveable)
        .opacity(isSaveable ? 1 : 0.4)
      }

      Button(action: { onPublish(trimmed()) }) {
        HStack(spacing: 8) {
          Text("公開する")
          Text("¥1,000")
            .font(WafuuUI.num(15, weight: .medium))
            .tracking(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
      }
      .buttonStyle(PrimaryButtonStyleWafuu(fontSize: 15))
      .disabled(!isPublishable)
      .opacity(isPublishable ? 1 : 0.4)
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 24)
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

  private var isPublishable: Bool {
    isSaveable && !chart.notes.isEmpty
  }

  private var isSaveable: Bool {
    !chart.name.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func trimmed() -> Chart {
    var t = chart
    t.name = chart.name.trimmingCharacters(in: .whitespaces)
    t.region = chart.region.trimmingCharacters(in: .whitespaces)
    return t
  }

  // MARK: - Helpers

  private func formatDuration(_ ms: Int) -> String {
    let seconds = ms / 1000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func formatTime(_ ms: Int) -> String {
    let seconds = ms / 1000
    let millis = ms % 1000
    return String(format: "%d:%02d.%03d", seconds / 60, seconds % 60, millis)
  }
}

#Preview {
  ChartEditView(
    chart: DemoChart.phase2Demo,
    onSave: { _ in },
    onPreview: { _ in },
    onPublish: { _ in },
    onDiscard: {}
  )
}
