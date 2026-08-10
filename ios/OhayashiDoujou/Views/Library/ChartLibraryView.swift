import SwiftUI

/// 保存済み譜面一覧(メニューから遷移するサブ画面)。
///
/// 機能:
/// - ローカル譜面のカードリスト表示
/// - スワイプで削除
/// - タップ → プレイ
/// - 下部の「新しい譜面をダウンロードする」ボタンで ID 検索/DL 画面へ
/// - 左上に「メニュー」戻るボタン
///
/// mockup: `mockups/02_library_wafuu.html`
struct ChartLibraryView: View {
  var onPlay: (Chart) -> Void
  var onDownload: () -> Void
  var onBack: () -> Void

  @State private var summaries: [ChartSummary] = []
  @State private var isLoading = true

  var body: some View {
    ZStack {
      WafuuBackground()

      VStack(spacing: 0) {
        header
        subheader
        content
        footer
      }
    }
    .task {
      await refresh()
    }
  }

  // MARK: - Header

  private var header: some View {
    AppHeader(title: "譜面ライブラリ", onBack: onBack)
  }

  private var subheader: some View {
    HStack {
      if isLoading {
        Text("読み込み中...")
      } else if summaries.isEmpty {
        Text("譜面がまだありません")
      } else {
        Text("保存済み \(summaries.count) 件")
      }
      Spacer()
    }
    .font(WafuuUI.num(10, weight: .medium))
    .tracking(3)
    .foregroundStyle(WafuuUI.sumiMist)
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
  }

  // MARK: - Content

  private var content: some View {
    Group {
      if summaries.isEmpty && !isLoading {
        emptyState
      } else {
        ScrollView {
          LazyVStack(spacing: 10) {
            ForEach(summaries, id: \.id) { summary in
              chartCard(summary)
            }
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 16)
        }
      }
    }
    .frame(maxHeight: .infinity)
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer()
      Text("譜面をダウンロードしてみましょう")
        .font(WafuuUI.serif(14, weight: .regular))
        .foregroundStyle(WafuuUI.sumiSoft)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private func chartCard(_ summary: ChartSummary) -> some View {
    Button {
      Task {
        if let chart = try? await ChartStorage.shared.load(id: summary.id) {
          onPlay(chart)
        }
      }
    } label: {
      HStack(spacing: 12) {
        icon(for: summary.name)
        VStack(alignment: .leading, spacing: 4) {
          Text(summary.name)
            .font(WafuuUI.serif(15, weight: .bold))
            .tracking(1)
            .foregroundStyle(WafuuUI.sumi)
            .lineLimit(1)
          HStack(spacing: 10) {
            Text(summary.region.isEmpty ? "—" : summary.region)
              .foregroundStyle(WafuuUI.gold)
            Text(formatDuration(summary.durationMs))
              .font(WafuuUI.num(10))
              .foregroundStyle(WafuuUI.sumiSoft)
            Text(formatDate(summary.createdAt))
              .font(WafuuUI.num(10))
              .foregroundStyle(WafuuUI.sumiSoft.opacity(0.7))
          }
          .font(WafuuUI.gothic(11))
          .tracking(1)
        }
        Spacer()
        Text("›")
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(WafuuUI.gold.opacity(0.5))
      }
      .padding(14)
      .background(WafuuUI.cardBackground)
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
      )
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(role: .destructive) {
        Task {
          try? await ChartStorage.shared.delete(id: summary.id)
          await refresh()
        }
      } label: {
        Label("削除", systemImage: "trash")
      }
    }
  }

  private func icon(for name: String) -> some View {
    let firstChar = String(name.prefix(1))
    return Text(firstChar)
      .font(WafuuUI.serif(15, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: 44, height: 44)
      .background(
        RadialGradient(
          colors: [WafuuUI.donHi, WafuuUI.don, WafuuUI.donDim],
          center: UnitPoint(x: 0.35, y: 0.30),
          startRadius: 0,
          endRadius: 40
        )
      )
      .clipShape(Circle())
      .shadow(color: WafuuUI.don.opacity(0.35), radius: 3, x: 0, y: 2)
  }

  // MARK: - Footer

  private var footer: some View {
    Button(action: onDownload) {
      HStack(spacing: 10) {
        Circle()
          .fill(.white)
          .frame(width: 10, height: 10)
        Text("新しい譜面をダウンロードする")
      }
    }
    .buttonStyle(PrimaryButtonStyleWafuu(fontSize: 15))
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 24)
    .background(
      LinearGradient(
        colors: [.clear, WafuuUI.moss.opacity(0.10)],
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

  private func refresh() async {
    isLoading = true
    let result = (try? await ChartStorage.shared.list()) ?? []
    summaries = result
    isLoading = false
  }

  private func formatDuration(_ ms: Int) -> String {
    let seconds = ms / 1000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}

#Preview {
  ChartLibraryView(
    onPlay: { _ in },
    onDownload: {},
    onBack: {}
  )
}
