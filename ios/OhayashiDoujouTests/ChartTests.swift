import Foundation
import Testing
@testable import OhayashiDoujou

@Suite("Chart Codable")
struct ChartTests {
  @Test("Chart round-trip encoding preserves values")
  func chartRoundtripPreservesValues() throws {
    let original = Chart(
      id: "test-2026-irihayashi",
      name: "テスト譜面",
      region: "テスト町",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      durationMs: 5000,
      notes: [
        Note(t: 0, type: .don_l),
        Note(t: 450, type: .ka_r),
        Note(t: 900, type: .don_both),
        Note(t: 1350, type: .don_r, duration: 800),
      ]
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoded = try JSONDecoder().decode(Chart.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.name == original.name)
    #expect(decoded.region == original.region)
    #expect(decoded.durationMs == original.durationMs)
    #expect(decoded.notes == original.notes)
    // ISO8601(fractional seconds)なので丸め誤差 <1ms 想定
    #expect(abs(decoded.createdAt.timeIntervalSince(original.createdAt)) < 0.001)
  }

  @Test("Chart uses snake_case JSON keys")
  func chartSnakeCaseKeys() throws {
    let chart = Chart(
      id: "x",
      name: "n",
      region: "r",
      createdAt: Date(timeIntervalSince1970: 0),
      durationMs: 100,
      notes: []
    )
    let data = try JSONEncoder().encode(chart)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"created_at\""))
    #expect(json.contains("\"duration_ms\""))
  }

  @Test("Legacy notes without duration decode as single tap")
  func legacyNotesWithoutDurationDecode() throws {
    // 後方互換: 既存の 4 種のみ + duration なしの譜面が読めることを確認
    let legacyJson = """
    {
      "id": "legacy",
      "name": "n",
      "region": "r",
      "created_at": "2026-01-01T00:00:00.000Z",
      "duration_ms": 500,
      "notes": [
        { "t": 0, "type": "don_l" },
        { "t": 250, "type": "ka_r" }
      ]
    }
    """
    let data = try #require(legacyJson.data(using: .utf8))
    let chart = try JSONDecoder().decode(Chart.self, from: data)
    #expect(chart.notes.count == 2)
    #expect(chart.notes[0].duration == nil)
    #expect(chart.notes[0].isHold == false)
  }
}

@Suite("NoteType zones")
struct NoteTypeTests {
  @Test("Zone mapping is consistent with spec")
  func zoneMapping() {
    #expect(NoteType.ka_l.zone == .leftKa)
    #expect(NoteType.don_l.zone == .center)
    #expect(NoteType.don_r.zone == .center)
    #expect(NoteType.ka_r.zone == .rightKa)
    #expect(NoteType.don_both.zone == .centerBoth)
  }

  @Test("All raw values are lowercase snake_case")
  func rawValuesFormat() {
    for type in NoteType.allCases {
      let rawValue = type.rawValue
      #expect(rawValue == rawValue.lowercased())
    }
  }
}

@Suite("Note hold detection")
struct NoteHoldTests {
  @Test("Note without duration is not a hold")
  func singleTapNotHold() {
    let note = Note(t: 0, type: .don_l)
    #expect(note.isHold == false)
  }

  @Test("Note with duration > 0 is a hold")
  func holdNote() {
    let note = Note(t: 0, type: .don_l, duration: 800)
    #expect(note.isHold == true)
  }

  @Test("Note with duration 0 is not a hold")
  func zeroDurationNotHold() {
    let note = Note(t: 0, type: .don_l, duration: 0)
    #expect(note.isHold == false)
  }
}
