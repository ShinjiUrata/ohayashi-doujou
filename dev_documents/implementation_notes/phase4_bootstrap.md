# Phase 4: GCP セットアップ Bootstrap 手順

**位置付け**: Phase 4-A の手動セットアップ手順。ここが完了したら Terraform で残りを管理する。

**関連**:
- Terraform 全体方針: `terraform_and_deployment.md` §3(手動 → Terraform 化の境界)
- コスト保護: `cost_protection.md`
- セキュリティ: `security.md`

---

## 前提

- Apple Developer Program の Team ID `W6W4Y5HLYB`(afterglow と同じ)を持っている
- GCP 課金アカウントが利用可能
- `gcloud` / `terraform` / `docker` をインストール済み
- afterglow の Terraform 運用実績あり(似た手順)

---

## 進行チェックリスト

順に潰していく。各ステップの実行済みチェックボックスを打ちながら進める。

### 前準備

- [ ] `gcloud version` で 500+ のバージョン確認、必要なら update
- [ ] `terraform -version` で 1.5.0+ を確認
- [ ] `docker --version` で 24+ を確認
- [ ] `gcloud auth login`(初回のみ)
- [ ] `gcloud auth application-default login`(Terraform 用)

### ステップ 1: GCP プロジェクト作成

Console(<https://console.cloud.google.com/projectcreate>)から dev と prod を作る:

- [ ] プロジェクト `ohayashi-doujou-dev` を作成
- [ ] プロジェクト `ohayashi-doujou-prod` を作成
- [ ] 両方に課金アカウントを紐付ける

プロジェクト番号(Terraform で必要)を控える:
```bash
gcloud projects describe ohayashi-doujou-dev --format='value(projectNumber)'
gcloud projects describe ohayashi-doujou-prod --format='value(projectNumber)'
```

- [ ] dev の project number: __________________
- [ ] prod の project number: __________________

### ステップ 2: 必要な API を有効化

**両方のプロジェクトで実施**:

```bash
for PROJECT in ohayashi-doujou-dev ohayashi-doujou-prod; do
  gcloud services enable \
    run.googleapis.com \
    storage.googleapis.com \
    firestore.googleapis.com \
    logging.googleapis.com \
    monitoring.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    iam.googleapis.com \
    iamcredentials.googleapis.com \
    secretmanager.googleapis.com \
    cloudresourcemanager.googleapis.com \
    --project=$PROJECT
done
```

- [ ] dev で API 有効化完了
- [ ] prod で API 有効化完了

### ステップ 3: Firestore Database 作成

`(default)` データベースはプロジェクトあたり 1 個で不可逆のため、Console で作成が最も安全:

Console → Firestore → Create database → **Native mode** → Location: `asia-northeast1`

- [ ] dev の Firestore を作成
- [ ] prod の Firestore を作成

または CLI で:
```bash
for PROJECT in ohayashi-doujou-dev ohayashi-doujou-prod; do
  gcloud firestore databases create \
    --location=asia-northeast1 \
    --type=firestore-native \
    --project=$PROJECT
done
```

### ステップ 4: Terraform state バケット作成(単一、prod プロジェクト配下)

**方針**: `terraform_and_deployment.md` §6 参照。単一バケット + prefix 分けで運用。

```bash
gcloud storage buckets create gs://ohayashi-doujou-terraform-state \
  --project=ohayashi-doujou-prod \
  --location=asia-northeast1 \
  --uniform-bucket-level-access \
  --public-access-prevention=enforced

gcloud storage buckets update gs://ohayashi-doujou-terraform-state \
  --versioning

# ライフサイクル(古いバージョンは 90 日で削除)
cat > /tmp/lifecycle.json <<'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 90,
          "isLive": false
        }
      }
    ]
  }
}
EOF

gcloud storage buckets update gs://ohayashi-doujou-terraform-state \
  --lifecycle-file=/tmp/lifecycle.json
```

- [ ] state バケット作成完了
- [ ] Versioning 有効化完了
- [ ] Lifecycle 設定完了

### ステップ 5: Terraform 実行用サービスアカウント

**両方のプロジェクトで実施**:

```bash
for PROJECT in ohayashi-doujou-dev ohayashi-doujou-prod; do
  gcloud iam service-accounts create terraform \
    --display-name="Terraform executor" \
    --project=$PROJECT

  # 各プロジェクトで必要な最小権限
  for ROLE in \
    roles/run.admin \
    roles/storage.admin \
    roles/datastore.owner \
    roles/artifactregistry.admin \
    roles/iam.serviceAccountAdmin \
    roles/iam.serviceAccountUser \
    roles/serviceusage.serviceUsageAdmin \
    roles/logging.admin \
    roles/monitoring.editor \
    roles/secretmanager.admin \
    roles/resourcemanager.projectIamAdmin; do
    gcloud projects add-iam-policy-binding $PROJECT \
      --member="serviceAccount:terraform@${PROJECT}.iam.gserviceaccount.com" \
      --role=$ROLE >/dev/null
  done
done

# state バケットに対しても Terraform SA に権限付与
for PROJECT in ohayashi-doujou-dev ohayashi-doujou-prod; do
  gcloud storage buckets add-iam-policy-binding gs://ohayashi-doujou-terraform-state \
    --member="serviceAccount:terraform@${PROJECT}.iam.gserviceaccount.com" \
    --role=roles/storage.objectAdmin
done
```

- [ ] dev の Terraform SA 作成 + 権限付与
- [ ] prod の Terraform SA 作成 + 権限付与

**認証方法**: MVP は Application Default Credentials(ADC)経由で `gcloud auth application-default login` した Google アカウントの権限で Terraform を実行する。CI 化する Phase 4 後半で WIF に切り替える。

### ステップ 6: Artifact Registry リポジトリ作成

`terraform/artifact_registry.tf` で管理されるが、Cloud Run 初回デプロイ時にリポジトリが必要なので先に手動作成:

```bash
for PROJECT in ohayashi-doujou-dev ohayashi-doujou-prod; do
  gcloud artifacts repositories create api \
    --repository-format=docker \
    --location=asia-northeast1 \
    --description="お囃子道場 API の Docker イメージ格納" \
    --project=$PROJECT
done
```

- [ ] dev で Artifact Registry 作成
- [ ] prod で Artifact Registry 作成

### ステップ 7: Cloud Run 用サービスアカウント作成

```bash
for PROJECT in ohayashi-doujou-dev ohayashi-doujou-prod; do
  gcloud iam service-accounts create cloudrun-charts \
    --display-name="Cloud Run API service account" \
    --project=$PROJECT
done
```

- [ ] 両プロジェクトで cloudrun-charts SA 作成

権限は Terraform 側(`terraform/iam.tf`)で付与するので、ここでは SA の枠だけ用意する。

### ステップ 8: Charts バケットの作成

Cloud Run 初回デプロイ前に必要。

```bash
for ENV in dev prod; do
  PROJECT="ohayashi-doujou-${ENV}"
  gcloud storage buckets create gs://ohayashi-charts-${ENV} \
    --project=$PROJECT \
    --location=asia-northeast1 \
    --uniform-bucket-level-access

  # 公開設定(allUsers に Object Viewer だけ)
  gcloud storage buckets add-iam-policy-binding gs://ohayashi-charts-${ENV} \
    --member=allUsers \
    --role=roles/storage.objectViewer

  # Versioning 有効
  gcloud storage buckets update gs://ohayashi-charts-${ENV} --versioning
done
```

- [ ] dev で charts バケット作成
- [ ] prod で charts バケット作成

### ステップ 9: Secret Manager の枠を作成

```bash
for PROJECT in ohayashi-doujou-dev ohayashi-doujou-prod; do
  gcloud secrets create apple-p8 \
    --replication-policy=automatic \
    --project=$PROJECT
done
```

- [ ] 両プロジェクトで apple-p8 の secret 枠を作成

**注意**: 値の投入は Phase 5 で `.p8` を発行してから実施。

### ステップ 10: Cloud Run 初回デプロイ(hello-world)

Terraform で import する前に、Cloud Run サービスが存在している必要がある。ダミーイメージで初回デプロイ:

```bash
for ENV in dev prod; do
  PROJECT="ohayashi-doujou-${ENV}"

  # Docker イメージを build & push(バックエンドコード付き)
  cd backend
  gcloud builds submit \
    --tag asia-northeast1-docker.pkg.dev/${PROJECT}/api/api:bootstrap \
    --project=$PROJECT

  # Cloud Run にデプロイ
  gcloud run deploy api \
    --image asia-northeast1-docker.pkg.dev/${PROJECT}/api/api:bootstrap \
    --region asia-northeast1 \
    --project=$PROJECT \
    --service-account cloudrun-charts@${PROJECT}.iam.gserviceaccount.com \
    --set-env-vars="PROJECT_ID=${PROJECT},ENVIRONMENT=${ENV},CHARTS_BUCKET=ohayashi-charts-${ENV},APPLE_BUNDLE_ID=com.zembrem.ohayashidoujou,APPLE_PRODUCT_ID=rhythm.chart.publish.single" \
    --allow-unauthenticated \
    --min-instances=0 \
    --max-instances=5
  cd ..
done
```

- [ ] dev で Cloud Run 初回デプロイ完了
- [ ] prod で Cloud Run 初回デプロイ完了

デプロイ後の URL を控える(iOS の xcconfig に反映):
```bash
gcloud run services describe api --region=asia-northeast1 --project=ohayashi-doujou-dev --format='value(status.url)'
gcloud run services describe api --region=asia-northeast1 --project=ohayashi-doujou-prod --format='value(status.url)'
```

### ステップ 11: 予算アラート(3 段階、Console で手動)

Console → Billing → Budgets & alerts → CREATE BUDGET

**dev 用**:
- Name: `ohayashi-doujou-dev budget`
- Projects: `ohayashi-doujou-dev`
- Amount: ¥1,000
- Thresholds: 50% Warning / 100% Alert / 300% Critical
- Notification: `urata.1321@gmail.com`

**prod 用**:
- Name: `ohayashi-doujou-prod budget`
- Projects: `ohayashi-doujou-prod`
- Amount: ¥3,000
- Thresholds: 17% (≈¥500) / 33% (≈¥1,000) / 100% (≈¥3,000)

- [ ] dev の予算アラート設定完了
- [ ] prod の予算アラート設定完了

### ステップ 12: Terraform 変数ファイル作成

`terraform/` ディレクトリで作業:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
cp terraform.tfvars.example env-prod.tfvars
```

**`terraform.tfvars`** (dev) を編集:
```hcl
project_id     = "ohayashi-doujou-dev"
project_number = "<ステップ 1 で控えた dev の番号>"
region         = "asia-northeast1"
environment    = "dev"
alert_email    = "urata.1321@gmail.com"
```

**`env-prod.tfvars`** (prod) を編集:
```hcl
project_id     = "ohayashi-doujou-prod"
project_number = "<ステップ 1 で控えた prod の番号>"
region         = "asia-northeast1"
environment    = "prod"
alert_email    = "urata.1321@gmail.com"
cloudrun_max_instances = 10
budget_amounts_yen     = [500, 1000, 3000]
```

- [ ] dev tfvars 作成完了
- [ ] prod tfvars 作成完了

### ステップ 13: Terraform init + import

```bash
cd terraform

# dev
./tf.sh dev init   # backend-dev.hcl で init
./import.sh dev    # 手動作成済みリソースを取り込み
./tf.sh dev plan   # 差分ゼロを確認

# prod
./tf.sh prod init
./import.sh prod
./tf.sh prod plan
```

**差分が出た場合**: `.tf` の記述を実状態に合わせるか、逆に `terraform apply` で理想状態に寄せる。取り扱い注意で、apply する前に必ず内容を確認。

- [ ] dev で差分ゼロ確認
- [ ] prod で差分ゼロ確認

### ステップ 14: iOS 側の xcconfig 反映

```
ios/Config/Debug.xcconfig
  API_BASE_URL = <dev Cloud Run URL>
  CHARTS_BASE_URL = https:/$()/storage.googleapis.com/ohayashi-charts-dev

ios/Config/Release.xcconfig
  API_BASE_URL = <prod Cloud Run URL>
  CHARTS_BASE_URL = https:/$()/storage.googleapis.com/ohayashi-charts-prod
```

- [ ] Debug.xcconfig 更新
- [ ] Release.xcconfig 更新

これで Phase 4-A(GCP 手動セットアップ + Terraform 化)が完了。次は Phase 4-C(iOS 通信層 + 譜面検索/DL 画面)。

---

## トラブルシューティング

### Firestore の import で `(default)` が解決できない
Bash のシェルによっては `()` がエスケープ問題を起こす。以下のようにクォートすると通る:
```bash
terraform import "google_firestore_database.default" 'projects/ohayashi-doujou-dev/databases/(default)'
```

### Cloud Run 初回デプロイで permission denied
`cloudrun-charts` SA が SA を「使う」権限が必要。以下を実施:
```bash
gcloud iam service-accounts add-iam-policy-binding \
  cloudrun-charts@ohayashi-doujou-dev.iam.gserviceaccount.com \
  --member="user:<あなたのアカウント>@gmail.com" \
  --role=roles/iam.serviceAccountUser \
  --project=ohayashi-doujou-dev
```

### Terraform plan で `google_firestore_database` の差分が消えない
Firestore の細かい設定は import で完全に反映されない場合がある。以下のいずれか:
- `.tf` の値を実状態に合わせる
- `lifecycle { ignore_changes = [...] }` を追加

### Cloud Run の image が Terraform で戻される
`cloudrun.tf` で `lifecycle.ignore_changes = [template[0].containers[0].image]` を設定済み。もし戻される場合は Terraform のバージョンによる差異なので、addressing を確認。

---

## 実装チェックリスト(全体)

- [ ] ステップ 1: GCP プロジェクト作成
- [ ] ステップ 2: API 有効化
- [ ] ステップ 3: Firestore Database 作成
- [ ] ステップ 4: Terraform state バケット作成
- [ ] ステップ 5: Terraform SA 作成
- [ ] ステップ 6: Artifact Registry 作成
- [ ] ステップ 7: Cloud Run SA 作成
- [ ] ステップ 8: Charts バケット作成
- [ ] ステップ 9: Secret Manager 枠作成
- [ ] ステップ 10: Cloud Run 初回デプロイ
- [ ] ステップ 11: 予算アラート設定
- [ ] ステップ 12: Terraform tfvars 作成
- [ ] ステップ 13: Terraform init + import + plan(差分ゼロ)
- [ ] ステップ 14: iOS xcconfig 反映
