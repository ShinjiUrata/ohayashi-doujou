import Foundation

/// バックエンド API と Cloud Storage 上の譜面 JSON へのクライアント。
///
/// 実装方針(`implementation_plan/ios.md` §14):
///  - `URLSession` async/await
///  - 環境切替は `AppConfig` 経由
///  - タイムアウト 30 秒(cold start 対応)
///  - リトライは自動化しない(ユーザー明示操作)
public actor APIClient {
  public static let shared = APIClient()

  private let session: URLSession
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder
  private let apiBase: URL
  private let chartsBase: URL

  public init(
    apiBase: URL = AppConfig.apiBaseURL,
    chartsBase: URL = AppConfig.chartsBaseURL
  ) {
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 30
    cfg.timeoutIntervalForResource = 60
    cfg.waitsForConnectivity = false
    self.session = URLSession(configuration: cfg)
    self.apiBase = apiBase
    self.chartsBase = chartsBase

    self.decoder = JSONDecoder()
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.sortedKeys]
  }

  // MARK: - Public API

  /// 譜面を GCS から取得する。
  /// - `id` はサーバー側でも改めて検証されるが、iOS 側でも同じルールで先に弾く。
  public func fetchChart(id: String) async throws -> Chart {
    let url = chartsBase.appendingPathComponent("\(id).json")
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await performData(req)
    guard let http = response as? HTTPURLResponse else {
      throw APIError.network(underlying: nil)
    }
    switch http.statusCode {
    case 200:
      do {
        return try decoder.decode(Chart.self, from: data)
      } catch {
        throw APIError.decoding(underlying: error)
      }
    case 404:
      throw APIError.notFound
    case 429:
      throw APIError.tooManyRequests
    case 500...599:
      throw APIError.server(statusCode: http.statusCode)
    default:
      throw APIError.server(statusCode: http.statusCode)
    }
  }

  /// 公開 ID が利用可能か事前確認する。
  /// - Returns: 利用可能なら true、既に使用済みなら false。
  public func checkID(_ id: String) async throws -> Bool {
    struct Body: Encodable { let id: String }
    let (data, response) = try await postJSON(
      path: "check-id",
      body: Body(id: id)
    )
    guard let http = response as? HTTPURLResponse else {
      throw APIError.network(underlying: nil)
    }
    switch http.statusCode {
    case 200:
      return true
    case 409:
      return false
    case 400:
      throw APIError.invalidRequest
    case 429:
      throw APIError.tooManyRequests
    case 500...599:
      throw APIError.server(statusCode: http.statusCode)
    default:
      _ = data // suppress unused warning
      throw APIError.server(statusCode: http.statusCode)
    }
  }

  /// 譜面を公開する。StoreKit 2 の JWS と Chart を渡すと、成功時に確定 ID が返る。
  /// Phase 5 で StoreKit 2 の実 JWS を渡すよう iOS 側で切替。
  public func publish(signedTransaction: String, chart: Chart) async throws -> String {
    struct Body: Encodable {
      let signed_transaction: String
      let chart_json: Chart
    }
    struct SuccessResponse: Decodable { let id: String }
    let body = Body(signed_transaction: signedTransaction, chart_json: chart)
    let (data, response) = try await postJSON(path: "publish", body: body)
    guard let http = response as? HTTPURLResponse else {
      throw APIError.network(underlying: nil)
    }
    switch http.statusCode {
    case 200:
      do {
        return try decoder.decode(SuccessResponse.self, from: data).id
      } catch {
        throw APIError.decoding(underlying: error)
      }
    case 400:
      throw APIError.invalidRequest
    case 402:
      // TRANSACTION_ALREADY_USED か TRANSACTION_INVALID かは body で判別する
      if let err = try? decoder.decode(ErrorBody.self, from: data),
         err.code == "TRANSACTION_ALREADY_USED" {
        throw APIError.transactionAlreadyUsed
      }
      throw APIError.transactionInvalid
    case 409:
      throw APIError.idConflict
    case 413:
      throw APIError.invalidRequest
    case 429:
      throw APIError.tooManyRequests
    case 500...599:
      throw APIError.server(statusCode: http.statusCode)
    default:
      throw APIError.server(statusCode: http.statusCode)
    }
  }

  // MARK: - Internal

  private struct ErrorBody: Decodable {
    let code: String
  }

  private func postJSON<Body: Encodable>(
    path: String,
    body: Body
  ) async throws -> (Data, URLResponse) {
    let url = apiBase.appendingPathComponent(path)
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
      req.httpBody = try encoder.encode(body)
    } catch {
      throw APIError.decoding(underlying: error)
    }
    return try await performData(req)
  }

  private func performData(_ req: URLRequest) async throws -> (Data, URLResponse) {
    do {
      return try await session.data(for: req)
    } catch {
      throw APIError.network(underlying: error)
    }
  }
}
