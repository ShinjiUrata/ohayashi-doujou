import SwiftUI

/// 譜面検索 / ダウンロード画面。
///
/// - ID 入力(小英数ハイフン、3〜64 文字)
/// - 既に保存済みなら DL スキップ
/// - GCS から匿名 GET → ローカルに保存 → 一覧へ戻る
///
/// mockup: `mockups/03_download_wafuu.html`
struct ChartDownloadView: View {
  var onDownloaded: (Chart) -> Void
  var onCancel: () -> Void

  @State private var idInput: String = ""
  @State private var phase: Phase = .idle

  enum Phase: Equatable {
    case idle
    case downloading
    case success(Chart)
    case error(String)
    case alreadySaved(Chart)
  }

  var body: some View {
    ZStack {
      WafuuBackground()

      VStack(spacing: 0) {
        AppHeader(title: "譜面をダウンロード", onBack: onCancel)
        content
      }
    }
  }

  // MARK: - Content

  private var content: some View {
    ScrollView {
      VStack(spacing: 20) {
        hero
        form
        Spacer(minLength: 20)
      }
      .padding(.horizontal, 24)
      .padding(.top, 26)
      .padding(.bottom, 40)
    }
  }

  private var hero: some View {
    VStack(spacing: 8) {
      Text("譜面 ID を入力")
        .font(WafuuUI.serif(24, weight: .bold))
        .tracking(6)
        .foregroundStyle(WafuuUI.sumi)

      Text("制作者から共有された ID を入力してダウンロード。")
        .font(WafuuUI.gothic(12))
        .tracking(2)
        .foregroundStyle(WafuuUI.sumiSoft)
        .multilineTextAlignment(.center)
    }
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("CHART ID")
        .font(WafuuUI.num(9, weight: .semibold))
        .tracking(3)
        .foregroundStyle(WafuuUI.sumiMist)
        .frame(maxWidth: .infinity, alignment: .center)

      TextField("shimoda-2026-a7Kp", text: $idInput)
        .textFieldStyle(.plain)
        .font(WafuuUI.num(20, weight: .medium))
        .tracking(3)
        .foregroundStyle(WafuuUI.sumi)
        .multilineTextAlignment(.center)
        .autocorrectionDisabled(true)
        .textInputAutocapitalization(.never)
        .padding(14)
        .background(WafuuUI.paper.opacity(0.7))
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(borderColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onChange(of: idInput) { _, new in
          idInput = new.lowercased().filter {
            $0.isLetter || $0.isNumber || $0 == "-"
          }
          if case .error = phase { phase = .idle }
        }

      Text("3〜64 文字 / 小文字英字・数字・ハイフン")
        .font(WafuuUI.num(10, weight: .regular))
        .tracking(1)
        .foregroundStyle(WafuuUI.sumiMist)
        .frame(maxWidth: .infinity, alignment: .center)

      statusView

      Button(action: download) {
        HStack(spacing: 8) {
          Text("↓")
            .font(.system(size: 16, weight: .bold))
          Text("譜面を取得する")
        }
      }
      .buttonStyle(PrimaryButtonStyleWafuu(fontSize: 15))
      .disabled(!isValidID || phase == .downloading)
      .opacity(!isValidID || phase == .downloading ? 0.5 : 1)
      .padding(.top, 4)
    }
    .padding(20)
    .background(WafuuUI.cardBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 4)
  }

  private var borderColor: Color {
    switch phase {
    case .error: return .red.opacity(0.7)
    case .success, .alreadySaved: return WafuuUI.moss
    default: return WafuuUI.woodDark
    }
  }

  @ViewBuilder
  private var statusView: some View {
    switch phase {
    case .idle:
      Color.clear.frame(height: 0)
    case .downloading:
      HStack(spacing: 8) {
        ProgressView().tint(WafuuUI.gold)
        Text("ダウンロード中...")
          .font(WafuuUI.gothic(12))
          .foregroundStyle(WafuuUI.sumiSoft)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 4)
    case .success(let chart):
      statusBanner(
        text: "「\(chart.name)」をライブラリに追加しました",
        color: WafuuUI.moss
      )
    case .alreadySaved(let chart):
      statusBanner(
        text: "「\(chart.name)」は既に保存済みです",
        color: WafuuUI.gold
      )
    case .error(let message):
      statusBanner(
        text: message,
        color: .red
      )
    }
  }

  private func statusBanner(text: String, color: Color) -> some View {
    HStack(spacing: 8) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(text)
        .font(WafuuUI.gothic(12))
        .foregroundStyle(WafuuUI.sumi)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(color.opacity(0.12))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(0.5), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  // MARK: - Logic

  private var isValidID: Bool {
    let count = idInput.count
    return count >= 3 && count <= 64 && idInput.allSatisfy {
      $0.isLowercase || $0.isNumber || $0 == "-"
    }
  }

  private func download() {
    let id = idInput
    guard isValidID else { return }
    phase = .downloading
    Task {
      if await ChartStorage.shared.exists(id: id) {
        if let existing = try? await ChartStorage.shared.load(id: id) {
          await MainActor.run {
            phase = .alreadySaved(existing)
          }
          try? await Task.sleep(nanoseconds: 900_000_000)
          onDownloaded(existing)
          return
        }
      }

      do {
        let chart = try await APIClient.shared.fetchChart(id: id)
        try await ChartStorage.shared.save(chart)
        await MainActor.run {
          phase = .success(chart)
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        onDownloaded(chart)
      } catch let error as APIError {
        await MainActor.run {
          phase = .error(error.localizedDescription)
        }
      } catch {
        await MainActor.run {
          phase = .error("通信に失敗しました。時間をおいて再試行してください。")
        }
      }
    }
  }
}

#Preview {
  ChartDownloadView(
    onDownloaded: { _ in },
    onCancel: {}
  )
}
