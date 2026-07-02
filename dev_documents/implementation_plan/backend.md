# バックエンド実装手順

このドキュメントはバックエンド(GCP + Cloud Run + Cloud Storage + Firestore)の実装を項目単位で網羅する。
各項目には「何を / 技術 / 粒度 / 対応 Phase」を明記する。

参照:
- 全体設計: `CLAUDE.md` §3.8
- インフラ構成案: `infra-proposal.html`
- コスト保護: `dev_documents/implementation_notes/cost_protection.md`

---

## 全体方針

- **GCP に統一**(Cloud Run + Cloud Storage + Firestore)
- 東京リージョン(`asia-northeast1`)
- 開発 / 本番プロジェクトを分離(`ohayashi-doujou-dev` / `ohayashi-doujou-prod`)
- **インフラは可能な限り Terraform 管理**(afterglow のフラット構成を踏襲、詳細は `implementation_notes/terraform_and_deployment.md`)
- **Cloud Load Balancer は MVP では使わない**(月額固定 $18 発生を避け、無料枠内運用を維持)
- 無料枠内での運用が前提、規模拡大時に段階的にスケール
- iOS アプリからのアクセスは匿名(認証なし)
- 譜面一覧 API は設けない
- 更新公開機能なし(取り下げ→再公開の課金回避を防ぐ設計)

---

## 1. GCP プロジェクト構成

**何を**: 本番・開発の 2 プロジェクトを作り、リソースを分離する。

**技術**: GCP Console(プロジェクト作成)、`gcloud` CLI(API 有効化・SA 作成)、Terraform(以降の全リソース)

**粒度**:
- 本番: `ohayashi-doujou-prod`
- 開発: `ohayashi-doujou-dev`
- 課金アカウントの紐付け(法人カード)
- リージョン: `asia-northeast1`(東京)固定
- 予算アラート: **¥500 / ¥1,000 / ¥3,000** の 3 段階(cost_protection.md §2A)
- 通知チャネル: メール(法人代表アドレス)
- Terraform state バケット: `ohayashi-doujou-terraform-state`(単一、prefix で `dev/` `prod/` 分離、prod プロジェクト配下)

**Phase**: Phase 4(バックエンド着手時に最初)

**手動 vs Terraform**: プロジェクト作成・API 有効化・state バケット作成までは手動。以降は Terraform 管理下(詳細: `implementation_notes/terraform_and_deployment.md` §3)

---

## 2. Cloud Storage(公開バケット)

**何を**: 譜面 JSON を配信する公開バケット。

**技術**: Cloud Storage(Terraform: `storage.tf`)

**粒度**:
- バケット名: `ohayashi-charts-prod` / `ohayashi-charts-dev`
- リージョン: `asia-northeast1`
- Storage class: Standard
- 公開設定:
  - `allUsers` に `Storage Object Viewer` 権限のみ付与
  - **`Storage Object Lister` は付与しない**(一覧 API を意図的に無効化)
- CORS: モバイルアプリからの GET のみ想定なので基本不要(将来 Web からアクセス予定なら設定)
- Object Versioning: 有効(誤削除への保険)
- **アプリからのアクセス URL**: **直接 GCS URL**(`https://storage.googleapis.com/ohayashi-charts-{env}/{id}.json`)を採用
  - MVP は Cloud Load Balancer を使わない(月額 $18 の固定料金発生を避ける)
  - URL は iOS 側にハードコード、ユーザーが目にすることはない
  - 将来カスタムドメインが必要になれば Phase 6+ で Load Balancer + Backend Bucket に移行
- ライフサイクル: なし(手動削除のみ)

**Phase**: Phase 4

---

## 3. Firestore

**何を**: トランザクション台帳と譜面メタデータの記録。

**技術**: Firestore Native mode

**粒度**:

### コレクション設計

#### `charts`
- ドキュメント ID = `chart_id`(制作者指定の ID)
- フィールド:
  - `chart_id` (string) — 冗長だがクエリしやすくするため
  - `name` (string)
  - `region` (string)
  - `created_at` (timestamp)
  - `transaction_id` (string) — 対応する Apple トランザクション
  - `status` (string) — `public` | `withdrawn`

#### `transactions`
- ドキュメント ID = `transaction_id`(Apple 側 ID)
- フィールド:
  - `transaction_id` (string)
  - `chart_id` (string)
  - `product_id` (string) — `rhythm.chart.publish.single`
  - `purchased_at` (timestamp) — Apple 側 originalPurchaseDate
  - `verified_at` (timestamp) — サーバー側検証時刻
  - `bundle_id` (string) — 認証 Bundle ID(ログ用)

### インデックス
- 基本的なドキュメント ID 検索のみで足りる(単一 ID の存在確認が主用途)
- 追加インデックス不要

### セキュリティルール
- Cloud Run のサービスアカウント経由でのみ書き込み可
- クライアント SDK からの直接アクセスは一切不可(default deny)

**Phase**: Phase 4

---

## 4. Cloud Run(API サーバー)

**何を**: `/check-id` と `/publish` を提供する HTTP サーバー。

**技術選定**:

| 候補 | メリット | デメリット |
|---|---|---|
| Node.js (TypeScript) | Apple サンプル充実、JWS ライブラリ多い、開発速度 | メモリ使用量やや大 |
| Go | 起動早い、シングルバイナリ、コンテナ小 | Apple 系ライブラリの選択肢が少なめ |
| Python (FastAPI) | 開発速度、`app-store-server-library` 公式 | 起動やや遅い、cold start に不利 |

**推奨**: **Node.js (TypeScript) + Hono**
- 理由: Apple 公式が Node.js/Swift/Java/Python の `app-store-server-library` を提供、Hono は Cloud Run に相性良し(高速起動、軽量)、TypeScript の型安全で JWS のような構造化ペイロードを扱いやすい

**Phase**: Phase 4

---

## 5. エンドポイント: `POST /check-id`

**何を**: 公開 ID の重複を課金前に確認する(決済損失防止)。

**技術**: Hono ルート、Firestore Admin SDK

**粒度**:
- リクエスト: `{ id: string }`
- バリデーション: 小英数ハイフン、3〜64 文字(サーバー側でも検証)
- Firestore `charts` に該当 ID のドキュメントが存在するか確認
  - 存在しない → `200 OK { available: true }`
  - 存在する → `409 Conflict { available: false }`
- レートリミット: IP ベースの簡易制限(Cloud Run の Concurrency + 独自メモリキャッシュで暫定)
- ログ: `chart_id` + 結果のみ(必要最小限)

**Phase**: Phase 4

---

## 6. エンドポイント: `POST /publish`

**何を**: IAP 決済成功後、譜面 JSON を検証・保存する。

**技術**: Hono、`app-store-server-library` (Node.js)、Firestore、GCS

**粒度**:

### リクエスト
```json
{
  "signed_transaction": "<JWS>",
  "chart_json": { /* Chart 全体 */ }
}
```

### 処理ステップ

1. **リクエストサイズ制限**
   - `chart_json` を最大 100KB に制限(悪意ある大サイズ攻撃防止)
   - 通常譜面は数十 KB 想定

2. **JWS 検証**
   - Apple の公開鍵 / x509 チェーンで署名検証
   - 検証失敗 → `402 Payment Required`
   - `bundle_id` が本番の `com.zembrem.ohayashidoujou` と一致することを確認
   - `product_id` が `rhythm.chart.publish.single` と一致することを確認

3. **transaction_id 重複チェック(Firestore)**
   - 既に使われていれば `402 Payment Required`(二重使用防止)

4. **chart_json 内容検証**
   - `id`(公開 ID)存在・バリデーション(小英数ハイフン、3〜64 文字)
   - `notes` 配列存在、要素の型検証
   - `duration_ms` 妥当性(0 < x < 600000 くらい)

5. **chart_id 重複チェック(Firestore)**
   - 存在すれば `409 Conflict`(check-id を通ってもレースあり得る)

6. **GCS へアップロード**
   - `{id}.json` として保存
   - Content-Type: `application/json`
   - Cache-Control: `public, max-age=3600`(端末側もキャッシュするが CDN 前提時のヒント)

7. **Firestore に台帳記録**
   - `transactions` + `charts` にトランザクショナルに書き込み
   - Firestore トランザクションで一貫性を担保

8. **レスポンス**: `200 OK { id: string }`

### エラー
- `400` — 不正入力(バリデーション失敗)
- `402` — JWS 検証失敗 / transaction 重複
- `409` — chart_id 競合
- `500` — サーバーエラー

**Phase**: Phase 4(基本)/ Phase 5(JWS 検証接続)

---

## 7. Apple JWS 検証

**何を**: StoreKit 2 の Transaction JWS を検証し、trusted な情報を取り出す。

**技術**: `app-store-server-library` (Node.js, Apple 公式)

**粒度**:
- 公式ライブラリの `SignedDataVerifier` を使用
- ローカル検証(Apple のルート証明書チェーンで verify)のみで MVP は十分
  - App Store Server API の `getTransactionInfo` 呼び出しは Phase 6+ で拡張余地
- 検証結果から取り出す情報:
  - `transactionId`
  - `originalTransactionId`
  - `productId`
  - `bundleId`
  - `purchaseDate`
  - `environment` (Sandbox / Production)
- Bundle ID / Product ID / Environment の一致確認は必須

**Phase**: Phase 5

---

## 8. IAM / セキュリティ

**何を**: サービスアカウントと権限の最小化。

**技術**: GCP IAM

**粒度**:

### Cloud Run サービスアカウント
- `cloudrun-charts@ohayashi-doujou-prod.iam.gserviceaccount.com`
- 権限:
  - `roles/datastore.user`(Firestore 読み書き)
  - `roles/storage.objectAdmin`(charts バケットのみに限定、条件付き IAM)
  - `roles/logging.logWriter`

### Cloud Run サービス設定
- **未認証呼び出しを許可**(アプリからの匿名 POST を受け付ける)
- IP 制限は基本かけない(iOS アプリの多様なネットワーク環境のため)

### Cloud Storage
- `allUsers`: `Storage Object Viewer` のみ
- `cloudrun-charts` SA: `Storage Object Admin`(バケット内でのみ)

### Firestore
- クライアント SDK からの直接アクセスなし(セキュリティルール default deny)
- Cloud Run SA のみ Admin 権限

**Phase**: Phase 4

---

## 9. デプロイ(IaC + CI/CD)

**何を**: Cloud Run へのコンテナデプロイと、それを取り巻く GCP リソース全体の管理。

**技術**: **Terraform**(インフラ)+ **Docker**(イメージ)+ **GitHub Actions**(CI/CD)+ `gcloud` CLI(手動フェーズ)

### インフラは Terraform
- afterglow のフラット構成を踏襲(モジュール分割せず、リソース種別ごとの `*.tf`)
- `backend-{env}.hcl` + `env-{env}.tfvars` の対で環境切替
- **`tf.sh`** ラッパー経由でのみ実行(dev/prod 取り違え事故防止)
- state は `gs://ohayashi-doujou-terraform-state/{dev|prod}/`
- 詳細: `implementation_notes/terraform_and_deployment.md`

### Cloud Run のデプロイ責務境界
- **Terraform**: サービス定義(SA、CPU、メモリ、env vars、min/max instances)
- **CI/CD**: **イメージタグのみ** 更新(`lifecycle.ignore_changes = [template[0].containers[0].image]` で drift 回避)
- Docker build → Artifact Registry に push → `gcloud run deploy --image` は GitHub Actions が担う

### Dockerfile
- Multi-stage build(build stage で TypeScript コンパイル、runtime に slim イメージ)
- 最終イメージサイズを 100MB 以下に抑える
- Artifact Registry: `asia-northeast1-docker.pkg.dev/ohayashi-doujou-{env}/api/api:{tag}`

### Cloud Run 設定(Terraform 管理)
- Min instances: 0(cold start 許容、料金節約)
- Max instances: dev=5 / prod=10
- Concurrency: 80(デフォルト)
- Timeout: 60 秒
- CPU: 1 vCPU, Memory: 512 MiB
- 未認証呼び出し許可(アプリからの匿名 POST)
- 環境変数: `PROJECT_ID`, `CHARTS_BUCKET`, `ENVIRONMENT`, `APPLE_BUNDLE_ID`, `APPLE_PRODUCT_ID`
- Secret Manager 経由参照: Apple `.p8`

### CI/CD Workflow(afterglow 命名踏襲)
```
.github/workflows/
├── terraform-ci.yml    ← PR で tf.sh dev plan / tf.sh prod plan
├── api-ci.yml          ← PR で TS lint + Jest
├── api-dev-cd.yml      ← main マージで dev デプロイ
├── api-prod-cd.yml     ← 手動承認 → prod デプロイ
└── ios-ci.yml          ← Xcode ビルド + Swift Testing
```

### 認証(Workload Identity Federation)
- GitHub Actions → GCP は **WIF 経由**(SA `.json` 鍵をリポジトリに置かない)
- afterglow と同じ方式

### 手動デプロイの許容範囲
- Phase 4 前半のみ(Terraform 化前の hello-world 初回デプロイ)
- 緊急 rollback は gcloud で(後で state と実状態を突合)

**Phase**: Phase 4(Terraform + 手動デプロイ)/ Phase 5(CI/CD 自動化)

---

## 10. 監視・ログ・アラート

**何を**: `cost_protection.md` のチェックリスト全消化。

**技術**: Cloud Logging, Cloud Monitoring, Log Router

**粒度**:

### ログ(cost_protection.md §1)
- Cloud Run 内で構造化ログ(JSON)のみ出力
- INFO: `transaction_id`, `chart_id`, `duration_ms` の最小情報
- ERROR: 概要 + trace ID(スタックトレースは Error Reporting へ)
- リクエストボディの全ログ出力は禁止
- Log Router で HTTP 200 かつ `severity<ERROR` を `_Default` sink から除外
- 保持期間: 14 日

### アラート(cost_protection.md §1D, §2A/B)
- 日次ログ量 1GB/日 → Warning
- 月次ログ量 20GB/月 → Critical
- 予算 ¥500 / ¥1,000 / ¥3,000 の 3 段階(§2A)
- バケット req 頻度: 1 時間 1K / 10K で Warning / Critical(§2B)

### 通知チャネル
- メール(必須)
- Slack 等(検討)

**Phase**: Phase 4(必須、リリース前)

---

## 11. URL 方針(独自ドメインなし)

**何を**: iOS アプリからアクセスする URL の設計。**本プロジェクトでは独自ドメインを取得しない方針**。

**技術**: Cloud Run 発行デフォルト URL + GCS の直接 URL

**粒度**:

### 方針: 独自ドメイン取得なし + Cloud Load Balancer なし
- 独自ドメインを取得しない(維持コスト・DNS 管理を省く)
- Cloud Load Balancer も使わない(月額 $18 の固定料金を回避)
- Cloud Run Custom Domain Mapping も不要
- 結果: **DNS 関連の作業が一切発生しない**

### API(Cloud Run)
- URL は Cloud Run が自動発行するデフォルト URL を使う
- 形式: `https://api-<hash>.asia-northeast1.run.app`
  - dev / prod で hash が異なる別 URL
- SSL は自動、証明書管理不要
- iOS 側の xcconfig に **Cloud Run サービス作成後**に実 URL を反映
- Terraform 出力から URL を取得:
  ```hcl
  output "api_url" {
    value = google_cloud_run_v2_service.api.uri
  }
  ```

### 譜面配信(GCS)
- 直接 GCS URL を使う
- 形式: `https://storage.googleapis.com/ohayashi-charts-{env}/{id}.json`
  - dev: `https://storage.googleapis.com/ohayashi-charts-dev/{id}.json`
  - prod: `https://storage.googleapis.com/ohayashi-charts-prod/{id}.json`
- URL は iOS 側にハードコード、ユーザーが目にする機会なし

### URL 変更耐性
- Cloud Run のデフォルト URL は **サービス削除 → 再作成で hash が変わる**リスクあり
  - 通常の Terraform 運用では発生しない(サービス名保持)
  - 万一の場合は iOS アプリの再ビルド + AppStore 更新が必要
- MVP スケールではこのリスクは無視できる

### 将来の拡張(Phase 6+)
- ブランド化・SEO 上の必要が出たら独自ドメイン取得 + Load Balancer + CDN 導入を検討
- iOS 側は xcconfig の URL 定数を書き換えるだけで対応可能

**Phase**: Phase 4

---

## 12. データバックアップ

**何を**: Firestore と Cloud Storage のバックアップ。

**技術**: Cloud Scheduler, Firestore Export, GCS Object Versioning

**粒度**:
- Firestore: 週次エクスポートを GCS の別バケットへ(Cloud Scheduler + Cloud Function or Cloud Run Job)
- Cloud Storage(charts バケット): Object Versioning で誤削除に備える(30 日保持)
- リストア手順は Runbook 化

**Phase**: Phase 4(基本)/ Phase 5(自動化)

---

## 13. テスト

**何を**: バックエンドロジックの妥当性検証。

**技術**: Jest, Firebase Emulator Suite

**粒度**:

### ユニットテスト
- JWS 検証ロジック(Apple のサンプル JWS で検証)
- リクエストバリデーション(小英数ハイフン、長さ)
- エラー分岐

### 統合テスト
- Firestore Emulator + GCS モックで `/check-id` と `/publish` の E2E
- 並行 publish のレース検証(同一 chart_id で複数同時)

### 手動テスト
- Sandbox 経由の実 JWS で通しテスト
- Cloud Run 上での実接続確認

**Phase**: Phase 4(ユニット)/ Phase 5(統合)

---

## 14. リポジトリ / ディレクトリ構成

**何を**: `backend/` 配下のコード配置。

**技術**: TypeScript, Hono, Firebase Admin SDK

**粒度**:
```
backend/
├── src/
│   ├── index.ts             ← エントリポイント(Hono app 起動)
│   ├── routes/
│   │   ├── check-id.ts
│   │   └── publish.ts
│   ├── services/
│   │   ├── firestore.ts     ← Firestore ラッパー
│   │   ├── storage.ts       ← GCS ラッパー
│   │   └── jws.ts           ← JWS 検証
│   ├── types/
│   │   ├── chart.ts
│   │   └── errors.ts
│   ├── validators/
│   │   ├── chart-id.ts
│   │   └── chart-json.ts
│   └── config.ts            ← 環境変数読み込み
├── tests/
│   ├── unit/
│   └── integration/
├── Dockerfile
├── package.json
├── tsconfig.json
└── .env.example
```

**Phase**: Phase 4

---

## 15. Runbook(緊急対応手順)

**何を**: 悪意ある大量 DL 発生時の即応手順。

**技術**: gsutil, gcloud logging

**粒度**:
- `cost_protection.md §2D` のコマンドを README.md に転記
- Runbook を Notion / GitHub Wiki のいずれかに配置し、緊急時に判断せず実行できる状態に
- 通知連絡先(オンコール担当)を明記

**Phase**: Phase 4(リリース前必須)

---

## 16. Phase 対応マトリクス

| Phase | 実装項目(節番号) |
|---|---|
| Phase 4 前半 | 1(手動)、2, 3, 4, 5, 6(基本骨格), 8, 9(手動デプロイ), 10, 11, 12(基本), 13(ユニット), 14, 15 |
| Phase 4 後半 | 9(Terraform 化 + import) |
| Phase 5 | 6(JWS 接続), 7, 9(CI/CD 自動化), 13(統合) |
| Phase 6+ | 12(自動化), 監視の細分化, Cloud LB + CDN 導入検討 |

---

## 17. 将来の拡張ポイント(MVP 外)

- Cloud Load Balancer + Backend Bucket + Cloud CDN の導入(規模拡大時にカスタムドメイン付き charts 配信)
- App Store Server API の呼び出し追加(refund 通知の受信、Server-to-Server Notification)
- 管理ツール(譜面取り下げ、公開状態の一覧、返金対応)
- 楽曲データ配信(BGM 対応時)
- 譜面のメタデータ検索(規模拡大時に許容するかは要検討、現状は「発見手段は ID のみ」で意図的に閉じている)
