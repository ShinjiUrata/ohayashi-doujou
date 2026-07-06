import Foundation

/// 譜面全体を表すデータモデル。
///
/// - `id`: 公開 ID(サーバー上のグローバル ID)or ローカルドラフト UUID。
/// - `name` / `region`: メタデータ。
/// - `createdAt`: 作成時刻(ISO8601、サーバー時刻に上書きされる想定)。
/// - `durationMs`: 譜面全体の長さ (ms)。
/// - `notes`: 時系列の打点列。
///
/// 詳細は CLAUDE.md §3.7 を参照。
public struct Chart: Codable, Sendable, Equatable {
  public var id: String
  public var name: String
  public var region: String
  public var createdAt: Date
  public var durationMs: Int
  public var notes: [Note]

  public init(
    id: String,
    name: String,
    region: String,
    createdAt: Date,
    durationMs: Int,
    notes: [Note]
  ) {
    self.id = id
    self.name = name
    self.region = region
    self.createdAt = createdAt
    self.durationMs = durationMs
    self.notes = notes
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case region
    case createdAt = "created_at"
    case durationMs = "duration_ms"
    case notes
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(region, forKey: .region)
    try container.encode(Self.iso8601Formatter.string(from: createdAt), forKey: .createdAt)
    try container.encode(durationMs, forKey: .durationMs)
    try container.encode(notes, forKey: .notes)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.name = try container.decode(String.self, forKey: .name)
    self.region = try container.decode(String.self, forKey: .region)
    let dateString = try container.decode(String.self, forKey: .createdAt)
    guard let date = Self.iso8601Formatter.date(from: dateString) else {
      throw DecodingError.dataCorruptedError(
        forKey: .createdAt,
        in: container,
        debugDescription: "created_at is not a valid ISO8601 timestamp: \(dateString)"
      )
    }
    self.createdAt = date
    self.durationMs = try container.decode(Int.self, forKey: .durationMs)
    self.notes = try container.decode([Note].self, forKey: .notes)
  }

  // ISO8601DateFormatter は iOS 10+ でスレッドセーフ(Apple ドキュメント記載)。
  // Sendable 準拠していないため nonisolated(unsafe) で明示的に安全性を宣言する。
  nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
}

/// 一覧表示用の軽量サマリ(notes を含まない)。
///
/// ChartStorage.list() が軽量にパースするための型。Phase 3 で本格運用。
public struct ChartSummary: Sendable, Equatable {
  public let id: String
  public let name: String
  public let region: String
  public let createdAt: Date
  public let durationMs: Int
}
