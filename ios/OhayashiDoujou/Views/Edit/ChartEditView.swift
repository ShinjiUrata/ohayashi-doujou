import SwiftUI

/// 譜面編集画面。
///
/// Phase 3 の最小機能:
/// - 譜面名 / 地域名 のテキスト入力
/// - 収録時間・ノーツ数のサマリ
/// - ノーツリスト(時系列、種別バッジ、ホールドマーク)
/// - 保存 → ライブラリへ
/// - 破棄 → ライブラリへ(保存せず)
///
/// Phase 4 で公開ボタン → PublishView への遷移を追加。
/// Phase 6 でノーツ個別削除 UI を追加。
struct ChartEditView: View {
  @State private var chart: Chart
  var onSave: (Chart) -> Void
  var onPreview: (Chart) -> Void
  var onDiscard: () -> Void

  init(
    chart: Chart,
    onSave: @escaping (Chart) -> Void,
    onPreview: @escaping (Chart) -> Void,
    onDiscard: @escaping () -> Void
  ) {
    self._chart = State(initialValue: chart)
    self.onSave = onSave
    self.onPreview = onPreview
    self.onDiscard = onDiscard
  }

  private let gold = Color(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0)
  private let goldDim = Color(red: 0xb8 / 255.0, green: 0x93 / 255.0, blue: 0x5a / 255.0)
  private let cream = Color(red: 0xf5 / 255.0, green: 0xea / 255.0, blue: 0xd0 / 255.0)
  private let panel = Color(red: 0x1d / 255.0, green: 0x1a / 255.0, blue: 0x2a / 255.0)
  private let bg = Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x1d / 255.0)

  var body: some View {
    ZStack {
      bg.ignoresSafeArea()

      VStack(spacing: 0) {
        header
        body_
        footer
      }
    }
    .foregroundStyle(cream)
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      Button(action: onDiscard) {
        Image(systemName: "chevron.left")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(gold.opacity(0.7))
          .frame(width: 32, height: 32)
          .background(Color.black.opacity(0.3))
          .clipShape(Circle())
      }
      Spacer()
      Text("譜面編集")
        .font(.system(size: 14, weight: .bold))
        .tracking(2)
        .foregroundStyle(gold)
      Spacer()
      Button(action: onDiscard) {
        Text("破棄")
          .font(.system(size: 12))
          .foregroundStyle(Color(red: 1.0, green: 0.23, blue: 0.23).opacity(0.75))
          .tracking(1)
      }
      .padding(.trailing, 4)
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 10)
    .background(
      LinearGradient(
        colors: [Color(red: 0x4e / 255.0, green: 0xa7 / 255.0, blue: 0xd9 / 255.0).opacity(0.12), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  // MARK: - Body

  private var body_: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        formBlock(label: "譜面名") {
          TextField("例: 獅子舞 入り囃子", text: $chart.name)
            .textFieldStyle(.plain)
            .foregroundStyle(cream)
            .padding(10)
            .background(panel)
            .overlay(
              RoundedRectangle(cornerRadius: 10)
                .stroke(chart.name.isEmpty ? gold.opacity(0.15) : gold.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }

        formBlock(label: "地域") {
          TextField("例: 下田町", text: $chart.region)
            .textFieldStyle(.plain)
            .foregroundStyle(cream)
            .padding(10)
            .background(panel)
            .overlay(
              RoundedRectangle(cornerRadius: 10)
                .stroke(chart.region.isEmpty ? gold.opacity(0.15) : gold.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }

        summaryBox

        Text("ノーツ(時系列)")
          .font(.system(size: 10))
          .tracking(3)
          .foregroundStyle(gold.opacity(0.7))
          .padding(.top, 4)

        noteList
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 16)
    }
  }

  private func formBlock<Content: View>(
    label: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.system(size: 10))
        .tracking(2)
        .foregroundStyle(gold)
      content()
    }
  }

  private var summaryBox: some View {
    HStack(spacing: 14) {
      summaryCell(k: "時間", v: formatDuration(chart.durationMs))
      summaryCell(k: "ノーツ数", v: "\(chart.notes.count)")
      summaryCell(k: "状態", v: "ドラフト", vColor: Color(red: 0x6b / 255.0, green: 0xc9 / 255.0, blue: 0x8a / 255.0))
    }
    .padding(10)
    .background(panel)
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(gold.opacity(0.15), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private func summaryCell(k: String, v: String, vColor: Color? = nil) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(k)
        .font(.system(size: 10))
        .tracking(1)
        .foregroundStyle(cream.opacity(0.5))
      Text(v)
        .font(.system(size: 13, weight: .bold, design: .monospaced))
        .foregroundStyle(vColor ?? gold)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var noteList: some View {
    VStack(spacing: 0) {
      ForEach(Array(chart.notes.enumerated()), id: \.offset) { _, note in
        HStack(spacing: 10) {
          Text(formatTime(note.t))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(cream.opacity(0.75))
            .frame(width: 70, alignment: .leading)
          typeBadge(note.type)
          Spacer()
          if note.isHold, let duration = note.duration {
            HStack(spacing: 4) {
              Rectangle()
                .fill(gold)
                .frame(width: 18, height: 3)
                .clipShape(Capsule())
              Text("\(duration)ms")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(gold)
                .tracking(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(gold.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(
          Rectangle()
            .fill(Color.white.opacity(0.04))
            .frame(height: 1),
          alignment: .bottom
        )
      }
    }
    .padding(.vertical, 6)
    .background(panel)
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(gold.opacity(0.15), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private func typeBadge(_ type: NoteType) -> some View {
    let text = type.rawValue
    let (bg, fg): (Color, Color)
    switch type {
    case .don_l, .don_r:
      bg = Color(red: 0xe2 / 255.0, green: 0x3b / 255.0, blue: 0x3b / 255.0).opacity(0.2)
      fg = Color(red: 1.0, green: 0.42, blue: 0.42)
    case .don_both:
      bg = Color(red: 0xe2 / 255.0, green: 0x3b / 255.0, blue: 0x3b / 255.0).opacity(0.35)
      fg = Color(red: 1.0, green: 0.85, blue: 0.85)
    case .ka_l, .ka_r:
      bg = Color(red: 0x4e / 255.0, green: 0xa7 / 255.0, blue: 0xd9 / 255.0).opacity(0.2)
      fg = Color(red: 0.56, green: 0.82, blue: 0.96)
    }
    return Text(text)
      .font(.system(size: 10, weight: .semibold, design: .monospaced))
      .tracking(1)
      .foregroundStyle(fg)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(bg)
      .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  // MARK: - Footer

  private var footer: some View {
    VStack(spacing: 0) {
      Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
      HStack(spacing: 8) {
        Button(action: {
          onPreview(trimmed())
        }) {
          HStack(spacing: 6) {
            Image(systemName: "play.fill")
              .font(.system(size: 10))
            Text("試遊")
              .font(.system(size: 14, weight: .bold))
              .tracking(2)
          }
          .foregroundStyle(gold)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(Color(red: 0x26 / 255.0, green: 0x22 / 255.0, blue: 0x3a / 255.0))
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(gold.opacity(0.35), lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(chart.notes.isEmpty)
        .opacity(chart.notes.isEmpty ? 0.4 : 1.0)

        Button(action: {
          onSave(trimmed())
        }) {
          Text("保存")
            .font(.system(size: 14, weight: .bold))
            .tracking(2)
            .foregroundStyle(cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(panel)
            .overlay(
              RoundedRectangle(cornerRadius: 12)
                .stroke(gold.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!isSaveable)
        .opacity(isSaveable ? 1.0 : 0.4)
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 20)
      .background(Color.black.opacity(0.3))
    }
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
    onDiscard: {}
  )
  .preferredColorScheme(.dark)
}
