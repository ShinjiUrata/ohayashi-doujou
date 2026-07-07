# =============================================================================
# Cloud Logging のコスト保護
# =============================================================================
# 設計: cost_protection.md §1
# - HTTP 200 + severity < ERROR を _Default sink から除外
# - _Default バケットの保持期間を 14 日に短縮

# Log Router の除外設定
resource "google_logging_project_sink" "default_exclude_noise" {
  name        = "_Default"
  description = "Cloud Run の HTTP 200 (severity < ERROR) を除外して無料枠を守る"
  destination = "logging.googleapis.com/projects/${var.project_id}/locations/global/buckets/_Default"

  # _Default sink は Google が project-owned な writer SA を持つ形で作るため true
  unique_writer_identity = true

  exclusions {
    name        = "http200-noise"
    description = "cost_protection.md §1A で規定"
    filter      = "resource.type=\"cloud_run_revision\" AND httpRequest.status=200 AND severity<\"ERROR\""
  }
}

# _Default バケットの保持期間を短縮
resource "google_logging_project_bucket_config" "default_bucket_retention" {
  project        = var.project_id
  location       = "global"
  retention_days = 14
  bucket_id      = "_Default"
}
