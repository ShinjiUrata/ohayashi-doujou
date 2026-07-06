import Foundation
import Testing
@testable import OhayashiDoujou

@Suite("ScoreState accumulation")
struct ScoreStateTests {
  @Test("Good increases combo and score")
  func recordGood() {
    var s = ScoreState()
    s.record(.good)
    #expect(s.good == 1)
    #expect(s.combo == 1)
    #expect(s.maxCombo == 1)
    #expect(s.totalScore == ScoreState.goodPoints + ScoreState.comboBonus)
  }

  @Test("OK increases combo but with fewer points than good")
  func recordOK() {
    var s = ScoreState()
    s.record(.ok)
    #expect(s.ok == 1)
    #expect(s.combo == 1)
    #expect(s.totalScore == ScoreState.okPoints + ScoreState.comboBonus)
    #expect(s.totalScore < ScoreState.goodPoints + ScoreState.comboBonus)
  }

  @Test("Miss resets combo but keeps maxCombo")
  func recordMissResetsCombo() {
    var s = ScoreState()
    s.record(.good)
    s.record(.good)
    s.record(.good)
    #expect(s.combo == 3)
    #expect(s.maxCombo == 3)
    s.record(.miss)
    #expect(s.miss == 1)
    #expect(s.combo == 0)
    #expect(s.maxCombo == 3)
  }

  @Test("Combo bonus grows with combo level")
  func comboBonusGrows() {
    var s = ScoreState()
    s.record(.good)
    let firstScore = s.totalScore
    s.record(.good)
    let secondScore = s.totalScore
    let firstDelta = firstScore
    let secondDelta = secondScore - firstScore
    #expect(secondDelta > firstDelta)
  }

  @Test("judgedCount sums all judgment types")
  func judgedCount() {
    var s = ScoreState()
    s.record(.good)
    s.record(.good)
    s.record(.ok)
    s.record(.miss)
    #expect(s.judgedCount == 4)
  }

  @Test("Stars are 5 when all good, 0 when all miss")
  func stars() {
    var perfect = ScoreState()
    for _ in 0..<10 { perfect.record(.good) }
    #expect(perfect.stars(totalExpected: 10) == 5)

    var terrible = ScoreState()
    for _ in 0..<10 { terrible.record(.miss) }
    #expect(terrible.stars(totalExpected: 10) == 0)
  }
}
