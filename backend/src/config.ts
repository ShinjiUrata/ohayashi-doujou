/**
 * 環境変数から実行時設定を読み込む。
 *
 * Cloud Run では以下が terraform/cloudrun.tf 経由で自動的にセットされる:
 *  - PROJECT_ID
 *  - ENVIRONMENT (dev | prod)
 *  - CHARTS_BUCKET
 *  - APPLE_BUNDLE_ID
 *  - APPLE_PRODUCT_ID
 *  - APPLE_APP_APPLE_ID (App Store Connect でアプリ登録後、appAppleId 数値をセット。
 *                       未設定の間は JWS 検証を SANDBOX モードに強制フォールバック)
 *  - PORT (Cloud Run 自動指定)
 */

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`環境変数 ${name} が設定されていません`);
  }
  return value;
}

function optionalEnv(name: string, fallback: string): string {
  return process.env[name] ?? fallback;
}

function optionalNumberEnv(name: string): number | undefined {
  const value = process.env[name];
  if (!value) return undefined;
  const n = Number(value);
  return Number.isFinite(n) ? n : undefined;
}

export const config = {
  projectId: requireEnv("PROJECT_ID"),
  environment: requireEnv("ENVIRONMENT") as "dev" | "prod",
  chartsBucket: requireEnv("CHARTS_BUCKET"),
  appleBundleId: optionalEnv("APPLE_BUNDLE_ID", "com.zembrem.ohayashidoujou"),
  appleProductId: optionalEnv("APPLE_PRODUCT_ID", "rhythm.chart.publish.single"),
  appleAppAppleId: optionalNumberEnv("APPLE_APP_APPLE_ID"),
  port: Number(optionalEnv("PORT", "8080")),
};

export type AppConfig = typeof config;
