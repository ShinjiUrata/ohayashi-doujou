import Foundation

/// 単発判定の結果。
public enum JudgeResult: Sendable, Equatable {
  case good
  case ok
  case miss
}

/// プレイ中のスコア・コンボ状態。
///
/// 数値は Phase 2 で暫定、Phase 6-7 で試遊フィードバックを踏まえて調整する。
public struct ScoreState: Sendable, Equatable {
  public var good: Int = 0
  public var ok: Int = 0
  public var miss: Int = 0
  public var combo: Int = 0
  public var maxCombo: Int = 0
  public var totalScore: Int = 0

  public static let goodPoints = 300
  public static let okPoints = 100
  public static let comboBonus = 5

  public init() {}

  public mutating func record(_ result: JudgeResult) {
    switch result {
    case .good:
      good += 1
      combo += 1
      maxCombo = max(maxCombo, combo)
      totalScore += Self.goodPoints + combo * Self.comboBonus
    case .ok:
      ok += 1
      combo += 1
      maxCombo = max(maxCombo, combo)
      totalScore += Self.okPoints + combo * Self.comboBonus
    case .miss:
      miss += 1
      combo = 0
    }
  }

  /// 総ノーツ数(判定回数)。
  public var judgedCount: Int { good + ok + miss }

  /// 星評価(5 段階)。判定できたノーツに対する 良 の割合で判定。
  public func stars(totalExpected: Int) -> Int {
    guard totalExpected > 0 else { return 0 }
    let ratio = Double(good) / Double(totalExpected)
    switch ratio {
    case 0.95...: return 5
    case 0.80..<0.95: return 4
    case 0.60..<0.80: return 3
    case 0.35..<0.60: return 2
    case 0.10..<0.35: return 1
    default: return 0
    }
  }
}
