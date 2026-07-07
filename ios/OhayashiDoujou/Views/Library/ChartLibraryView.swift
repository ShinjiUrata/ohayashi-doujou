import SwiftUI

/// 保存済み譜面一覧(アプリのルート画面)。
///
/// Phase 3:
/// - ローカル譜面のカードリスト表示
/// - スワイプで削除
/// - 「録音」ボタン → 新規譜面録音フロー
/// - タップ → プレイ
///
/// Phase 4 以降:
/// - 「IDで入手」ボタンで検索/DL 画面へ
struct ChartLibraryView: View {
  var onPlay: (Chart) -> Void
  var onRecord: () -> Void
  var onDownload: () -> Void

  @State private var summaries: [ChartSummary] = []
  @State private var isLoading = true

  private let gold = Color(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0)
  private let goldDim = Color(red: 0xb8 / 255.0, green: 0x93 / 255.0, blue: 0x5a / 255.0)
  private let cream = Color(red: 0xf5 / 255.0, green: 0xea / 255.0, blue: 0xd0 / 255.0)
  private let panel = Color(red: 0x1d / 255.0, green: 0x1a / 255.0, blue: 0x2a / 255.0)
  private let bg = Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x1d / 255.0)
  private let accent = Color(red: 0xc8 / 255.0, green: 0x21 / 255.0, blue: 0x1d / 255.0)

  var body: some View {
    ZStack {
      bg.ignoresSafeArea()

      VStack(spacing: 0) {
        header
        subheader
        content
        footer
      }
    }
    .foregroundStyle(cream)
    .task {
      await refresh()
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      Spacer().frame(width: 32)
      VStack(spacing: 2) {
        Text("♪ 譜面ライブラリ")
          .font(.system(size: 15, weight: .bold))
          .tracking(2)
          .foregroundStyle(gold)
      }
      Spacer()
      Button(action: onDownload) {
        HStack(spacing: 4) {
          Image(systemName: "plus")
            .font(.system(size: 10, weight: .bold))
          Text("IDで入手")
            .font(.system(size: 11, weight: .semibold))
            .tracking(1)
        }
        .foregroundStyle(gold)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(gold.opacity(0.1))
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(gold.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .background(
      LinearGradient(
        colors: [accent.opacity(0.15), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private var subheader: some View {
    HStack {
      if isLoading {
        Text("読み込み中...")
      } else if summaries.isEmpty {
        Text("譜面がまだありません")
      } else {
        Text("保存済み \(summaries.count) 件 / 作成日順")
      }
      Spacer()
    }
    .font(.system(size: 10))
    .tracking(1)
    .foregroundStyle(cream.opacity(0.5))
    .padding(.horizontal, 20)
    .padding(.bottom, 8)
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
          .padding(.horizontal, 12)
          .padding(.bottom, 16)
        }
      }
    }
    .frame(maxHeight: .infinity)
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer()
      Text("最初の譜面を録音してみましょう")
        .font(.system(size: 14))
        .foregroundStyle(cream.opacity(0.6))
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
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(cream)
            .lineLimit(1)
          HStack(spacing: 10) {
            Text(summary.region.isEmpty ? "—" : summary.region)
              .foregroundStyle(goldDim)
            Text(formatDuration(summary.durationMs))
            Text(formatDate(summary.createdAt))
          }
          .font(.system(size: 11))
          .foregroundStyle(cream.opacity(0.5))
        }
        Spacer()
        Text("›")
          .font(.system(size: 20))
          .foregroundStyle(gold.opacity(0.4))
      }
      .padding(14)
      .background(panel)
      .overlay(
        RoundedRectangle(cornerRadius: 14)
          .stroke(gold.opacity(0.15), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 14))
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
      .font(.system(size: 14, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: 44, height: 44)
      .background(
        RadialGradient(
          colors: [Color(red: 1.0, green: 0.42, blue: 0.42), accent, Color(red: 0.42, green: 0.07, blue: 0.06)],
          center: UnitPoint(x: 0.35, y: 0.30),
          startRadius: 0,
          endRadius: 40
        )
      )
      .clipShape(Circle())
      .shadow(color: accent.opacity(0.4), radius: 6)
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 12) {
      Button(action: onRecord) {
        HStack(spacing: 8) {
          Image(systemName: "circle.fill")
            .font(.system(size: 10))
          Text("録音する")
            .font(.system(size: 15, weight: .bold))
            .tracking(2)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
          LinearGradient(
            colors: [Color(red: 0xdd / 255.0, green: 0x42 / 255.0, blue: 0x38 / 255.0), accent],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: accent.opacity(0.4), radius: 8)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 24)
    .background(
      Color.black.opacity(0.3)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(cream.opacity(0.05)), alignment: .top)
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
    onRecord: {},
    onDownload: {}
  )
  .preferredColorScheme(.dark)
}
