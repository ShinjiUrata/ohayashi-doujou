# お囃子道場 API

Cloud Run で動く TypeScript + Hono の API サーバー。
譜面公開 (`/publish`) と ID 事前確認 (`/check-id`) を提供する。

## 実装状況

| Phase | 内容 | 状態 |
|---|---|---|
| Phase 4 | Hono ルート、Firestore/GCS 書き込み、chart-json バリデーション | ✅ 実装 |
| Phase 5 | JWS 検証 (`app-store-server-library`) | 🚧 スタブ |

## エンドポイント

### GET /

ヘルスチェック。Cloud Run の readiness で使う。

### POST /check-id

```json
{ "id": "shimoda-2026-irihayashi" }
```

- `200 { available: true }` — 使える
- `409 { available: false, code: "ID_CONFLICT" }` — 使用済み
- `400 { code: "INVALID_REQUEST" }` — バリデーション失敗

### POST /publish

```json
{
  "signed_transaction": "<JWS from StoreKit 2>",
  "chart_json": { "id": "...", "notes": [...] }
}
```

- `200 { id: "..." }` — 成功
- `400 { code: "INVALID_REQUEST" }` — バリデーション失敗
- `402 { code: "TRANSACTION_ALREADY_USED" | "TRANSACTION_INVALID" }`
- `409 { code: "ID_CONFLICT" }`
- `413 { code: "PAYLOAD_TOO_LARGE" }`
- `500 { code: "INTERNAL_ERROR" }`

## 開発

```bash
npm install
npm run dev       # ウォッチモードでローカル起動
npm test          # Vitest でユニットテスト
npm run lint      # tsc --noEmit
npm run build     # dist/ に出力
```

### 環境変数 (ローカル開発時)

```
PROJECT_ID=ohayashi-doujou-dev
ENVIRONMENT=dev
CHARTS_BUCKET=ohayashi-charts-dev
APPLE_BUNDLE_ID=com.zembrem.ohayashidoujou
APPLE_PRODUCT_ID=rhythm.chart.publish.single
PORT=8080
```

Cloud Run 上ではこれらは terraform/cloudrun.tf 経由で自動設定される。

## デプロイ

```bash
# Docker image build & push
gcloud builds submit --tag asia-northeast1-docker.pkg.dev/${PROJECT_ID}/api/api:latest

# Cloud Run に反映
gcloud run deploy api \
  --image asia-northeast1-docker.pkg.dev/${PROJECT_ID}/api/api:latest \
  --region asia-northeast1 \
  --project ${PROJECT_ID}
```

CI/CD は `.github/workflows/api-{dev,prod}-cd.yml` で自動化する (Phase 4 終盤で追加)。

## 落とし穴

- `implementation_notes/security.md` の全項目を守る
- Cloud Run の image は Terraform の `lifecycle.ignore_changes` 対象 → CI/CD が更新
- ログは構造化 JSON、リクエストボディ全体を出力しない (`cost_protection.md` §1B)
