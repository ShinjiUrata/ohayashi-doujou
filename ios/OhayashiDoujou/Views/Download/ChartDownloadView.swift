import SwiftUI

/// 譜面検索 / ダウンロード画面。
///
/// モック `screens/03_chart_download.md` に準拠。
/// - ID 入力(小英数ハイフン、3〜64 文字)
/// - 既に保存済みなら DL スキップ
/// - GCS から匿名 GET → ローカルに保存 → 一覧へ戻る
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

  private let gold = Color(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0)
  private let goldDim = Color(red: 0xb8 / 255.0, green: 0x93 / 255.0, blue: 0x5a / 255.0)
  private let cream = Color(red: 0xf5 / 255.0, green: 0xea / 255.0, blue: 0xd0 / 255.0)
  private let panel = Color(red: 0x1d / 255.0, green: 0x1a / 255.0, blue: 0x2a / 255.0)
  private let bg = Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x1d / 255.0)
  private let sub = Color(red: 0x4e / 255.0, green: 0xa7 / 255.0, blue: 0xd9 / 255.0)
  private let ok = Color(red: 0x6b / 255.0, green: 0xc9 / 255.0, blue: 0x8a / 255.0)

  var body: some View {
    ZStack {
      bg.ignoresSafeArea()

      VStack(spacing: 0) {
        header
        content
        Spacer()
      }
    }
    .foregroundStyle(cream)
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      Button(action: onCancel) {
        Text("◀ 戻る")
          .font(.system(size: 13))
          .foregroundStyle(gold.opacity(0.8))
      }
      Spacer()
      Text("譜面を入手")
        .font(.system(size: 15, weight: .bold))
        .tracking(2)
        .foregroundStyle(gold)
      Spacer()
      Color.clear.frame(width: 44)
    }
    .padding(.horizontal, 20)
    .padding(.top, 14)
    .padding(.bottom, 12)
    .background(
      LinearGradient(
        colors: [sub.opacity(0.15), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  // MARK: - Content

  private var content: some View {
    VStack(spacing: 16) {
      hero

      VStack(alignment: .leading, spacing: 6) {
        Text("譜面 ID")
          .font(.system(size: 10))
          .tracking(2)
          .foregroundStyle(gold)

        TextField("例: shimoda-2026-irihayashi", text: $idInput)
          .textFieldStyle(.plain)
          .font(.system(size: 15, design: .monospaced))
          .foregroundStyle(cream)
          .autocorrectionDisabled(true)
          .textInputAutocapitalization(.never)
          .padding(12)
          .background(panel)
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(borderColor, lineWidth: 2)
          )
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .onChange(of: idInput) { _, new in
            // 入力を安全な範囲にリアルタイム制限
            idInput = new.lowercased().filter {
              $0.isLetter || $0.isNumber || $0 == "-"
            }
            if case .error = phase { phase = .idle }
          }

        Text("小英字 / 数字 / ハイフンのみ、3〜64 文字")
          .font(.system(size: 10))
          .tracking(1)
          .foregroundStyle(cream.opacity(0.5))
      }

      statusView

      downloadButton

      infoBox

      Spacer()
    }
    .padding(.horizontal, 24)
    .padding(.top, 20)
  }

  private var hero: some View {
    VStack(spacing: 6) {
      Circle()
        .fill(
          RadialGradient(
            colors: [Color(red: 0x8f / 255.0, green: 0xd1 / 255.0, blue: 0xf4 / 255.0), sub, Color(red: 0x1b / 255.0, green: 0x4d / 255.0, blue: 0x70 / 255.0)],
            center: UnitPoint(x: 0.35, y: 0.30),
            startRadius: 0,
            endRadius: 40
          )
        )
        .frame(width: 56, height: 56)
        .overlay(Image(systemName: "magnifyingglass").foregroundStyle(.white).font(.system(size: 22, weight: .bold)))
        .shadow(color: sub.opacity(0.4), radius: 10)

      Text("譜面 ID を入力してください")
        .font(.system(size: 14))
        .foregroundStyle(cream.opacity(0.85))
      Text("制作者から教えてもらった ID を打ち込むだけ")
        .font(.system(size: 11))
        .foregroundStyle(cream.opacity(0.5))
    }
  }

  private var borderColor: Color {
    switch phase {
    case .error: return Color(red: 1, green: 0.42, blue: 0.42)
    case .success, .alreadySaved: return ok
    default: return isValidID ? gold.opacity(0.4) : gold.opacity(0.15)
    }
  }

  @ViewBuilder
  private var statusView: some View {
    switch phase {
    case .idle:
      Color.clear.frame(height: 0)
    case .downloading:
      HStack(spacing: 8) {
        ProgressView()
          .tint(gold)
        Text("ダウンロード中...")
          .font(.system(size: 12))
          .foregroundStyle(cream.opacity(0.7))
      }
      .padding(.vertical, 4)
    case .success(let chart):
      statusBanner(
        text: "「\(chart.name)」をライブラリに追加しました",
        color: ok
      )
    case .alreadySaved(let chart):
      statusBanner(
        text: "「\(chart.name)」は既に保存済みです",
        color: gold
      )
    case .error(let message):
      statusBanner(
        text: message,
        color: Color(red: 1, green: 0.42, blue: 0.42)
      )
    }
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

  private var downloadButton: some View {
    Button(action: download) {
      HStack(spacing: 6) {
        Image(systemName: "arrow.down.circle.fill")
        Text("ダウンロード")
      }
      .font(.system(size: 16, weight: .bold))
      .tracking(3)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 15)
      .background(
        LinearGradient(
          colors: [Color(red: 0x5f / 255.0, green: 0xb8 / 255.0, blue: 0xea / 255.0), sub],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .shadow(color: sub.opacity(0.4), radius: 10)
    }
    .disabled(!isValidID || phase == .downloading)
    .opacity(!isValidID || phase == .downloading ? 0.5 : 1.0)
  }

  private var infoBox: some View {
    Text("オフライン設計: 一度ダウンロードすればプレイ中はネット接続なしで動作します。祭り会場でも安心。")
      .font(.system(size: 10))
      .foregroundStyle(cream.opacity(0.7))
      .padding(12)
      .background(gold.opacity(0.06))
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(gold.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      )
      .clipShape(RoundedRectangle(cornerRadius: 10))
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
      // ローカル既存チェック
      if await ChartStorage.shared.exists(id: id) {
        if let existing = try? await ChartStorage.shared.load(id: id) {
          await MainActor.run {
            phase = .alreadySaved(existing)
          }
          // 少し待ってから遷移
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
  .preferredColorScheme(.dark)
}
