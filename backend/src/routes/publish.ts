import { Hono } from "hono";
import { ApiError } from "../types/errors.js";
import { validateChartJson } from "../validators/chart-json.js";
import { verifySignedTransaction } from "../services/jws.js";
import { claimTransactionAndChart } from "../services/firestore.js";
import { uploadChart } from "../services/storage.js";
import { config } from "../config.js";
import type { Chart } from "../types/chart.js";

/**
 * POST /publish
 *
 * StoreKit 2 決済成功後に、譜面 JSON をサーバー側にアップロードする。
 *
 * リクエスト: { signed_transaction: string (JWS), chart_json: Chart }
 * レスポンス:
 *   200 { id: string }              — 成功
 *   400 { code: "INVALID_REQUEST" } — バリデーション失敗
 *   402 { code: "TRANSACTION_ALREADY_USED" | "TRANSACTION_INVALID" } — JWS 関連
 *   409 { code: "ID_CONFLICT" }     — ID 競合
 *   413 { code: "PAYLOAD_TOO_LARGE" }
 *   500 { code: "INTERNAL_ERROR" }
 */

// リクエストの最大サイズ (100 KB)。security.md §5 参照。
const MAX_CHART_JSON_BYTES = 100 * 1024;

export const publishRoute = new Hono();

publishRoute.post("/publish", async (c) => {
  // 1) Content-Length で先に弾く
  const contentLength = Number(c.req.header("content-length") ?? "0");
  if (contentLength > MAX_CHART_JSON_BYTES) {
    return c.json({ code: "PAYLOAD_TOO_LARGE" }, 413);
  }

  // 2) JSON パース
  const body = await c.req.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return c.json({ code: "INVALID_REQUEST" }, 400);
  }
  const { signed_transaction: jws, chart_json: rawChart } = body as {
    signed_transaction?: unknown;
    chart_json?: unknown;
  };
  if (typeof jws !== "string") {
    return c.json({ code: "INVALID_REQUEST" }, 400);
  }

  // 3) chart_json バリデーション
  const validation = validateChartJson(rawChart);
  if (!validation.ok) {
    return c.json({ code: "INVALID_REQUEST" }, 400);
  }
  const chart = rawChart as Chart;

  try {
    // 4) JWS 検証
    const verified = await verifySignedTransaction(jws);

    // 5) bundle_id / product_id / environment の整合チェック
    if (verified.bundleId !== config.appleBundleId) {
      throw new ApiError("TRANSACTION_INVALID", 402, "bundle_id mismatch");
    }
    if (verified.productId !== config.appleProductId) {
      throw new ApiError("TRANSACTION_INVALID", 402, "product_id mismatch");
    }
    const expectedEnv = config.environment === "prod" ? "Production" : "Sandbox";
    if (verified.environment !== expectedEnv) {
      throw new ApiError("TRANSACTION_INVALID", 402, "environment mismatch");
    }
    // purchase 時刻の妥当性
    const nowMs = Date.now();
    const dayMs = 24 * 60 * 60 * 1000;
    if (
      verified.purchasedAtMs > nowMs + dayMs ||
      verified.purchasedAtMs < nowMs - dayMs
    ) {
      throw new ApiError("TRANSACTION_INVALID", 402, "purchase time out of range");
    }

    // 6) Firestore に atomic に台帳記録 (transaction_id 二重使用 + chart_id 競合を同時判定)
    const claimed = await claimTransactionAndChart({
      transactionId: verified.transactionId,
      chartId: chart.id,
      productId: verified.productId,
      purchasedAtMs: verified.purchasedAtMs,
      bundleId: verified.bundleId,
      name: chart.name,
      region: chart.region,
    });
    if (!claimed.ok) {
      const status = claimed.reason === "TRANSACTION_ALREADY_USED" ? 402 : 409;
      return c.json({ code: claimed.reason }, status);
    }

    // 7) GCS へアップロード
    await uploadChart(chart, new Date());

    return c.json({ id: chart.id });
  } catch (err) {
    if (err instanceof ApiError) {
      return c.json({ code: err.code }, err.status as 400 | 402 | 409 | 413 | 500);
    }
    console.error("[publish] internal error", err);
    return c.json({ code: "INTERNAL_ERROR" }, 500);
  }
});
