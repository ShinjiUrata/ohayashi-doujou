# Terraform と CI/CD — 気をつけること

**位置付け**: インフラを Terraform で管理し、backend / iOS の CI/CD を GitHub Actions で回すための運用方針と落とし穴。afterglow プロジェクトのフラット構成を踏襲する。

**関連**:
- 実装手順: `dev_documents/implementation_plan/backend.md`(Terraform 前提に更新済み)、`others.md` §7(DNS 簡素化)
- 参照実績: `~/Devlopment/Company/afterglow/terraform/`、`~/Devlopment/Company/afterglow/.github/workflows/`

---

## 全体方針

- **フラット構成**(モジュール分割せず、リソース種別ごとの `*.tf` を単一ディレクトリに置く)
- 環境切替は **`backend-{env}.hcl` + `env-{env}.tfvars`** の対で行う(Workspace 方式は不採用)
- **`tf.sh` ラッパースクリプト** を必ず経由し、dev/prod 取り違え事故を防ぐ
- 土台の土台(GCP プロジェクト・state バケット・Terraform 用 SA)は永続的に手動管理
- CI/CD は afterglow と同じ `{service}-ci.yml` / `{service}-dev-cd.yml` / `{service}-prod-cd.yml` の 3 面持ち

---

## 1. プロジェクトと state バケットの命名

**確定事項**:
- GCP プロジェクト: `ohayashi-doujou-dev` / `ohayashi-doujou-prod`
- Terraform state バケット: **`ohayashi-doujou-terraform-state`(単一バケット)** に `dev/` `prod/` の prefix で分ける
- リージョン: `asia-northeast1`

**afterglow との差異**:
- afterglow の prod は `spanglow-terraform-state-prod` と別バケットを使っている(勘違いによる事故を物理的に防ぐため)
- お囃子道場は単一バケット + prefix 分けを採用(運用の単純化を優先)
- 代わりに `tf.sh` の prod 警告表示を強調して事故防止

---

## 2. ディレクトリ構成

```
terraform/
├── README.md                    ← 運用ガイド(afterglow 書式)
├── tf.sh                        ← 環境切替ラッパー(唯一の推奨入口)
├── main.tf                      ← provider / backend / locals
├── variables.tf                 ← 変数定義
├── artifact_registry.tf         ← Docker イメージ格納
├── cloudrun.tf                  ← api サービス(独自ドメインなし、デフォルト URL 使用)
├── storage.tf                   ← charts バケット + IAM
├── firestore.tf                 ← DB + セキュリティルール
├── iam.tf                       ← SA + 最小権限
├── logging.tf                   ← Log Router 除外(cost_protection §1A)
├── monitoring.tf                ← 予算 + ログ量 + GCS req 頻度
├── secret_manager.tf            ← Apple .p8 用(枠のみ、値は手動投入)
├── backend-dev.hcl
├── backend-prod.hcl
├── terraform.tfvars             ← dev 変数値(gitignored)
├── env-prod.tfvars              ← prod 変数値(gitignored)
├── terraform.tfvars.example     ← サンプル(git 管理)
├── import.sh                    ← 既存リソース取り込みスクリプト
├── .terraform.lock.hcl          ← providers 版バージョンロック(git 管理)
└── .gitignore                   ← *.tfvars、.terraform/、tfstate 等
```

---

## 3. 手動フェーズと Terraform 化フェーズの境界

### 手動フェーズ(Phase 4 前半)

「土台」だけ手動で作る。ここは永続的に IaC 外。

| 項目 | 実施ツール | 備考 |
|---|---|---|
| GCP プロジェクト作成(dev / prod) | GCP Console | 組織ポリシー・請求アカウント紐付けが絡むため Console が確実 |
| gcloud CLI 認証(ADC) | `gcloud auth application-default login` | ローカル環境の前提 |
| GCP API 有効化 | `gcloud services enable` | Cloud Run / Cloud Storage / Firestore / Cloud Logging / Cloud Monitoring / Artifact Registry / Cloud Build / IAM / Secret Manager |
| Firestore データベース作成 | GCP Console | プロジェクトあたり 1 個で不可逆、Console が最も安全 |
| Terraform state バケット作成 | `gcloud storage buckets create` | 鶏卵、Terraform で作れない |
| Terraform 実行用 SA + 初期権限 | gcloud | 同上 |
| Artifact Registry リポジトリ作成 | `gcloud artifacts repositories create` | Cloud Run 初回デプロイに必要 |
| Cloud Run 初回デプロイ(hello-world 等のダミー) | `gcloud run deploy` | Terraform 管理に置く前に「リソースが存在する」状態を作る |

### Terraform 化フェーズ(Phase 4 後半)

1. `terraform/` を配置し、`.tf` ファイル群を書き上げる
2. **`import.sh`** で手動作成済みリソースを Terraform state に import
3. `./tf.sh dev plan` で **差分ゼロ**を確認 → import 完了
4. 同様に prod も import
5. 以降のすべての変更は `.tf` ファイル経由で `./tf.sh {env} apply`

### 永続的に IaC 外(意図的に管理しないもの)

- GCP プロジェクト自体
- 請求アカウント紐付け
- Terraform state バケット + 実行用 SA
- Secret Manager の秘密の**値**(枠は Terraform、値は手動投入)
- Cloud Run にデプロイされる **Docker イメージ**(タグ参照のみ Terraform で、実物は CI/CD が push)

---

## 4. `tf.sh` ラッパー(afterglow から流用)

**必須**: dev/prod の取り違え事故を防ぐため、直接 `terraform` コマンドを叩かず必ず `tf.sh` を経由する。

```bash
./tf.sh dev plan          # dev 環境に対して plan
./tf.sh dev apply         # dev 環境に対して apply
./tf.sh prod plan         # prod は警告表示付き
./tf.sh prod apply
```

内部処理:
1. `terraform init -reconfigure -backend-config=backend-{env}.hcl` で backend 切替
2. `-var-file=env-{env}.tfvars` を明示指定
3. prod は警告バナー表示

**「backend 切替を忘れて dev に prod を apply した」は最も起こりやすい事故**。`tf.sh` を絶対的な入口に。

---

## 5. `import.sh`(既存リソースの取り込み)

**目的**: 手動で作った GCP リソースを Terraform state に取り込み、`plan` で差分ゼロにする。

**afterglow パターン**:
```bash
#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-dev}"
PROJECT_ID="ohayashi-doujou-${ENV}"

# GCS バケット
terraform import -var-file="env-${ENV}.tfvars" \
  google_storage_bucket.charts \
  "ohayashi-charts-${ENV}"

# Cloud Run サービス
terraform import -var-file="env-${ENV}.tfvars" \
  google_cloud_run_v2_service.api \
  "projects/${PROJECT_ID}/locations/asia-northeast1/services/api"

# Firestore
terraform import -var-file="env-${ENV}.tfvars" \
  google_firestore_database.default \
  "projects/${PROJECT_ID}/databases/(default)"

# ... 全リソース分繰り返す
```

**注意**:
- import 後は必ず `./tf.sh {env} plan` で差分ゼロを確認
- 差分が出たら `.tf` の記述を実状態に合わせて修正(手動で作った時の設定に合わせる)
- 完了したら `import.sh` は履歴として残す(再実施可能な形で)

---

## 6. state バケットの Bootstrap 手順

**手動で 1 度だけ実施**:

```bash
# 1) Terraform state 用バケット作成(単一バケット、両環境共用)
gcloud storage buckets create gs://ohayashi-doujou-terraform-state \
  --project=ohayashi-doujou-prod \
  --location=asia-northeast1 \
  --uniform-bucket-level-access

# 2) バージョニング有効化(誤削除・破損時のロールバック用)
gcloud storage buckets update gs://ohayashi-doujou-terraform-state \
  --versioning

# 3) ライフサイクル: 90 日で古いバージョンを削除
gcloud storage buckets update gs://ohayashi-doujou-terraform-state \
  --lifecycle-file=lifecycle.json
```

**なぜバケットは prod プロジェクト配下?**
- Terraform state は本番運用の心臓部
- dev プロジェクトを万一削除しても state が残る
- afterglow の prod パターンを踏襲

---

## 7. CI/CD Workflow の命名と役割

afterglow に倣い `{service}-ci.yml` / `{service}-dev-cd.yml` / `{service}-prod-cd.yml` の 3 面持ち。

```
.github/workflows/
├── ios-ci.yml              ← PR で Xcode ビルド + Swift Testing 実行
├── api-ci.yml              ← PR で TypeScript lint + Jest 実行
├── api-dev-cd.yml          ← main マージで Cloud Run dev へデプロイ
├── api-prod-cd.yml         ← tag or 手動承認で Cloud Run prod へデプロイ
└── terraform-ci.yml        ← PR で `tf.sh dev plan` / `tf.sh prod plan`
```

**iOS の CI**:
- GitHub Actions の macOS runner を使用(有料枠に注意、初期は月内無料枠で足りるはず)
- Xcode Cloud 併用の選択肢もあるが、afterglow との整合のため GitHub Actions で統一

**backend の CD**:
- Docker build → Artifact Registry に push → `gcloud run deploy --image` で Cloud Run 更新
- Terraform では `image` 変数を「特定タグ」ではなく `latest` に設定 or `ignore_changes = [template[0].containers[0].image]` で CD 側の更新を許容
- afterglow の cloudrun.tf を参考にする

---

## 8. Cloud Run のイメージ更新と Terraform の境界

**問題**: `google_cloud_run_v2_service` の `image` を Terraform で管理すると、CD で `gcloud run deploy` するたびに drift が発生する。

**対策**(afterglow の実績パターン):
```hcl
resource "google_cloud_run_v2_service" "api" {
  # ...
  template {
    containers {
      image = var.api_image  # 初期値のみ、以降は無視
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}
```

**運用ルール**:
- Terraform: Cloud Run の**構造**(env vars、SA、CPU、メモリ、min instances 等)を管理
- CI/CD: **イメージタグ**のみを更新
- 両者の境界を明確に分ける

---

## 9. Workload Identity Federation(WIF)

**目的**: GitHub Actions から GCP に `.json` 鍵なしで認証する。

**afterglow の実績**: WIF 経由で認証(SA 鍵をリポジトリに置かない)。同じ方針を採る。

**手動フェーズで設定**:
```bash
# WIF pool 作成
gcloud iam workload-identity-pools create github \
  --project=ohayashi-doujou-prod \
  --location=global

# GitHub 用 provider
gcloud iam workload-identity-pools providers create-oidc github \
  --workload-identity-pool=github \
  --issuer-uri=https://token.actions.githubusercontent.com \
  --attribute-mapping=... \
  --attribute-condition="..."

# SA と紐付け
gcloud iam service-accounts add-iam-policy-binding <deploy-sa> \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/..."
```

**注意**: `attribute-condition` で「特定リポジトリ・特定ブランチのみ許可」を必ず設定。緩いと第三者リポジトリからも悪用できてしまう。

---

## 10. Terraform で管理しないもの一覧

| 対象 | 管理場所 | 理由 |
|---|---|---|
| GCP プロジェクト自体 | 手動 | 組織ポリシーとの絡み |
| 請求アカウント紐付け | 手動 | 組織アカウント側の権限 |
| Terraform state バケット | 手動 | 鶏卵 |
| Terraform 用 SA | 手動 | 鶏卵 |
| Docker イメージ | CI/CD | ライフサイクルが違う(頻繁更新) |
| Secret 値(`.p8` 等) | Secret Manager 手動投入 | Git に載せられない |
| Firestore ドキュメント | アプリ経由 | データプレーン |
| GCS 内の譜面 JSON | アプリ経由 | データプレーン |

---

## 11. Secret 管理の分離

**Terraform**: Secret Manager の**枠**(secret リソース)を管理
```hcl
resource "google_secret_manager_secret" "apple_p8" {
  secret_id = "apple-p8"
  replication { auto {} }
}
```

**手動**: Secret **値**を投入
```bash
gcloud secrets versions add apple-p8 --data-file=./AuthKey_XXXX.p8
```

**Cloud Run から参照**:
```hcl
env {
  name = "APPLE_P8"
  value_source {
    secret_key_ref {
      secret  = google_secret_manager_secret.apple_p8.secret_id
      version = "latest"
    }
  }
}
```

**注意**: `.p8` は 1 度しかダウンロードできない → 発行後即 Secret Manager に投入 → ローカルファイル削除。

---

## 12. state ファイルの保護

**問題**: `terraform.tfstate` にはシークレット(SA email、内部リソース ID 等)が平文で含まれる。

**対策**:
- state を **リモート backend(GCS)** に置く(ローカルに永続保持しない)
- state バケットの IAM は最小権限(Terraform SA のみ read/write)
- state バケットは **Uniform Bucket-Level Access** で個別 ACL を無効化
- Object Versioning で 90 日ロールバック可
- state をローカルに残さないため `.gitignore` に `*.tfstate*` を必ず登録

---

## 13. `.gitignore`

```
# tfstate(ローカルには残さない、GCS が真)
*.tfstate
*.tfstate.*
*.tfstate.backup

# tfvars(環境ごとの機密値)
terraform.tfvars
env-*.tfvars
# example のみ許可
!terraform.tfvars.example

# provider cache
.terraform/
.terraform.tfstate.lock.info

# crash log
crash.log
crash.*.log
```

`.terraform.lock.hcl` は git 管理する(providers バージョン固定のため)。

---

## 14. import 差分ゼロの確認 Runbook

**手順**:
1. `./tf.sh dev init`
2. `./import.sh dev`
3. `./tf.sh dev plan`
4. 差分が出た場合:
   - `google_cloud_run_v2_service.api` に `annotations` の差分 → `lifecycle.ignore_changes` に追加
   - `google_storage_bucket.charts` に `labels` の差分 → tfvars で明示追加
   - どうしても解消できないなら → 該当リソースを import せず、`terraform apply` で作り直す判断
5. 差分ゼロを確認 → import 完了
6. prod 側も同様に実施

**注意**: import は state を書き換える危険操作。実施前に state のバックアップを取る:
```bash
gcloud storage cp gs://ohayashi-doujou-terraform-state/dev/default.tfstate \
  gs://ohayashi-doujou-terraform-state/backup/dev-$(date +%Y%m%d).tfstate
```

---

## 15. dev / prod 差分の吸収パターン

**共通の `.tf`** + **`env-{env}.tfvars` で値のみ切替** が原則。

| 変数 | dev | prod |
|---|---|---|
| project_id | `ohayashi-doujou-dev` | `ohayashi-doujou-prod` |
| charts_bucket | `ohayashi-charts-dev` | `ohayashi-charts-prod` |
| min_instances | 0 | 0(将来 1 に上げる余地) |
| max_instances | 5 | 10 |
| budget_amounts | [200, 500, 1000] | [500, 1000, 3000] |
| alert_email | dev 通知先 | prod 通知先 |

**アンチパターン**: dev/prod で `.tf` ファイル自体を分岐(if 文的な `count = var.environment == "prod" ? 1 : 0`)は最小限に。値レベルの差分で吸収できるように設計。

---

## 16. CI/CD の "少なくとも動く" 順序

Phase 4-5 で CI/CD を組む際の推奨順序:

1. **Phase 4 中**: `terraform-ci.yml`(PR で plan)を最初に組む — plan 自動化がリグレッション防止に最も効く
2. **Phase 4 後**: `api-ci.yml`(PR で lint + test)
3. **Phase 5 前**: `api-dev-cd.yml`(main → dev 自動デプロイ)
4. **Phase 5 中**: `api-prod-cd.yml`(手動承認 → prod デプロイ)
5. **Phase 6**: `ios-ci.yml`(Xcode ビルド)

**理由**: バックエンドは iOS よりリリースサイクルが速く、リグレッションのリスクが高い。iOS の CI は Xcode 手動ビルド + TestFlight でも当初は足りる。

---

## 17. 「Terraform でも触れないもの」を Runbook 化

**シナリオ**: Cloud Run の revision が急激に失敗率上昇 → Terraform apply では遅い → 手動 rollback が必要。

**Runbook 例**:
```bash
# 直前の healthy revision に traffic を戻す
gcloud run services update-traffic api \
  --to-revisions=api-00042-abc=100 \
  --region=asia-northeast1 \
  --project=ohayashi-doujou-prod
```

**方針**: 緊急時は Terraform に頼らず gcloud で対応、後で Terraform state と実状態を突合して整合を取る。

---

## 実装チェックリスト

### 手動フェーズ
- [ ] GCP プロジェクト作成 dev / prod
- [ ] gcloud ADC 設定
- [ ] 必要な GCP API 有効化
- [ ] Firestore Database 作成(dev / prod)
- [ ] Terraform state バケット作成(prod 配下、単一バケット)
- [ ] state バケットの Versioning + Lifecycle 設定
- [ ] Terraform 実行用 SA 作成 + 権限付与
- [ ] Artifact Registry リポジトリ作成
- [ ] Cloud Run 初回デプロイ(ダミーイメージ)
- [ ] WIF pool + provider 作成(GitHub Actions 用)

### Terraform 化フェーズ
- [ ] `terraform/` 配下に `.tf` 全ファイル作成
- [ ] `tf.sh` 配置(afterglow から流用調整)
- [ ] `import.sh` 作成
- [ ] `backend-dev.hcl` / `backend-prod.hcl`
- [ ] `terraform.tfvars` / `env-prod.tfvars`(gitignored)
- [ ] `import.sh` 実行 → `plan` 差分ゼロ確認(dev / prod)
- [ ] README.md 執筆(運用手順)

### CI/CD フェーズ
- [ ] `terraform-ci.yml`(plan on PR)
- [ ] `api-ci.yml`(lint + test on PR)
- [ ] `api-dev-cd.yml`(main → dev)
- [ ] `api-prod-cd.yml`(手動承認 → prod)
- [ ] `ios-ci.yml`(Xcode ビルド)
- [ ] WIF 経由の認証確認(SA 鍵を使わない)

### 継続運用
- [ ] Cloud Run image は `lifecycle.ignore_changes` で CD 側が更新
- [ ] Secret 値は Secret Manager に手動投入
- [ ] state バケット IAM を最小権限に維持
- [ ] 緊急 rollback Runbook を README に併記
