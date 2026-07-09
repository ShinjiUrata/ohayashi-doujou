import { Firestore } from "@google-cloud/firestore";
import { config } from "../config.js";

/**
 * Firestore クライアント。プロセス起動時に一度だけ初期化する。
 *
 * コレクション設計 (backend.md §3):
 *  - charts:       docId = chart_id
 *  - transactions: docId = transaction_id
 */
const firestore = new Firestore({
  projectId: config.projectId,
});

const chartsCol = firestore.collection("charts");
const transactionsCol = firestore.collection("transactions");

export interface ChartRecord {
  chart_id: string;
  name: string;
  region: string;
  created_at: FirebaseFirestore.Timestamp;
  transaction_id: string;
  status: "public" | "withdrawn";
}

export interface TransactionRecord {
  transaction_id: string;
  chart_id: string;
  product_id: string;
  purchased_at: FirebaseFirestore.Timestamp;
  verified_at: FirebaseFirestore.Timestamp;
  bundle_id: string;
}

/**
 * 公開 ID が既に使われているか事前確認する。
 * /check-id で呼ばれる。
 */
export async function isChartIdTaken(chartId: string): Promise<boolean> {
  const snap = await chartsCol.doc(chartId).get();
  return snap.exists;
}

/**
 * transaction_id + chart_id を atomic に台帳へ書き込む。
 * race condition を防ぐため runTransaction で:
 *  1) transactions/{transaction_id} が未使用か
 *  2) charts/{chart_id} が未使用か
 * を両方チェックしてから両方書き込む。
 */
export async function claimTransactionAndChart(params: {
  transactionId: string;
  chartId: string;
  productId: string;
  purchasedAtMs: number;
  bundleId: string;
  name: string;
  region: string;
}): Promise<{ ok: true } | { ok: false; reason: "TRANSACTION_ALREADY_USED" | "ID_CONFLICT" }> {
  return firestore.runTransaction(async (tx) => {
    const txRef = transactionsCol.doc(params.transactionId);
    const chartRef = chartsCol.doc(params.chartId);

    const [txSnap, chartSnap] = await Promise.all([tx.get(txRef), tx.get(chartRef)]);
    if (txSnap.exists) {
      return { ok: false, reason: "TRANSACTION_ALREADY_USED" as const };
    }
    if (chartSnap.exists) {
      return { ok: false, reason: "ID_CONFLICT" as const };
    }

    const now = new Date();
    tx.set(txRef, {
      transaction_id: params.transactionId,
      chart_id: params.chartId,
      product_id: params.productId,
      purchased_at: new Date(params.purchasedAtMs),
      verified_at: now,
      bundle_id: params.bundleId,
    });
    tx.set(chartRef, {
      chart_id: params.chartId,
      name: params.name,
      region: params.region,
      created_at: now,
      transaction_id: params.transactionId,
      status: "public",
    });
    return { ok: true as const };
  });
}
