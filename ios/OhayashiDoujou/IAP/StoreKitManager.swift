import Foundation
import StoreKit

/// StoreKit 2 統合の窓口。
///
/// - 単一の Consumable プロダクト `rhythm.chart.publish.single` を扱う
/// - 購入成功時は JWS(`verification.jwsRepresentation`)を取り出して返す
/// - **`finish(_:)` は必ず backend の `/publish` 成功後に呼ぶ**
///   (`ios_pitfalls.md` §10 / `client_reliability.md` §2 参照)
///
/// アプリ起動時から `Transaction.updates` を購読しており、未完了の
/// トランザクション(publish 未確定など)を検出したらログを残す。
/// 完全なリカバリ UI は Phase 6 で追加予定。
@MainActor
public final class StoreKitManager {
  public static let shared = StoreKitManager()

  /// backend / App Store Connect と同じ ID を使う。
  public static let publishProductID = "rhythm.chart.publish.single"

  private var cachedProduct: Product?
  private var updatesTask: Task<Void, Never>?

  private init() {
    startObservingUpdates()
  }

  // MARK: - Types

  /// 課金成功後、backend に投げるまでの中間状態。
  ///
  /// 呼び出し側は backend `/publish` が返って初めて `finish(_:)` を呼ぶ。
  /// backend が失敗したら **finish しない**ことで、次回 `Transaction.updates`
  /// で再送機会が残る。
  public struct PendingPurchase: Sendable {
    public let jws: String
    public let transactionId: String
    fileprivate let transaction: StoreKit.Transaction
  }

  public enum PurchaseError: Error, LocalizedError, Sendable {
    case productUnavailable
    case userCancelled
    case pending
    case verificationFailed
    case unknown

    public var errorDescription: String? {
      switch self {
      case .productUnavailable:
        return "商品情報の取得に失敗しました。時間をおいて再試行してください。"
      case .userCancelled:
        return "購入がキャンセルされました。"
      case .pending:
        return "購入が保留中です。承認をお待ちください(Ask to Buy 等)。"
      case .verificationFailed:
        return "決済情報の検証に失敗しました。"
      case .unknown:
        return "購入に失敗しました。"
      }
    }
  }

  // MARK: - Public API

  /// 商品情報を取得する。ChartPublishView の onAppear で先取りしておく想定。
  @discardableResult
  public func loadProduct() async -> Product? {
    if let cached = cachedProduct { return cached }
    do {
      let products = try await Product.products(for: [Self.publishProductID])
      cachedProduct = products.first
      return cachedProduct
    } catch {
      print("[StoreKit] loadProduct failed: \(error)")
      return nil
    }
  }

  /// 表示用の価格文字列(ロケール適用済み)。取得失敗時は nil。
  public func displayPrice() async -> String? {
    let product = await loadProduct()
    return product?.displayPrice
  }

  /// 課金ダイアログを起こす。
  public func purchase() async throws -> PendingPurchase {
    guard let product = await loadProduct() else {
      throw PurchaseError.productUnavailable
    }

    let result: Product.PurchaseResult
    do {
      result = try await product.purchase()
    } catch {
      print("[StoreKit] purchase() threw: \(error)")
      throw PurchaseError.productUnavailable
    }

    switch result {
    case .success(let verification):
      switch verification {
      case .verified(let transaction):
        return PendingPurchase(
          jws: verification.jwsRepresentation,
          transactionId: String(transaction.id),
          transaction: transaction
        )
      case .unverified:
        throw PurchaseError.verificationFailed
      }
    case .userCancelled:
      throw PurchaseError.userCancelled
    case .pending:
      throw PurchaseError.pending
    @unknown default:
      throw PurchaseError.unknown
    }
  }

  /// backend `/publish` が成功したときのみ呼ぶ。
  public func finish(_ pending: PendingPurchase) async {
    await pending.transaction.finish()
  }

  // MARK: - Background updates observer

  private func startObservingUpdates() {
    updatesTask?.cancel()
    updatesTask = Task.detached { [weak self] in
      for await update in StoreKit.Transaction.updates {
        guard let self else { break }
        await self.handleObservedTransaction(update)
      }
    }
  }

  private func handleObservedTransaction(
    _ verification: VerificationResult<StoreKit.Transaction>
  ) async {
    // Phase 5 段階:未完了トランザクションを検出してもここでは finish しない。
    // ChartPublishView で publish 成功 → finish する既定フローに委ねる。
    // Phase 6 で「未確定 publish の再送」UI を追加してここから駆動する予定。
    switch verification {
    case .verified(let transaction):
      print(
        "[StoreKit] observed pending transaction: id=\(transaction.id) product=\(transaction.productID)"
      )
    case .unverified(_, let error):
      print("[StoreKit] observed unverified transaction: \(error)")
    }
  }
}
