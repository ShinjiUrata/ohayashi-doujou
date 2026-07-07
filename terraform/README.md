# Terraform 運用ガイド

お囃子道場の GCP インフラ管理。dev / prod の 2 環境を扱う。afterglow の運用実績を踏襲したフラット構成。

## 環境構成

| 環境 | GCP プロジェクト | state バックエンド | 変数ファイル |
|---|---|---|---|
| dev | `ohayashi-doujou-dev` | `gs://ohayashi-doujou-terraform-state/dev/` | `terraform.tfvars` |
| prod | `ohayashi-doujou-prod` | `gs://ohayashi-doujou-terraform-state/prod/` | `env-prod.tfvars` |

## クイックスタート

### 初回セットアップ

1. `dev_documents/implementation_notes/phase4_bootstrap.md` に沿って手動セットアップを実施
2. `terraform.tfvars.example` をコピーして `terraform.tfvars` / `env-prod.tfvars` を作成、値を埋める
3. `./tf.sh dev init` を実行して provider インストール
4. `./import.sh dev` を実行して手動作成済みリソースを取り込み
5. `./tf.sh dev plan` で差分ゼロを確認 → 完了
6. prod 側も同様に実施

### 認証

```bash
gcloud auth application-default login   # 初回 / 期限切れ時
```

### dev / prod 切替実行

必ず `tf.sh` を経由する。引数チェック・backend 切替・var-file 渡しを一括で行う。

```bash
# dev
./tf.sh dev plan
./tf.sh dev apply

# prod (PROD への操作と警告される)
./tf.sh prod plan
./tf.sh prod apply
```

### 任意の追加引数を渡す

```bash
./tf.sh dev plan -refresh=false
./tf.sh prod plan -target=google_cloud_run_v2_service.api
```

## ファイル構成

```
terraform/
├── README.md                    ← 本ファイル
├── tf.sh                        ← 環境切替ラッパー (推奨入口)
├── import.sh                    ← 既存リソース取り込み
├── main.tf                      ← provider / backend / locals
├── variables.tf                 ← 変数定義 (dev/prod 共通)
├── artifact_registry.tf         ← Docker イメージ格納
├── cloudrun.tf                  ← api サービス
├── storage.tf                   ← charts バケット + IAM
├── firestore.tf                 ← DB
├── iam.tf                       ← SA + 権限
├── logging.tf                   ← Log Router 除外
├── monitoring.tf                ← 予算 / GCS 頻度 / ログ量アラート
├── secret_manager.tf            ← Apple .p8 用 (枠のみ)
├── backend-dev.hcl              ← dev backend 設定
├── backend-prod.hcl             ← prod backend 設定
├── terraform.tfvars             ← dev 変数値 (gitignored)
├── env-prod.tfvars              ← prod 変数値 (gitignored)
├── terraform.tfvars.example     ← サンプル (git 管理)
└── .gitignore
```

## Terraform で管理しないもの

- **Docker イメージ**: CI/CD が push、Cloud Run image は `lifecycle.ignore_changes`
- **Secret 値**: `.p8` の中身は手動投入 (`gcloud secrets versions add`)
- **Firestore ドキュメント**: データプレーン、アプリ経由
- **GCS 内の譜面 JSON**: データプレーン、アプリ経由
- **予算アラート**: billing account に紐づくため、Console で手動設定 (Terraform で持たない)
- **プロジェクト自体、state バケット、Terraform SA**: 鶏卵、`phase4_bootstrap.md` で手動

## 出力

`./tf.sh <env> output` で取得。iOS 側の xcconfig に反映する:

- `api_url`: Cloud Run の URL(例: `https://api-<hash>.asia-northeast1.run.app`)
- `charts_bucket_public_url_prefix`: 譜面 URL の prefix(例: `https://storage.googleapis.com/ohayashi-charts-dev`)

## 緊急対応

`cost_protection.md` §2D の Runbook を参照。GCS への大量 DL を検知したら:

```bash
# 公開停止
gsutil iam ch -d allUsers:objectViewer gs://ohayashi-charts-prod

# 復旧
gsutil iam ch allUsers:objectViewer gs://ohayashi-charts-prod
```
