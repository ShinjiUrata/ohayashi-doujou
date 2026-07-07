import { Hono } from "hono";
import { isValidChartId } from "../validators/chart-id.js";
import { isChartIdTaken } from "../services/firestore.js";

/**
 * POST /check-id
 *
 * 公開ボタン押下前に、指定 ID が既に使われていないかを事前確認する。
 * 課金完了後に ID 重複エラーで決済損失を招くのを防ぐため。
 *
 * リクエスト: { id: string }
 * レスポンス:
 *   200 { available: true }  — 使える
 *   409 { available: false, code: "ID_CONFLICT" }  — 使用済み
 *   400 { code: "INVALID_REQUEST" }  — バリデーション失敗
 */

export const checkIdRoute = new Hono();

checkIdRoute.post("/check-id", async (c) => {
  const body = await c.req.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return c.json({ code: "INVALID_REQUEST" }, 400);
  }
  const id = (body as { id?: unknown }).id;
  if (!isValidChartId(id)) {
    return c.json({ code: "INVALID_REQUEST" }, 400);
  }

  const taken = await isChartIdTaken(id);
  if (taken) {
    return c.json({ available: false, code: "ID_CONFLICT" }, 409);
  }
  return c.json({ available: true });
});
