import SwiftUI

/// アプリのルート画面。タイトルとメインメニュー(2 種の入口)。
///
/// - プレイする → 譜面ライブラリ(選択して再生、DL 導線もここに集約)
/// - 譜面を作る → 録音モード
///
/// mockup: `mockups/01_title_menu_wafuu.html`
struct MainMenuView: View {
  var onSelectLibrary: () -> Void
  var onRecord: () -> Void

  @State private var legalURL: URL?

  private var appVersion: String {
    let bundle = Bundle.main
    let short = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    let build = (bundle.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    return "v\(short) (\(build))"
  }

  var body: some View {
    ZStack {
      WafuuBackground()

      VStack(spacing: 0) {
        Spacer(minLength: 32)
        titleBlock
        Spacer(minLength: 32)
        menuButtons
          .padding(.horizontal, 28)
        Spacer(minLength: 20)
        footer
      }
    }
    .legalLinkSheet(url: $legalURL)
  }

  // MARK: - Title

  private var titleBlock: some View {
    VStack(spacing: 12) {
      Text("祭りのリズムを、体で覚える")
        .font(WafuuUI.gothic(11))
        .tracking(4)
        .foregroundStyle(WafuuUI.sumiMist)

      // 提灯風の 3 点デコレーション
      HStack(spacing: 14) {
        ForEach(0..<3, id: \.self) { _ in
          Capsule()
            .fill(WafuuUI.don)
            .frame(width: 8, height: 12)
            .overlay(
              Rectangle()
                .fill(WafuuUI.sumi)
                .frame(width: 2, height: 3)
                .offset(y: -7)
            )
            .shadow(color: WafuuUI.don.opacity(0.35), radius: 2, x: 0, y: 2)
        }
      }

      Text("おはやし道場")
        .font(WafuuUI.serif(42, weight: .black))
        .tracking(12)
        .foregroundStyle(WafuuUI.sumi)
        .padding(.leading, 12) // トラッキングによる右寄せ補正

      Text("OHAYASHI DOUJOU")
        .font(WafuuUI.num(12, weight: .semibold))
        .tracking(6)
        .foregroundStyle(WafuuUI.gold)

      GoldHairline()
        .frame(maxWidth: 140)
        .padding(.top, 6)

      Text("道場で、太鼓を叩こう。")
        .font(WafuuUI.serif(13, weight: .regular))
        .tracking(3)
        .foregroundStyle(WafuuUI.sumiSoft)
        .padding(.top, 10)
    }
  }

  // MARK: - Menu

  private var menuButtons: some View {
    VStack(spacing: 14) {
      MenuButton(
        title: "プレイする",
        subtitle: "保存した譜面を選んでプレイ",
        icon: "▶",
        style: .primary,
        action: onSelectLibrary
      )
      MenuButton(
        title: "譜面を作る",
        subtitle: "太鼓を叩いてお手本を録音",
        icon: "●",
        style: .wood(iconColor: WafuuUI.donDim),
        action: onRecord
      )
    }
  }

  // MARK: - Footer

  private var footer: some View {
    VStack(spacing: 8) {
      HStack(spacing: 14) {
        legalLinkButton("利用規約", url: LegalURL.terms)
        legalDivider
        legalLinkButton("プライバシー", url: LegalURL.privacy)
        legalDivider
        legalLinkButton("特商法表記", url: LegalURL.tokushoho)
      }
      VStack(spacing: 3) {
        Text(appVersion)
          .font(WafuuUI.num(10, weight: .regular))
          .tracking(2)
          .foregroundStyle(WafuuUI.sumiMist)
        Text("© 2026 株式会社ZembREM")
          .font(WafuuUI.num(9, weight: .regular))
          .tracking(2)
          .foregroundStyle(WafuuUI.sumiMist.opacity(0.7))
      }
    }
    .padding(.bottom, 24)
  }

  private func legalLinkButton(_ label: String, url: URL) -> some View {
    Button {
      legalURL = url
    } label: {
      Text(label)
        .font(WafuuUI.gothic(10, weight: .medium))
        .tracking(1)
        .foregroundStyle(WafuuUI.gold)
        .underline()
    }
    .buttonStyle(.plain)
  }

  private var legalDivider: some View {
    Rectangle()
      .fill(WafuuUI.sumiMist.opacity(0.35))
      .frame(width: 1, height: 10)
  }
}

// MARK: - Menu button

private struct MenuButton: View {
  enum Style {
    case primary
    case wood(iconColor: Color)
  }

  let title: String
  let subtitle: String
  let icon: String
  let style: Style
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        iconCircle
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(WafuuUI.serif(16, weight: .bold))
            .tracking(3)
            .foregroundStyle(titleColor)
          Text(subtitle)
            .font(WafuuUI.gothic(11))
            .tracking(1.5)
            .foregroundStyle(subtitleColor)
        }
        Spacer()
        Text("›")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(chevColor)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(background)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(borderColor, lineWidth: 1.5)
      )
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 4)
    }
    .buttonStyle(.plain)
  }

  private var iconCircle: some View {
    Text(icon)
      .font(.system(size: 14, weight: .bold))
      .foregroundStyle(iconColor)
      .frame(width: 36, height: 36)
      .background(Circle().fill(iconBackground))
  }

  // MARK: - Style resolvers

  @ViewBuilder
  private var background: some View {
    switch style {
    case .primary:
      LinearGradient(
        colors: [WafuuUI.donHi, WafuuUI.don, WafuuUI.donDim],
        startPoint: .top,
        endPoint: .bottom
      )
    case .wood:
      LinearGradient(
        colors: [WafuuUI.cardBgTop, WafuuUI.cardBgBottom],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }

  private var titleColor: Color {
    switch style {
    case .primary: return .white
    case .wood: return WafuuUI.sumi
    }
  }
  private var subtitleColor: Color {
    switch style {
    case .primary: return .white.opacity(0.85)
    case .wood: return WafuuUI.sumiSoft
    }
  }
  private var iconColor: Color {
    switch style {
    case .primary: return .white
    case .wood(let c): return c
    }
  }
  private var iconBackground: Color {
    switch style {
    case .primary: return .white.opacity(0.2)
    case .wood(let c): return c.opacity(0.15)
    }
  }
  private var chevColor: Color {
    switch style {
    case .primary: return .white.opacity(0.85)
    case .wood: return WafuuUI.gold.opacity(0.6)
    }
  }
  private var borderColor: Color {
    switch style {
    case .primary: return WafuuUI.donDim
    case .wood: return WafuuUI.woodDeep
    }
  }
  private var shadowColor: Color {
    switch style {
    case .primary: return WafuuUI.don.opacity(0.35)
    case .wood: return .black.opacity(0.12)
    }
  }
  private var shadowRadius: CGFloat {
    switch style {
    case .primary: return 8
    case .wood: return 2
    }
  }
}

#Preview {
  MainMenuView(
    onSelectLibrary: {},
    onRecord: {}
  )
}
