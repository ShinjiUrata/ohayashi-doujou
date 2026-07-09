import * as fs from "node:fs";
import * as path from "node:path";
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
} from "@apple/app-store-server-library";
import { config } from "../config.js";
import { ApiError } from "../types/errors.js";

/**
 * Apple StoreKit 2 の JWS を実際に検証する。
 *
 * 実装方針(`implementation_notes/security.md` §1-3):
 *  - Apple Root CA-G3 を bundle 同梱、SignedDataVerifier で verify
 *  - dev/prod で Environment を切り替え(SANDBOX / PRODUCTION)
 *  - bundle_id / product_id / environment / purchase_date の各種チェックは
 *    verify 内 + /publish の呼び出し側で二重にかける
 */

const CERTS_DIR = path.join(process.cwd(), "certs");

function loadRootCerts(): Buffer[] {
  if (!fs.existsSync(CERTS_DIR)) {
    throw new Error(`certs/ ディレクトリが存在しません: ${CERTS_DIR}`);
  }
  const files = fs
    .readdirSync(CERTS_DIR)
    .filter((f) => f.endsWith(".cer") || f.endsWith(".der"));
  if (files.length === 0) {
    throw new Error(`certs/ に Apple Root CA (.cer / .der) が見つかりません`);
  }
  return files.map((f) => fs.readFileSync(path.join(CERTS_DIR, f)));
}

const environment: Environment =
  config.environment === "prod" ? Environment.PRODUCTION : Environment.SANDBOX;

// SignedDataVerifier のコンストラクタ:
// (rootCertificates, enableOnlineChecks, environment, bundleId, appAppleId?)
const verifier: SignedDataVerifier = new SignedDataVerifier(
  loadRootCerts(),
  false, // OCSP / CRL のオンラインチェックは無効(オフライン検証で十分)
  environment,
  config.appleBundleId,
  undefined, // App Apple ID (Phase 6+ で使う可能性あり)
);

export interface VerifiedTransaction {
  transactionId: string;
  productId: string;
  bundleId: string;
  purchasedAtMs: number;
  environment: "Sandbox" | "Production";
}

/**
 * signedTransaction (JWS) を検証してデコードする。
 * 失敗時は ApiError("TRANSACTION_INVALID") を投げる。
 */
export async function verifySignedTransaction(
  signedTransaction: string,
): Promise<VerifiedTransaction> {
  if (typeof signedTransaction !== "string" || signedTransaction.length === 0) {
    throw new ApiError("TRANSACTION_INVALID", 402, "signed_transaction is empty");
  }

  let decoded: Awaited<ReturnType<SignedDataVerifier["verifyAndDecodeTransaction"]>>;
  try {
    decoded = await verifier.verifyAndDecodeTransaction(signedTransaction);
  } catch (err) {
    if (err instanceof VerificationException) {
      console.error(
        JSON.stringify({
          severity: "ERROR",
          message: "JWS verification failed",
          status: err.status,
          reason: err.message ?? "unknown",
        }),
      );
    } else {
      console.error(
        JSON.stringify({
          severity: "ERROR",
          message: "JWS decode threw",
          reason: err instanceof Error ? err.message : String(err),
        }),
      );
    }
    throw new ApiError("TRANSACTION_INVALID", 402, "JWS verification failed");
  }

  // 必須フィールド抽出。undefined ケースはライブラリ側では正常検証で
  // 埋められるはずだが、防御的にチェックしておく。
  const transactionId = decoded.transactionId;
  const productId = decoded.productId;
  const bundleId = decoded.bundleId;
  const purchaseDate = decoded.purchaseDate;

  if (!transactionId || !productId || !bundleId || typeof purchaseDate !== "number") {
    throw new ApiError("TRANSACTION_INVALID", 402, "JWS decoded but missing required fields");
  }

  const decodedEnv = (decoded.environment as string | undefined) ?? undefined;
  const envValue: "Sandbox" | "Production" =
    decodedEnv === "Production" ? "Production" : "Sandbox";

  return {
    transactionId: String(transactionId),
    productId: String(productId),
    bundleId: String(bundleId),
    purchasedAtMs: Number(purchaseDate),
    environment: envValue,
  };
}
