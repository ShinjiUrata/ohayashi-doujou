import Foundation

/// お囃子のノーツ種別。
///
/// - `don_l` / `don_r`: 中央ゾーンに落下、判定は共通(左右は叩く手のガイド)。
/// - `ka_l` / `ka_r`: 太鼓の左外側 / 右外側、判定ゾーンが物理的に異なる。
/// - `don_both`: 大ドン。中央ゾーンの左半分 + 右半分に 50ms 以内の 2 タッチで成立。
///
/// 詳細は CLAUDE.md §3.4 を参照。
public enum NoteType: String, Codable, Sendable, CaseIterable {
  case don_l
  case don_r
  case ka_l
  case ka_r
  case don_both

  /// タップ判定に使う 3 ゾーン + 両手同時打の分類。
  public enum Zone: Sendable {
    case leftKa       // ka_l
    case center       // don_l / don_r
    case rightKa      // ka_r
    case centerBoth   // don_both
  }

  public var zone: Zone {
    switch self {
    case .ka_l: return .leftKa
    case .don_l, .don_r: return .center
    case .ka_r: return .rightKa
    case .don_both: return .centerBoth
    }
  }
}

/// 単一の打点。
///
/// - `t`: 譜面開始からの経過ミリ秒。
/// - `type`: ノーツ種別。
/// - `duration`: ホールドノートの継続時間 (ms)。省略 or 0 は単発タップ。
///   500ms 以上を録音時にホールドとして自動判別する(録音側の閾値、モデルは値をそのまま保持)。
/// - `strong`: 太鼓の達人風の「強打」表現。true でノーツを一回り大きく描画する。
///   **視覚のみ**で判定ロジックには一切影響しない。省略 or false は通常(弱)。
///   譜面調整画面で任意に切替可能。既存譜面(フィールドなし)は「弱」扱い。
public struct Note: Codable, Sendable, Equatable {
  public var t: Int
  public var type: NoteType
  public var duration: Int?
  public var strong: Bool?

  public init(t: Int, type: NoteType, duration: Int? = nil, strong: Bool? = nil) {
    self.t = t
    self.type = type
    self.duration = duration
    self.strong = strong
  }

  public var isHold: Bool {
    (duration ?? 0) > 0
  }

  public var isStrong: Bool {
    strong ?? false
  }
}
