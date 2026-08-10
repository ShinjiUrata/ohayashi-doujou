import SwiftUI

/// 譜面公開画面。
///
/// フロー:
/// 1. 譜面サマリを表示
/// 2. 公開 ID を入力
/// 3. 「公開する」ボタン → 内部で `/check-id` → 利用可能なら StoreKit 2
///    → `/publish` → 確定 ID 受け取り(重複時は課金前に停止)
/// 4. 発行 ID を表示、コピー可、ライブラリへ復帰
///
/// mockup: `mockups/08_publish_wafuu.html`
struct ChartPublishView: View {
  let chart: Chart
  var onDismiss: () -> Void
  var onPublished: (String) -> Void

  enum Phase: Equatable {
    case input
    case checking
    case conflict
    case checkError(String)
    case publishing
    case success(String)
    case publishError(String)
  }

  @State private var publishId: String = ""
  @State private var phase: Phase = .input
  @State private var displayPrice: String = "¥1,200"

  var body: some View {
    ZStack {
      WafuuBackground()
      VStack(spacing: 0) {
        AppHeader(title: "譜面を公開", onBack: onDismiss)
        content
      }
    }
    .task {
      if let price = await StoreKitManager.shared.displayPrice() {
        displayPrice = price
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if case .success(let id) = phase {
      successBody(publishedId: id)
    } else {
      inputBody
    }
  }

  // MARK: - Input body

  private var inputBody: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 16) {
          hero
          chartSummaryCard
          idInputCard
          priceCard
          noticeBox
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 20)
      }
      footerActions
    }
  }

  private var hero: some View {
    VStack(spacing: 6) {
      Text("この譜面を配布する")
        .font(WafuuUI.serif(22, weight: .bold))
        .tracking(6)
        .foregroundStyle(WafuuUI.sumi)
      Text("公開すると、譜面 ID を知る人が\nダウンロードして遊べるようになります。")
        .font(WafuuUI.gothic(12))
        .tracking(2)
        .foregroundStyle(WafuuUI.sumiSoft)
        .multilineTextAlignment(.center)
    }
    .padding(.bottom, 4)
  }

  private var chartSummaryCard: some View {
    HStack(spacing: 12) {
      chartIcon(for: chart.name)
      VStack(alignment: .leading, spacing: 3) {
        Text(chart.name.isEmpty ? "(名称未設定)" : chart.name)
          .font(WafuuUI.serif(15, weight: .bold))
          .tracking(1)
          .foregroundStyle(WafuuUI.sumi)
          .lineLimit(1)
        Text("\(chart.region.isEmpty ? "—" : chart.region) · 演奏 \(formatDuration(chart.durationMs)) · \(chart.notes.count) 音")
          .font(WafuuUI.gothic(11))
          .tracking(1)
          .foregroundStyle(WafuuUI.gold)
      }
      Spacer()
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

  private func chartIcon(for name: String) -> some View {
    Text(String(name.prefix(1)))
      .font(WafuuUI.serif(17, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: 46, height: 46)
      .background(
        RadialGradient(
          colors: [WafuuUI.donHi, WafuuUI.don, WafuuUI.donDim],
          center: UnitPoint(x: 0.35, y: 0.30),
          startRadius: 0, endRadius: 42
        )
      )
      .clipShape(Circle())
  }

  private var idInputCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("CHART ID(公開後は変更不可)")
        .font(WafuuUI.num(10, weight: .semibold))
        .tracking(3)
        .foregroundStyle(WafuuUI.sumiMist)

      TextField("shimoda-2026-irihayashi", text: $publishId)
        .textFieldStyle(.plain)
        .font(WafuuUI.num(18, weight: .medium))
        .tracking(3)
        .foregroundStyle(WafuuUI.sumi)
        .multilineTextAlignment(.center)
        .autocorrectionDisabled(true)
        .textInputAutocapitalization(.never)
        .padding(12)
        .background(WafuuUI.paper.opacity(0.85))
        .overlay(
          RoundedRectangle(cornerRadius: 4)
            .stroke(idBorderColor, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onChange(of: publishId) { _, new in
          publishId = new.lowercased().filter {
            $0.isLetter || $0.isNumber || $0 == "-"
          }
          switch phase {
          case .conflict, .checkError:
            phase = .input
          default:
            break
          }
        }

      Text("小英字・数字・ハイフン、3〜64 文字")
        .font(WafuuUI.num(10, weight: .regular))
        .tracking(1)
        .foregroundStyle(WafuuUI.sumiMist)

      checkStatusView
    }
    .padding(16)
    .background(WafuuUI.paper.opacity(0.55))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(WafuuUI.woodDark, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private var idBorderColor: Color {
    switch phase {
    case .conflict, .checkError: return .red.opacity(0.7)
    default: return WafuuUI.woodDark
    }
  }

  @ViewBuilder
  private var checkStatusView: some View {
    switch phase {
    case .checking:
      HStack(spacing: 8) {
        ProgressView().tint(WafuuUI.gold)
        Text("ID を確認中…")
          .font(WafuuUI.gothic(12))
          .foregroundStyle(WafuuUI.sumiSoft)
      }
      .frame(maxWidth: .infinity)
    case .conflict:
      statusBanner(text: "この ID は既に使われています。別の ID にしてください。", color: .red)
    case .checkError(let msg):
      statusBanner(text: msg, color: .red)
    default:
      Color.clear.frame(height: 0)
    }
  }

  private var priceCard: some View {
    HStack {
      Text("公開料金")
        .font(WafuuUI.serif(14, weight: .bold))
        .tracking(3)
        .foregroundStyle(WafuuUI.sumi)
      Spacer()
      HStack(alignment: .bottom, spacing: 2) {
        Text(displayPrice)
          .font(WafuuUI.num(28, weight: .medium))
          .tracking(1)
          .foregroundStyle(WafuuUI.donDim)
        Text("(税込)")
          .font(WafuuUI.gothic(12))
          .foregroundStyle(WafuuUI.sumiSoft)
          .padding(.bottom, 2)
      }
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 18)
    .background(
      LinearGradient(
        colors: [WafuuUI.woodLight, WafuuUI.woodMid],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 2)
  }

  private var noticeBox: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("ご注意")
        .font(WafuuUI.serif(11, weight: .bold))
        .foregroundStyle(WafuuUI.sumi)
      Text("· 公開ボタン押下と同時に決済 → 譜面がアップロードされます\n· 消費型(Consumable)IAP、返金不可\n· 更新公開はできません(修正時は別 ID で新規公開)")
        .font(WafuuUI.gothic(11))
        .tracking(1)
        .foregroundStyle(WafuuUI.sumiSoft)
        .lineSpacing(2)
    }
    .padding(12)
    .background(WafuuUI.sumi.opacity(0.05))
    .overlay(
      Rectangle().fill(WafuuUI.gold).frame(width: 3),
      alignment: .leading
    )
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private var footerActions: some View {
    VStack(spacing: 8) {
      if case .publishError(let msg) = phase {
        statusBanner(text: msg, color: .red)
          .padding(.horizontal, 20)
          .padding(.top, 6)
      }
      Button(action: publish) {
        HStack(spacing: 10) {
          if case .checking = phase {
            ProgressView().tint(.white)
          } else if case .publishing = phase {
            ProgressView().tint(.white)
          }
          Text("公開する")
          Text(displayPrice)
            .font(WafuuUI.num(20, weight: .medium))
            .tracking(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
      }
      .buttonStyle(PrimaryButtonStyleWafuu(fontSize: 16))
      .disabled(!canPublish)
      .opacity(canPublish ? 1 : 0.4)
      .padding(.horizontal, 20)

      Button(action: onDismiss) {
        Text("後にする")
          .font(WafuuUI.gothic(12))
          .tracking(2)
          .foregroundStyle(WafuuUI.sumiSoft)
      }
      .padding(.bottom, 24)
    }
    .padding(.top, 12)
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

  // MARK: - Success body

  private func successBody(publishedId: String) -> some View {
    VStack(spacing: 22) {
      Spacer()
      Circle()
        .fill(WafuuUI.moss.opacity(0.15))
        .frame(width: 100, height: 100)
        .overlay(
          Text("✓")
            .font(.system(size: 60, weight: .bold))
            .foregroundStyle(WafuuUI.moss)
        )
      VStack(spacing: 6) {
        Text("公開完了")
          .font(WafuuUI.serif(24, weight: .bold))
          .tracking(6)
          .foregroundStyle(WafuuUI.sumi)
        Text("この ID を地域内で告知してください")
          .font(WafuuUI.gothic(12))
          .tracking(2)
          .foregroundStyle(WafuuUI.sumiSoft)
      }
      VStack(spacing: 8) {
        Text(publishedId)
          .font(WafuuUI.num(18, weight: .semibold))
          .tracking(2)
          .foregroundStyle(WafuuUI.sumi)
          .padding(14)
          .frame(maxWidth: .infinity)
          .background(WafuuUI.paper.opacity(0.85))
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(WafuuUI.woodDark, lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 8))
        Button {
          UIPasteboard.general.string = publishedId
        } label: {
          HStack(spacing: 4) {
            Text("⎘")
            Text("ID をコピー")
          }
          .font(WafuuUI.gothic(12, weight: .semibold))
          .tracking(1)
          .foregroundStyle(WafuuUI.gold)
        }
      }
      .padding(.horizontal, 20)
      Spacer()
      Button {
        onPublished(publishedId)
      } label: {
        Text("ライブラリへ戻る")
      }
      .buttonStyle(PrimaryButtonStyleWafuu(fontSize: 15))
      .padding(.horizontal, 20)
      .padding(.bottom, 28)
    }
  }

  // MARK: - Helpers

  private var isValidId: Bool {
    let n = publishId.count
    return n >= 3 && n <= 64 && publishId.allSatisfy {
      $0.isLowercase || $0.isNumber || $0 == "-"
    }
  }

  private var canPublish: Bool {
    guard isValidId else { return false }
    switch phase {
    case .checking, .conflict, .publishing:
      return false
    default:
      return true
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

  private func formatDuration(_ ms: Int) -> String {
    let seconds = ms / 1000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  // MARK: - Actions

  /// 「公開する」ボタンから呼ばれる。
  /// 課金前に `/check-id` で ID の空き確認 → 空きがあれば StoreKit 課金 → `/publish` に進む。
  /// 事前チェックで衝突していれば課金ダイアログを出さずに停止する
  /// (=課金だけ完了して公開失敗する事故を防ぐ)。
  private func publish() {
    let id = publishId
    guard isValidId else { return }
    phase = .checking

    var toPublish = chart
    toPublish.id = id

    Task {
      // 1) ID の空き確認
      let available: Bool
      do {
        available = try await APIClient.shared.checkID(id)
      } catch let error as APIError {
        await MainActor.run { phase = .checkError(error.localizedDescription) }
        return
      } catch {
        await MainActor.run {
          phase = .checkError("通信に失敗しました。時間をおいて再試行してください。")
        }
        return
      }

      guard available else {
        await MainActor.run { phase = .conflict }
        return
      }

      // 2) StoreKit 課金
      await MainActor.run { phase = .publishing }

      let pending: StoreKitManager.PendingPurchase
      do {
        pending = try await StoreKitManager.shared.purchase()
      } catch StoreKitManager.PurchaseError.userCancelled {
        await MainActor.run { phase = .input }
        return
      } catch let purchaseError as StoreKitManager.PurchaseError {
        await MainActor.run {
          phase = .publishError(
            purchaseError.errorDescription ?? "購入に失敗しました。"
          )
        }
        return
      } catch {
        await MainActor.run {
          phase = .publishError("購入に失敗しました。時間をおいて再試行してください。")
        }
        return
      }

      // 3) /publish 実行 + ローカル保存
      do {
        let confirmedId = try await APIClient.shared.publish(
          signedTransaction: pending.jws,
          chart: toPublish
        )

        await StoreKitManager.shared.finish(pending)

        toPublish.id = confirmedId
        try? await ChartStorage.shared.save(toPublish)

        await MainActor.run {
          phase = .success(confirmedId)
        }
      } catch let error as APIError {
        await MainActor.run {
          phase = .publishError(error.localizedDescription)
        }
      } catch {
        await MainActor.run {
          phase = .publishError("公開に失敗しました。時間をおいて再試行してください。")
        }
      }
    }
  }
}

#Preview {
  ChartPublishView(
    chart: DemoChart.phase2Demo,
    onDismiss: {},
    onPublished: { _ in }
  )
}
