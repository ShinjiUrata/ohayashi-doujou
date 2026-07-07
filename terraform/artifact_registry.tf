# =============================================================================
# Artifact Registry (Docker イメージ格納)
# =============================================================================
# CI/CD が Cloud Run 用の Docker イメージを push する先。

resource "google_artifact_registry_repository" "api" {
  location      = var.region
  repository_id = local.artifact_repository
  description   = "お囃子道場 API の Docker イメージ格納"
  format        = "DOCKER"
}

# Cloud Run のサービスアカウントに pull 権限
resource "google_artifact_registry_repository_iam_member" "api_cloudrun_reader" {
  location   = google_artifact_registry_repository.api.location
  repository = google_artifact_registry_repository.api.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.cloudrun.email}"
}
