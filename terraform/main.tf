# お囃子道場 GCP Infrastructure
#
# 手動セットアップ済みリソースを import.sh で取り込む形で運用する。
# afterglow プロジェクトのフラット構成を踏襲。
# 詳細: dev_documents/implementation_notes/terraform_and_deployment.md

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # backend 設定は backend-{env}.hcl で切り替える。
  # 例: terraform init -reconfigure -backend-config=backend-dev.hcl
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --- 共通ローカル変数 ---

locals {
  # リソース名(環境サフィックス付き)
  charts_bucket_name    = "ohayashi-charts-${var.environment}"
  artifact_repository   = "api"
  cloudrun_service_name = "api"

  # サービスアカウント
  cloudrun_service_account = "cloudrun-charts@${var.project_id}.iam.gserviceaccount.com"

  # iOS ビルドの Bundle ID と揃える(dev は .dev サフィックス付き)。
  # ここが JWS 検証時の bundleId チェックの正解値になる。
  apple_bundle_id = var.environment == "prod" ? "com.zembrem.ohayashidoujou" : "com.zembrem.ohayashidoujou.dev"
}
