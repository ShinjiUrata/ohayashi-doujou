import Foundation

/// 譜面 JSON のローカル永続化。
///
/// 保存先: `Application Support/charts/{id}.json`。
/// Documents 直下を避けることで `UIFileSharingEnabled = NO` の運用と整合する。
///
/// Phase 1 では最低限の API を用意し、Phase 3 で本格運用する。
public actor ChartStorage {
  public static let shared = ChartStorage()

  private let fileManager: FileManager
  private let baseURL: URL

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
    let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    self.baseURL = support.appendingPathComponent("charts", isDirectory: true)
  }

  /// 保存ディレクトリを初回起動時に用意する。
  public func ensureDirectory() throws {
    if !fileManager.fileExists(atPath: baseURL.path) {
      try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }
  }

  /// 指定 ID の譜面を読み込む。
  public func load(id: String) throws -> Chart {
    let url = fileURL(for: id)
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(Chart.self, from: data)
  }

  /// 譜面を保存する。同 ID は上書き。
  public func save(_ chart: Chart) throws {
    try ensureDirectory()
    let url = fileURL(for: chart.id)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(chart)
    // 一時ファイル経由で書き込むことで、書き込み途中に落ちても破損ファイルが残らない。
    let tmpURL = url.appendingPathExtension("tmp")
    try data.write(to: tmpURL, options: .atomic)
    if fileManager.fileExists(atPath: url.path) {
      _ = try fileManager.replaceItemAt(url, withItemAt: tmpURL)
    } else {
      try fileManager.moveItem(at: tmpURL, to: url)
    }
  }

  /// 指定 ID の譜面が存在するか。
  public func exists(id: String) -> Bool {
    fileManager.fileExists(atPath: fileURL(for: id).path)
  }

  /// 指定 ID の譜面を削除する。存在しない場合は何もしない。
  public func delete(id: String) throws {
    let url = fileURL(for: id)
    guard fileManager.fileExists(atPath: url.path) else { return }
    try fileManager.removeItem(at: url)
  }

  private func fileURL(for id: String) -> URL {
    baseURL.appendingPathComponent("\(id).json")
  }
}
