import Foundation

/// API 呼び出し結果のエラー種別。
///
/// ユーザーに提示するメッセージはこの型ベースで決める。
public enum APIError: LocalizedError, Sendable {
  case notFound
  case idConflict
  case invalidRequest
  case tooManyRequests
  case network(underlying: Error?)
  case decoding(underlying: Error)
  case server(statusCode: Int)
  case transactionInvalid
  case transactionAlreadyUsed

  public var errorDescription: String? {
    switch self {
    case .notFound: return "指定された譜面 ID は見つかりませんでした。"
    case .idConflict: return "この譜面 ID は既に使われています。別の ID を試してください。"
    case .invalidRequest: return "リクエストに問題があります。入力内容をご確認ください。"
    case .tooManyRequests: return "アクセスが多すぎます。少し待って再試行してください。"
    case .network: return "通信に失敗しました。電波状況をご確認ください。"
    case .decoding: return "サーバーからの応答を解釈できませんでした。"
    case .server(let status): return "サーバーエラーが発生しました (\(status))。"
    case .transactionInvalid: return "決済情報が不正です。"
    case .transactionAlreadyUsed: return "この決済は既に使われています。"
    }
  }
}
