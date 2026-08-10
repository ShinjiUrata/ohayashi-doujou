import SwiftUI

/// お囃子道場 和風モダン UI の共通トークン。
///
/// `mockups/play_wafuu_modern.html`(確定版)と
/// `dev_documents/implementation_plan/wafuu_ui_spec.md` に準拠。
///
/// - 色は 16 進で直接指定
/// - フォントは SwiftUI システムフォント(design: .serif で Hiragino Mincho 相当、
///   design: .default で Hiragino Sans 相当)。カスタムフォントの bundle は将来余地。
enum WafuuUI {

  // MARK: - Colors

  // 木・和紙
  static let woodLight  = Color(hex: 0xF2E5C5)
  static let woodCream  = Color(hex: 0xE9D6AC)
  static let woodMid    = Color(hex: 0xC8A976)
  static let woodDark   = Color(hex: 0x8B6A3C)
  static let woodDeep   = Color(hex: 0x5C4225)
  static let woodSumi   = Color(hex: 0x2B1A0E)
  static let paper      = Color(hex: 0xFDF6E3)
  static let cardBgTop    = Color(hex: 0xFBF3DC)
  static let cardBgBottom = Color(hex: 0xF0E0B0)

  // 墨(文字)
  static let sumi       = Color(hex: 0x2A2620)
  static let sumiSoft   = Color(hex: 0x5C5248)
  static let sumiMist   = Color(hex: 0x8A7F70)

  // 金アクセント
  static let gold       = Color(hex: 0xB8935A)
  static let goldSoft   = Color(hex: 0xD8BD85)
  static let goldHi     = Color(hex: 0xF0D896)

  // 深緑(畳の縁)
  static let moss       = Color(hex: 0x4D6C3E)
  static let mossMid    = Color(hex: 0x6B8556)
  static let mossSoft   = Color(hex: 0x9AB08B)

  // ドン
  static let don        = Color(hex: 0xFD4720)
  static let donDim     = Color(hex: 0xB0300F)
  static let donHi      = Color(hex: 0xFF7051)

  // カッ
  static let ka         = Color(hex: 0x44C2C1)
  static let kaDim      = Color(hex: 0x268786)
  static let kaHi       = Color(hex: 0x78D6D5)

  // MARK: - Fonts (helpers)

  /// 明朝寄り(Noto Serif JP 相当)。タイトル・見出し用。
  static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight, design: .serif)
  }

  /// ゴシック(Zen Kaku Gothic New 相当)。本文用。
  static func gothic(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .default)
  }

  /// 数字用(Bebas Neue 相当)。condensed で近い雰囲気に。
  static func num(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
    .system(size: size, weight: weight, design: .default).width(.condensed)
  }

  // MARK: - Gradients

  static var screenBackground: LinearGradient {
    LinearGradient(
      colors: [woodLight, woodCream],
      startPoint: .top,
      endPoint: .bottom
    )
  }
  static var cardBackground: LinearGradient {
    LinearGradient(
      colors: [cardBgTop, cardBgBottom],
      startPoint: .top,
      endPoint: .bottom
    )
  }
  static var primaryButtonBackground: LinearGradient {
    LinearGradient(
      colors: [donHi, don, donDim],
      startPoint: .top,
      endPoint: .bottom
    )
  }
  static var secondaryButtonBackground: LinearGradient {
    LinearGradient(
      colors: [woodLight, woodCream],
      startPoint: .top,
      endPoint: .bottom
    )
  }
}

// MARK: - Color hex init

extension Color {
  init(hex: UInt32, alpha: Double = 1.0) {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >>  8) & 0xFF) / 255.0
    let b = Double( hex        & 0xFF) / 255.0
    self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
  }
}

// MARK: - Reusable views

/// 和風背景(檜クリーム + 薄い節目 + 縦木目)。
struct WafuuBackground: View {
  var body: some View {
    ZStack {
      WafuuUI.screenBackground
        .ignoresSafeArea()

      // 節目(薄いシミ 2 個)
      GeometryReader { g in
        Canvas { ctx, size in
          let knots: [(x: CGFloat, y: CGFloat, opacity: Double)] = [
            (size.width * 0.26, size.height * 0.22, 0.14),
            (size.width * 0.72, size.height * 0.68, 0.11),
          ]
          for k in knots {
            let rect = CGRect(x: k.x - 20, y: k.y - 3, width: 40, height: 6)
            let gradient = Gradient(colors: [
              Color(hex: 0x5A3C1E, alpha: k.opacity),
              Color(hex: 0x5A3C1E, alpha: 0),
            ])
            ctx.fill(
              Path(ellipseIn: rect),
              with: .radialGradient(gradient, center: CGPoint(x: k.x, y: k.y),
                                    startRadius: 0, endRadius: 22)
            )
          }
        }
        // 縦の木目(疎)
        Canvas { ctx, size in
          for x in stride(from: 0, through: size.width, by: 22) {
            var p = Path()
            p.move(to: CGPoint(x: x + 6, y: 0))
            p.addLine(to: CGPoint(x: x + 6, y: size.height))
            ctx.stroke(p, with: .color(Color(hex: 0x8B6A3C, alpha: 0.04)), lineWidth: 1)

            var q = Path()
            q.move(to: CGPoint(x: x + 14, y: 0))
            q.addLine(to: CGPoint(x: x + 14, y: size.height))
            ctx.stroke(q, with: .color(Color(hex: 0x5C4225, alpha: 0.05)), lineWidth: 1)
          }
        }
      }
      .allowsHitTesting(false)
      .ignoresSafeArea()
    }
  }
}

/// 木札風カード(2 層グラデ + wood-deep 縁 + drop shadow)。
struct WoodCard<Content: View>: View {
  var cornerRadius: CGFloat = 10
  var padding: CGFloat = 14
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(padding)
      .background(WafuuUI.cardBackground)
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 2)
  }
}

/// 木の縦掛け札(スコア・数値表示)。
struct WoodPlate<Content: View>: View {
  var width: CGFloat? = nil
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 2) {
      content
    }
    .padding(.horizontal, 8)
    .padding(.top, 6)
    .padding(.bottom, 8)
    .frame(width: width)
    .background(
      LinearGradient(
        colors: [WafuuUI.woodLight, WafuuUI.woodMid],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .overlay(
      UnevenRoundedRectangle(cornerRadii: .init(
        topLeading: 4, bottomLeading: 8, bottomTrailing: 8, topTrailing: 4))
        .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
    )
    .clipShape(
      UnevenRoundedRectangle(cornerRadii: .init(
        topLeading: 4, bottomLeading: 8, bottomTrailing: 8, topTrailing: 4))
    )
    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 2)
    .overlay(alignment: .top) {
      // 縄穴(中央上部)
      Circle()
        .fill(Color(hex: 0x0A0805))
        .frame(width: 4, height: 4)
        .overlay(Circle().stroke(WafuuUI.woodDeep, lineWidth: 1.5))
        .offset(y: -3)
    }
  }
}

/// 主 CTA(朱グラデ + 赤縁)。
struct PrimaryButtonStyleWafuu: ButtonStyle {
  var fontSize: CGFloat = 15
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(WafuuUI.serif(fontSize, weight: .bold))
      .tracking(4)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .background(WafuuUI.primaryButtonBackground)
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(WafuuUI.donDim, lineWidth: 1.5)
      )
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .shadow(color: WafuuUI.don.opacity(0.35), radius: 5, x: 0, y: 4)
      .opacity(configuration.isPressed ? 0.85 : 1)
  }
}

/// 副 CTA(木札グラデ)。
struct SecondaryButtonStyleWafuu: ButtonStyle {
  var fontSize: CGFloat = 14
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(WafuuUI.serif(fontSize, weight: .medium))
      .tracking(3)
      .foregroundStyle(WafuuUI.sumi)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(WafuuUI.secondaryButtonBackground)
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(WafuuUI.woodDeep, lineWidth: 1.5)
      )
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 2)
      .opacity(configuration.isPressed ? 0.85 : 1)
  }
}

/// ゴースト(枠だけ)。
struct GhostButtonStyleWafuu: ButtonStyle {
  var fontSize: CGFloat = 13
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(WafuuUI.serif(fontSize, weight: .regular))
      .tracking(2)
      .foregroundStyle(WafuuUI.sumiSoft)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(Color.clear)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(WafuuUI.sumi.opacity(0.28), lineWidth: 1)
      )
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

/// 金の hairline セパレータ。
struct GoldHairline: View {
  var body: some View {
    LinearGradient(
      colors: [
        .clear,
        WafuuUI.goldSoft,
        WafuuUI.gold,
        WafuuUI.goldSoft,
        .clear,
      ],
      startPoint: .leading,
      endPoint: .trailing
    )
    .frame(height: 1)
  }
}

/// 共通アプリヘッダ(戻る + タイトル + 右ボタン)。
struct AppHeader<TrailingContent: View>: View {
  let title: String
  let onBack: (() -> Void)?
  @ViewBuilder var trailing: TrailingContent

  init(title: String,
       onBack: (() -> Void)? = nil,
       @ViewBuilder trailing: () -> TrailingContent = { EmptyView() }) {
    self.title = title
    self.onBack = onBack
    self.trailing = trailing()
  }

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [WafuuUI.moss.opacity(0.08), .clear],
        startPoint: .top,
        endPoint: .bottom
      )

      // タイトルは画面全体の中央に配置する(戻る / trailing の幅に依存しない)
      Text(title)
        .font(WafuuUI.serif(15, weight: .bold))
        .tracking(4)
        .foregroundStyle(WafuuUI.sumi)
        .lineLimit(1)

      HStack(spacing: 8) {
        if let onBack {
          Button(action: onBack) {
            HStack(spacing: 2) {
              Text("‹")
                .font(.system(size: 20, weight: .bold))
              Text("戻る")
                .font(WafuuUI.gothic(11))
                .tracking(2)
            }
            .foregroundStyle(WafuuUI.sumiSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
          }
        }

        Spacer()

        trailing
      }
      .padding(.horizontal, 16)
    }
    .frame(height: 44)
    .padding(.top, 14) // safe area 下ではさらに調整
    .background(
      Rectangle()
        .fill(Color.clear)
        .overlay(
          Rectangle()
            .fill(WafuuUI.sumi.opacity(0.12))
            .frame(height: 1),
          alignment: .bottom
        )
    )
  }
}
