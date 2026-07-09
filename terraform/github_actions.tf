# =============================================================================
# Workload Identity Federation (GitHub Actions 用)
# =============================================================================
# 設計方針:
#  - GitHub Actions は SA 鍵ファイルを持たず、WIF で短命トークンを発行して認証
#  - リポジトリ (github_repository) からのみ許可する attribute_condition 付き
#  - Terraform CI 用は terraform SA を、api CD 用は cloudrun-charts SA を
#    それぞれ impersonate する
#
# 参考: terraform_and_deployment.md §9

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "GitHub Actions が WIF 経由で認証するためのプール"
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions"
  description                        = "GitHub Actions OIDC トークンの検証"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # 指定リポジトリからのみ認証を許可(必須のセキュリティ制約)
  attribute_condition = "assertion.repository == \"${var.github_repository}\""
}

# =============================================================================
# GitHub Actions が impersonate する SA
# =============================================================================

resource "google_service_account" "github_actions" {
  account_id   = "github-actions"
  display_name = "GitHub Actions deployer"
  description  = "GitHub Actions が CI/CD 実行時に使う SA。WIF で impersonate される。"
}

# WIF プリンシパルセットに SA impersonation 権限を付与
resource "google_service_account_iam_member" "github_actions_wif_binding" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/github/attribute.repository/${var.github_repository}"
}

# =============================================================================
# github-actions SA の権限
# =============================================================================

# Docker イメージを Artifact Registry に push
resource "google_project_iam_member" "github_actions_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Cloud Run のリビジョンを更新
resource "google_project_iam_member" "github_actions_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Cloud Run サービスに cloudrun-charts SA を紐付けるため
resource "google_service_account_iam_member" "github_actions_use_cloudrun_sa" {
  service_account_id = google_service_account.cloudrun.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_actions.email}"
}

# Terraform CI 用: terraform SA を impersonate 可能にする
resource "google_service_account_iam_member" "github_actions_impersonate_terraform" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/terraform@${var.project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.github_actions.email}"
}

# =============================================================================
# 出力(GitHub Actions ワークフローで参照する値)
# =============================================================================

output "github_wif_provider" {
  description = "GitHub Actions ワークフローの workload_identity_provider に指定する値"
  value       = "projects/${var.project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github_actions.workload_identity_pool_provider_id}"
}

output "github_service_account" {
  description = "GitHub Actions が impersonate する SA のメールアドレス"
  value       = google_service_account.github_actions.email
}
