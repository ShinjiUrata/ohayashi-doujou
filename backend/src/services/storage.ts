import { Storage } from "@google-cloud/storage";
import { config } from "../config.js";
import type { Chart } from "../types/chart.js";

/**
 * Cloud Storage クライアント。charts バケットに JSON を書き込む。
 */
const storage = new Storage({
  projectId: config.projectId,
});

const chartsBucket = storage.bucket(config.chartsBucket);

/**
 * 譜面 JSON を GCS にアップロードする。
 * サーバー側で created_at を上書きしてから書き込む。
 */
export async function uploadChart(chart: Chart, createdAt: Date): Promise<void> {
  const finalChart: Chart = {
    ...chart,
    created_at: createdAt.toISOString(),
  };
  const file = chartsBucket.file(`${chart.id}.json`);
  const body = Buffer.from(JSON.stringify(finalChart), "utf-8");

  await file.save(body, {
    contentType: "application/json; charset=utf-8",
    resumable: false,
    metadata: {
      cacheControl: "public, max-age=3600",
    },
  });
}
