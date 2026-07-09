#!/usr/bin/env bash
# 手動作成済み GCP リソースを Terraform state に取り込むスクリプト
#
# 使用例:
#   ./import.sh dev
#   ./import.sh prod
#
# 前提:
#   - bootstrap 手順 (dev_documents/implementation_notes/phase4_bootstrap.md) を実施済み
#   - terraform.tfvars (dev) / env-prod.tfvars (prod) 設定済み
#
# 実施後:
#   ./tf.sh <env> plan を実行して差分ゼロを確認する

set -euo pipefail

ENV="${1:-}"
if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "❌ 第 1 引数は dev または prod を指定してください"
  echo "使用例: $0 dev"
  exit 1
fi

PROJECT_ID="ohayashi-doujou-${ENV}"
REGION="asia-northeast1"

echo "==> ${ENV} 環境のリソースを import します"
echo "    プロジェクト: ${PROJECT_ID}"
echo ""

# 事前準備: backend 切替
./tf.sh "${ENV}" init >/dev/null 2>&1 || true

VAR_FILE="env-${ENV}.tfvars"
if [[ "${ENV}" == "dev" && -f "terraform.tfvars" ]]; then
  VAR_FILE="terraform.tfvars"
fi
IMPORT_OPTS=(-var-file="${VAR_FILE}")

run_import() {
  local address="$1"
  local resource_id="$2"
  echo ""
  echo "→ import ${address}"
  echo "    resource: ${resource_id}"
  if terraform state show "${address}" >/dev/null 2>&1; then
    echo "    (既に state 済みのためスキップ)"
    return
  fi
  terraform import "${IMPORT_OPTS[@]}" "${address}" "${resource_id}" || {
    echo "    ⚠️  import 失敗。手動作成が済んでいるか確認してください"
    return
  }
}

# --- Firestore ---
run_import \
  "google_firestore_database.default" \
  "projects/${PROJECT_ID}/databases/(default)"

# --- Cloud Storage ---
run_import \
  "google_storage_bucket.charts" \
  "ohayashi-charts-${ENV}"

# --- Artifact Registry ---
run_import \
  "google_artifact_registry_repository.api" \
  "projects/${PROJECT_ID}/locations/${REGION}/repositories/api"

# --- Cloud Run ---
run_import \
  "google_cloud_run_v2_service.api" \
  "projects/${PROJECT_ID}/locations/${REGION}/services/api"

# --- Service Account ---
run_import \
  "google_service_account.cloudrun" \
  "projects/${PROJECT_ID}/serviceAccounts/cloudrun-charts@${PROJECT_ID}.iam.gserviceaccount.com"

# --- Secret Manager ---
run_import \
  "google_secret_manager_secret.apple_p8" \
  "projects/${PROJECT_ID}/secrets/apple-p8"

echo ""
echo "==> import 完了。次のコマンドで差分ゼロを確認してください:"
echo "    ./tf.sh ${ENV} plan"
