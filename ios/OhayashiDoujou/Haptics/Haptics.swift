import UIKit

/// 打点時の触覚フィードバック。
///
/// 実装方針(`implementation_notes/ios_pitfalls.md` §5 参照):
/// - `UIImpactFeedbackGenerator` のインスタンスを保持し、即時発火に備える。
/// - ドン: `.medium`、カッ: `.light`、大ドン: `.heavy` にする(打感の階調)。
/// - 発火後は次回のための `prepare()` を呼び直す。
@MainActor
public final class Haptics {
  public static let shared = Haptics()

  private let don = UIImpactFeedbackGenerator(style: .medium)
  private let ka = UIImpactFeedbackGenerator(style: .light)
  private let donBoth = UIImpactFeedbackGenerator(style: .heavy)

  private init() {
    prepare()
  }

  /// 起動時 or 画面遷移時に呼び、即時発火に備える。
  public func prepare() {
    don.prepare()
    ka.prepare()
    donBoth.prepare()
  }

  /// NoteType に応じた触覚を発火する。
  public func fire(for noteType: NoteType) {
    switch noteType {
    case .don_l, .don_r:
      don.impactOccurred()
      don.prepare()
    case .ka_l, .ka_r:
      ka.impactOccurred()
      ka.prepare()
    case .don_both:
      donBoth.impactOccurred()
      donBoth.prepare()
    }
  }
}
