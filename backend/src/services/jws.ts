/**
 * Apple StoreKit 2 の JWS 検証。
 *
 * Phase 5 で app-store-server-library (Node.js) を組み込んで
 * 実装する。現状は「常に検証成功」を返すスタブ。
 *
 * Phase 5 で必ず実施する検証項目 (security.md §1):
 *  - JWS 署名の x509 チェーン検証
 *  - bundle_id が config.appleBundleId と一致
 *  - product_id が config.appleProductId と一致
 *  - environment が config.environment と整合 (dev → Sandbox / prod → Production)
 *  - purchaseDate が現在時刻から前後 24 時間以内
 */

import { ApiError } from "../types/errors.js";

export interface VerifiedTransaction {
  transactionId: string;
  productId: string;
  bundleId: string;
  purchasedAtMs: number;
  environment: "Sandbox" | "Production";
}

/**
 * Phase 4 段階のスタブ実装。
 * DEBUG ビルドとの疎通確認用に、常に固定の値を返す。
 * Phase 5 で必ず実 JWS 検証に置き換える。
 */
export async function verifySignedTransaction(
  signedTransaction: string,
): Promise<VerifiedTransaction> {
  if (typeof signedTransaction !== "string" || signedTransaction.length === 0) {
    throw new ApiError("TRANSACTION_INVALID", 402, "signed_transaction is empty");
  }
  // TODO(Phase 5): app-store-server-library で本検証を実装。
  // 現状はダミーで通す (Phase 4 の疎通確認のみを目的とする)。
  const now = Date.now();
  return {
    transactionId: `stub-${now}`,
    productId: "rhythm.chart.publish.single",
    bundleId: "com.zembrem.ohayashidoujou",
    purchasedAtMs: now,
    environment: "Sandbox",
  };
}
