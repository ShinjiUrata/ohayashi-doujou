# =============================================================================
# サービスアカウントと権限
# =============================================================================
# 設計: backend.md §8、security.md §6
# - Cloud Run 用 SA を分離、最小権限
# - デフォルトの compute SA には権限を追加しない

resource "google_service_account" "cloudrun" {
  account_id   = "cloudrun-charts"
  display_name = "Cloud Run API service account"
  description  = "お囃子道場 API (Cloud Run) が使うサービスアカウント。Firestore と charts バケットへのアクセス権を持つ。"
}

# Firestore へのアクセス
resource "google_project_iam_member" "cloudrun_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloudrun.email}"
}

# ログ書き込み
resource "google_project_iam_member" "cloudrun_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudrun.email}"
}

# Cloud Trace (パフォーマンス調査用、無料枠内)
resource "google_project_iam_member" "cloudrun_trace" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.cloudrun.email}"
}

# Secret Manager からシークレットを読む権限 (Apple .p8 用、Phase 5 で有効化)
resource "google_project_iam_member" "cloudrun_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloudrun.email}"
}
