import SwiftUI
import SafariServices

/// SFSafariViewController を SwiftUI から使えるようにするラッパー。
/// 法務文書などを外部ブラウザではなくアプリ内 Safari で開くために使う。
struct SafariView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let controller = SFSafariViewController(url: url)
    controller.preferredControlTintColor = UIColor(WafuuUI.gold)
    controller.dismissButtonStyle = .close
    return controller
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// 法務文書 URL の集約(GitHub Pages 上)。
enum LegalURL {
  static let base = "https://shinjiurata.github.io/ohayashi-doujou/"

  static let terms      = URL(string: base + "terms.html")!
  static let privacy    = URL(string: base + "privacy.html")!
  static let tokushoho  = URL(string: base + "tokushoho.html")!
}

/// 法務リンクを SFSafariViewController で開くための ViewModifier。
/// タップ元の View に `.legalLinkSheet(url: $url)` を付けて使う。
struct LegalLinkSheet: ViewModifier {
  @Binding var url: URL?

  func body(content: Content) -> some View {
    content.sheet(item: Binding(
      get: { url.map { IdentifiableURL(url: $0) } },
      set: { url = $0?.url }
    )) { wrapper in
      SafariView(url: wrapper.url)
        .ignoresSafeArea()
    }
  }

  private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
  }
}

extension View {
  func legalLinkSheet(url: Binding<URL?>) -> some View {
    modifier(LegalLinkSheet(url: url))
  }
}
