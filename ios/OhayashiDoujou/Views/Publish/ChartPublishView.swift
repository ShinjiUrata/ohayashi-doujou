import SwiftUI

/// 譜面公開画面。
///
/// フロー(screens/08_publish.md 準拠):
/// 1. 譜面サマリを表示
/// 2. 公開 ID を入力
/// 3. 「IDを確認」→ `/check-id` で事前重複チェック
/// 4. 利用可能なら「公開する」ボタン → `/publish` に投げて確定 ID 受け取り
/// 5. 発行 ID を表示、コピー可、ライブラリへ復帰
///
/// Phase 4 では JWS スタブ、Phase 5 で StoreKit 2 の実 JWS に差し替え。
struct ChartPublishView: View {
  let chart: Chart
  var onDismiss: () -> Void
  var onPublished: (String) -> Void

  enum Phase: Equatable {
    case input
    case checking
    case available
    case conflict
    case checkError(String)
    case publishing
    case success(String)
    case publishError(String)
  }

  @State private var publishId: String = ""
  @State private var phase: Phase = .input

  private let gold = Color(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0)
  private let goldDim = Color(red: 0xb8 / 255.0, green: 0x93 / 255.0, blue: 0x5a / 255.0)
  private let cream = Color(red: 0xf5 / 255.0, green: 0xea / 255.0, blue: 0xd0 / 255.0)
  private let panel = Color(red: 0x1d / 255.0, green: 0x1a / 255.0, blue: 0x2a / 255.0)
  private let bg = Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x1d / 255.0)
  private let accent = Color(red: 0xc8 / 255.0, green: 0x21 / 255.0, blue: 0x1d / 255.0)
  private let ok = Color(red: 0x6b / 255.0, green: 0xc9 / 255.0, blue: 0x8a / 255.0)
  private let warn = Color(red: 1.0, green: 0.42, blue: 0.42)

  var body: some View {
    ZStack {
      bg.ignoresSafeArea()
      VStack(spacing: 0) {
        header
        content
      }
    }
    .foregroundStyle(cream)
  }

  private var header: some View {
    HStack {
      Button(action: onDismiss) {
        Image(systemName: "chevron.left")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(gold.opacity(0.7))
          .frame(width: 32, height: 32)
          .background(Color.black.opacity(0.3))
          .clipShape(Circle())
      }
      Spacer()
      Text("譜面を公開")
        .font(.system(size: 15, weight: .bold))
        .tracking(2)
        .foregroundStyle(gold)
      Spacer()
      Color.clear.frame(width: 32, height: 32)
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 10)
    .background(
      LinearGradient(
        colors: [accent.opacity(0.18), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
    )
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
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        chartSummary
        idInputBlock
        checkStatus
        publishSection
        Spacer(minLength: 40)
      }
      .padding(.horizontal, 20)
      .padding(.top, 14)
      .padding(.bottom, 20)
    }
  }

  private var chartSummary: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(chart.name.isEmpty ? "(名称未設定)" : chart.name)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(cream)
      HStack(spacing: 12) {
        summaryPill(k: "地域", v: chart.region.isEmpty ? "—" : chart.region)
        summaryPill(k: "時間", v: formatDuration(chart.durationMs))
        summaryPill(k: "ノーツ", v: "\(chart.notes.count)")
      }
    }
    .padding(12)
    .background(panel)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(gold.opacity(0.2), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func summaryPill(k: String, v: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(k)
        .font(.system(size: 10))
        .tracking(1)
        .foregroundStyle(goldDim)
      Text(v)
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(gold)
    }
  }

  private var idInputBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("公開 ID(自分で決められます)")
        .font(.system(size: 10))
        .tracking(2)
        .foregroundStyle(gold)
      TextField("例: shimoda-2026-irihayashi", text: $publishId)
        .textFieldStyle(.plain)
        .font(.system(size: 15, design: .monospaced))
        .foregroundStyle(cream)
        .autocorrectionDisabled(true)
        .textInputAutocapitalization(.never)
        .padding(12)
        .background(panel)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(idBorderColor, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: publishId) { _, new in
          publishId = new.lowercased().filter {
            $0.isLetter || $0.isNumber || $0 == "-"
          }
          // 入力が変わったら check 状態はリセット
          switch phase {
          case .available, .conflict, .checkError:
            phase = .input
          default:
            break
          }
        }
      Text("小英字 / 数字 / ハイフン、3〜64 文字。地域内で告知しやすい覚えやすい ID を推奨")
        .font(.system(size: 10))
        .tracking(1)
        .foregroundStyle(cream.opacity(0.5))
    }
  }

  private var idBorderColor: Color {
    switch phase {
    case .available: return ok
    case .conflict, .checkError: return warn
    default: return isValidId ? gold.opacity(0.4) : gold.opacity(0.15)
    }
  }

  @ViewBuilder
  private var checkStatus: some View {
    switch phase {
    case .checking:
      HStack(spacing: 8) {
        ProgressView().tint(gold)
        Text("ID を確認中…")
          .font(.system(size: 12))
          .foregroundStyle(cream.opacity(0.7))
      }
    case .available:
      statusBanner(text: "この ID は利用可能です", color: ok)
    case .conflict:
      statusBanner(text: "この ID は既に使われています。別の ID を試してください", color: warn)
    case .checkError(let msg):
      statusBanner(text: msg, color: warn)
    default:
      EmptyView()
    }

    Button(action: checkId) {
      Text("この ID が使えるか確認")
        .font(.system(size: 13, weight: .bold))
        .tracking(2)
        .foregroundStyle(gold)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(panel)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(gold.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .disabled(!canCheck)
    .opacity(canCheck ? 1.0 : 0.4)
  }

  private var publishSection: some View {
    VStack(spacing: 10) {
      priceCard
      publishButton
      caveat
    }
  }

  private var priceCard: some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: 10)
        .fill(accent.opacity(0.25))
        .frame(width: 40, height: 40)
        .overlay(
          Text("♪")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(gold)
        )
      VStack(alignment: .leading, spacing: 2) {
        Text("公開料金(1曲)")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(cream)
        Text("公開ボタンを押すと即時課金・即時公開")
          .font(.system(size: 10))
          .foregroundStyle(cream.opacity(0.7))
      }
      Spacer()
      Text("¥1,000")
        .font(.system(size: 20, weight: .bold, design: .monospaced))
        .foregroundStyle(gold)
        .shadow(color: gold.opacity(0.4), radius: 6)
    }
    .padding(14)
    .background(
      LinearGradient(
        colors: [accent.opacity(0.18), accent.opacity(0.05)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(accent.opacity(0.4), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  @ViewBuilder
  private var publishButton: some View {
    Button(action: publish) {
      HStack(spacing: 8) {
        if case .publishing = phase {
          ProgressView().tint(.white)
        }
        VStack(spacing: 3) {
          Text("この譜面を公開する")
            .font(.system(size: 16, weight: .bold))
            .tracking(2)
          Text("¥1,000 で即時アップロード")
            .font(.system(size: 10))
            .opacity(0.85)
        }
      }
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
    .disabled(!canPublish)
    .opacity(canPublish ? 1.0 : 0.4)

    if case .publishError(let msg) = phase {
      statusBanner(text: msg, color: warn)
    }
  }

  private var caveat: some View {
    VStack(spacing: 6) {
      Text("※ 購入は返金・キャンセル不可(即時消費)")
      Text("※ Phase 4 現在は課金スタブ、Phase 5 で StoreKit 2 決済を統合")
    }
    .font(.system(size: 9))
    .foregroundStyle(cream.opacity(0.5))
    .tracking(1)
    .multilineTextAlignment(.center)
    .padding(.top, 4)
  }

  // MARK: - Success body

  private func successBody(publishedId: String) -> some View {
    VStack(spacing: 22) {
      Spacer()
      Circle()
        .fill(ok.opacity(0.15))
        .frame(width: 100, height: 100)
        .overlay(
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 56))
            .foregroundStyle(ok)
        )
      VStack(spacing: 6) {
        Text("公開完了")
          .font(.system(size: 20, weight: .bold))
          .tracking(4)
          .foregroundStyle(gold)
        Text("この ID を地域内で告知してください")
          .font(.system(size: 12))
          .foregroundStyle(cream.opacity(0.75))
      }
      VStack(spacing: 8) {
        Text(publishedId)
          .font(.system(size: 18, weight: .semibold, design: .monospaced))
          .foregroundStyle(cream)
          .padding(14)
          .frame(maxWidth: .infinity)
          .background(panel)
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(gold.opacity(0.35), lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 12))
        Button {
          UIPasteboard.general.string = publishedId
        } label: {
          Label("ID をコピー", systemImage: "doc.on.doc")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(gold)
        }
      }
      .padding(.horizontal, 20)
      Spacer()
      Button {
        onPublished(publishedId)
      } label: {
        Text("ライブラリへ戻る")
          .font(.system(size: 15, weight: .bold))
          .tracking(3)
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
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 24)
    }
  }

  // MARK: - Helpers

  private var isValidId: Bool {
    let n = publishId.count
    return n >= 3 && n <= 64 && publishId.allSatisfy {
      $0.isLowercase || $0.isNumber || $0 == "-"
    }
  }

  private var canCheck: Bool {
    if case .checking = phase { return false }
    return isValidId
  }

  private var canPublish: Bool {
    if case .publishing = phase { return false }
    if case .available = phase { return true }
    return false
  }

  private func statusBanner(text: String, color: Color) -> some View {
    HStack(spacing: 8) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(text)
        .font(.system(size: 12))
        .foregroundStyle(cream)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(color.opacity(0.1))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(color.opacity(0.35), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private func formatDuration(_ ms: Int) -> String {
    let seconds = ms / 1000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  // MARK: - Actions

  private func checkId() {
    let id = publishId
    guard isValidId else { return }
    phase = .checking
    Task {
      do {
        let available = try await APIClient.shared.checkID(id)
        await MainActor.run {
          phase = available ? .available : .conflict
        }
      } catch let error as APIError {
        await MainActor.run {
          phase = .checkError(error.localizedDescription)
        }
      } catch {
        await MainActor.run {
          phase = .checkError("通信に失敗しました。時間をおいて再試行してください。")
        }
      }
    }
  }

  private func publish() {
    let id = publishId
    guard case .available = phase, isValidId else { return }
    phase = .publishing

    // Chart の id を公開 ID に差し替えて送る(元の chart は draft ID の可能性がある)
    var toPublish = chart
    toPublish.id = id

    Task {
      do {
        // Phase 4 現在: JWS は backend スタブが常に成功で返すダミー文字列。
        // Phase 5 で StoreKit 2 の実 JWS(product.purchase → verification.jwsRepresentation)に差し替える。
        let confirmedId = try await APIClient.shared.publish(
          signedTransaction: "phase4-stub-jws",
          chart: toPublish
        )
        // 公開成功した譜面をローカルにも保存(id を確定版に差し替えた形で)
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
  .preferredColorScheme(.dark)
}
