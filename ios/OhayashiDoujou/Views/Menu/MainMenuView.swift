import SwiftUI

/// アプリのルート画面。タイトルとメインメニュー(3 種の入口)。
///
/// - 譜面で遊ぶ → 譜面ライブラリ(選択して再生)
/// - 譜面を作る → 録音モード
/// - IDで譜面を入手 → 譜面検索 / ダウンロード
struct MainMenuView: View {
  var onSelectLibrary: () -> Void
  var onRecord: () -> Void
  var onDownload: () -> Void

  private let bg = Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x1d / 255.0)
  private let panel = Color(red: 0x1d / 255.0, green: 0x1a / 255.0, blue: 0x2a / 255.0)
  private let gold = Color(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0)
  private let goldDim = Color(red: 0xb8 / 255.0, green: 0x93 / 255.0, blue: 0x5a / 255.0)
  private let cream = Color(red: 0xf5 / 255.0, green: 0xea / 255.0, blue: 0xd0 / 255.0)
  private let accent = Color(red: 0xc8 / 255.0, green: 0x21 / 255.0, blue: 0x1d / 255.0)

  private var appVersion: String {
    let bundle = Bundle.main
    let short = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    let build = (bundle.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    return "v\(short) (\(build))"
  }

  var body: some View {
    ZStack {
      background
      VStack(spacing: 0) {
        Spacer(minLength: 24)
        titleBlock
        Spacer(minLength: 32)
        menuButtons
          .padding(.horizontal, 28)
        Spacer(minLength: 20)
        footer
      }
    }
    .foregroundStyle(cream)
  }

  // MARK: - Background

  private var background: some View {
    ZStack {
      bg.ignoresSafeArea()

      // 上部の赤いグラデーション(祭りの提灯風の残光)
      LinearGradient(
        colors: [accent.opacity(0.28), .clear],
        startPoint: .top,
        endPoint: .center
      )
      .ignoresSafeArea()

      // 下部の金色のうっすらとした光
      LinearGradient(
        colors: [.clear, gold.opacity(0.06)],
        startPoint: .center,
        endPoint: .bottom
      )
      .ignoresSafeArea()
    }
  }

  // MARK: - Title

  private var titleBlock: some View {
    VStack(spacing: 12) {
      HStack(spacing: 20) {
        noteMark
        noteMark
        noteMark
      }
      .foregroundStyle(gold.opacity(0.6))

      Text("お囃子道場")
        .font(.system(size: 44, weight: .black))
        .tracking(8)
        .foregroundStyle(
          LinearGradient(
            colors: [cream, gold],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .shadow(color: accent.opacity(0.5), radius: 12, x: 0, y: 4)
        .padding(.leading, 8) // トラッキングによる右寄りを補正

      Text("OHAYASHI DOUJOU")
        .font(.system(size: 11, weight: .semibold))
        .tracking(6)
        .foregroundStyle(goldDim)

      Rectangle()
        .fill(goldDim.opacity(0.35))
        .frame(width: 96, height: 1)
        .padding(.top, 4)

      Text("祭りのリズムを、体で覚える")
        .font(.system(size: 13, weight: .medium))
        .tracking(2)
        .foregroundStyle(cream.opacity(0.75))
        .padding(.top, 6)
    }
  }

  private var noteMark: some View {
    Image(systemName: "music.note")
      .font(.system(size: 14, weight: .semibold))
  }

  // MARK: - Menu buttons

  private var menuButtons: some View {
    VStack(spacing: 14) {
      primaryButton(
        title: "譜面で遊ぶ",
        subtitle: "保存した譜面を選んでプレイ",
        icon: "play.fill",
        action: onSelectLibrary
      )

      secondaryButton(
        title: "譜面を作る",
        subtitle: "太鼓を叩いてお手本を録音",
        icon: "circle.fill",
        iconColor: accent,
        action: onRecord
      )

      secondaryButton(
        title: "IDで譜面を入手",
        subtitle: "配布された譜面IDでダウンロード",
        icon: "arrow.down.circle.fill",
        iconColor: gold,
        action: onDownload
      )
    }
  }

  private func primaryButton(
    title: String,
    subtitle: String,
    icon: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: icon)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(Circle().fill(.white.opacity(0.18)))

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 17, weight: .bold))
            .tracking(2)
            .foregroundStyle(.white)
          Text(subtitle)
            .font(.system(size: 11))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.8))
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white.opacity(0.7))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .background(
        LinearGradient(
          colors: [
            Color(red: 0xdd / 255.0, green: 0x42 / 255.0, blue: 0x38 / 255.0),
            accent,
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .shadow(color: accent.opacity(0.45), radius: 10, y: 4)
    }
    .buttonStyle(.plain)
  }

  private func secondaryButton(
    title: String,
    subtitle: String,
    icon: String,
    iconColor: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: icon)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(iconColor)
          .frame(width: 40, height: 40)
          .background(Circle().fill(iconColor.opacity(0.14)))

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 15, weight: .semibold))
            .tracking(2)
            .foregroundStyle(cream)
          Text(subtitle)
            .font(.system(size: 11))
            .tracking(1)
            .foregroundStyle(cream.opacity(0.55))
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(gold.opacity(0.5))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(panel)
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(gold.opacity(0.18), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Footer

  private var footer: some View {
    VStack(spacing: 4) {
      Text(appVersion)
        .font(.system(size: 10))
        .tracking(1)
        .foregroundStyle(cream.opacity(0.35))
      Text("© 2026 ZembREM")
        .font(.system(size: 9))
        .tracking(1)
        .foregroundStyle(cream.opacity(0.25))
    }
    .padding(.bottom, 20)
  }
}

#Preview {
  MainMenuView(
    onSelectLibrary: {},
    onRecord: {},
    onDownload: {}
  )
  .preferredColorScheme(.dark)
}
