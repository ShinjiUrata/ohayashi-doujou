import SwiftUI

/// 保存済み譜面一覧(メニューから遷移するサブ画面)。
///
/// 機能:
/// - ローカル譜面のカードリスト表示
/// - スワイプで単発削除(通常時のショートカット)
/// - タップ → プレイ
/// - 下部の「新しい譜面をダウンロードする」ボタンで ID 検索/DL 画面へ
/// - 左上に「メニュー」戻るボタン
/// - 右上「選択」→ 複数選択モードで複数譜面を一括削除
///
/// mockup: `mockups/02_library_wafuu.html`
struct ChartLibraryView: View {
  var onPlay: (Chart) -> Void
  var onDownload: () -> Void
  var onBack: () -> Void

  @State private var summaries: [ChartSummary] = []
  @State private var isLoading = true

  // MARK: - 複数選択モード状態
  @State private var isSelectionMode: Bool = false
  @State private var selectedIds: Set<String> = []
  @State private var showDeleteConfirmation: Bool = false

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
    .alert("選択した \(selectedIds.count) 件の譜面を削除しますか?", isPresented: $showDeleteConfirmation) {
      Button("キャンセル", role: .cancel) {}
      Button("削除", role: .destructive) {
        Task {
          await deleteSelectedCharts()
        }
      }
    } message: {
      Text("この操作は取り消せません。")
    }
  }

  // MARK: - Header

  private var header: some View {
    AppHeader(
      title: "譜面ライブラリ",
      onBack: isSelectionMode ? nil : onBack,
      trailing: { headerTrailing }
    )
  }

  /// ヘッダ右側の切替ボタン。
  /// - 通常モード: 「選択」ボタン(0 件時は非表示)
  /// - 選択モード: 「完了」ボタン
  @ViewBuilder
  private var headerTrailing: some View {
    if isSelectionMode {
      Button("完了") {
        exitSelectionMode()
      }
      .font(WafuuUI.gothic(12, weight: .semibold))
      .tracking(1)
      .foregroundStyle(WafuuUI.sumi)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    } else if !summaries.isEmpty {
      Button("選択") {
        enterSelectionMode()
      }
      .font(WafuuUI.gothic(12, weight: .semibold))
      .tracking(1)
      .foregroundStyle(WafuuUI.gold)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    }
  }

  private var subheader: some View {
    HStack {
      if isLoading {
        Text("読み込み中...")
      } else if summaries.isEmpty {
        Text("譜面がまだありません")
      } else if isSelectionMode {
        Text("\(selectedIds.count) 件を選択中")
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
      if isSelectionMode {
        toggleSelection(summary.id)
      } else {
        Task {
          if let chart = try? await ChartStorage.shared.load(id: summary.id) {
            onPlay(chart)
          }
        }
      }
    } label: {
      HStack(spacing: 12) {
        // 選択モード時: 左端にチェック状態を表示
        if isSelectionMode {
          selectionIndicator(isSelected: selectedIds.contains(summary.id))
        }
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
        // 通常モードのみ chevron を表示(選択モードでは邪魔)
        if !isSelectionMode {
          Text("›")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(WafuuUI.gold.opacity(0.5))
        }
      }
      .padding(14)
      .background(WafuuUI.cardBackground)
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(cardBorderColor(for: summary.id), lineWidth: cardBorderWidth(for: summary.id))
      )
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    // スワイプ削除は選択モード中は無効化(選択操作と競合するため)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if !isSelectionMode {
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
  }

  /// 選択状態を示す ○ / ● マーカー。
  private func selectionIndicator(isSelected: Bool) -> some View {
    ZStack {
      Circle()
        .strokeBorder(WafuuUI.gold.opacity(0.7), lineWidth: 1.5)
        .frame(width: 24, height: 24)
      if isSelected {
        Circle()
          .fill(WafuuUI.gold)
          .frame(width: 16, height: 16)
      }
    }
  }

  /// 選択中の card は金色枠 + 太めのボーダーで強調。
  private func cardBorderColor(for id: String) -> Color {
    isSelectionMode && selectedIds.contains(id) ? WafuuUI.gold : WafuuUI.woodDeep
  }

  private func cardBorderWidth(for id: String) -> CGFloat {
    isSelectionMode && selectedIds.contains(id) ? 2.0 : 1.5
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

  /// フッタは選択モードで表示内容を切替:
  /// - 通常モード: 「新しい譜面をダウンロードする」ボタン
  /// - 選択モード: 「N 件を削除」ボタン(0 件時 disable)
  @ViewBuilder
  private var footer: some View {
    if isSelectionMode {
      selectionModeFooter
    } else {
      normalModeFooter
    }
  }

  private var normalModeFooter: some View {
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
    .background(footerBackground)
  }

  private var selectionModeFooter: some View {
    Button(action: {
      guard !selectedIds.isEmpty else { return }
      showDeleteConfirmation = true
    }) {
      Text(selectedIds.isEmpty ? "削除する譜面を選択" : "\(selectedIds.count) 件を削除")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(DangerButtonStyleWafuu(fontSize: 15))
    .disabled(selectedIds.isEmpty)
    .opacity(selectedIds.isEmpty ? 0.45 : 1.0)
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 24)
    .background(footerBackground)
  }

  private var footerBackground: some View {
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
  }

  // MARK: - Selection mode actions

  private func enterSelectionMode() {
    selectedIds.removeAll()
    withAnimation(.easeInOut(duration: 0.15)) {
      isSelectionMode = true
    }
  }

  private func exitSelectionMode() {
    selectedIds.removeAll()
    withAnimation(.easeInOut(duration: 0.15)) {
      isSelectionMode = false
    }
  }

  private func toggleSelection(_ id: String) {
    if selectedIds.contains(id) {
      selectedIds.remove(id)
    } else {
      selectedIds.insert(id)
    }
  }

  private func deleteSelectedCharts() async {
    for id in selectedIds {
      try? await ChartStorage.shared.delete(id: id)
    }
    await refresh()
    // 削除完了後は選択モードを抜ける
    await MainActor.run {
      exitSelectionMode()
    }
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
