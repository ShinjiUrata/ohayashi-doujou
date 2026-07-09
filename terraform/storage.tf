# =============================================================================
# 譜面配信用の公開 GCS バケット
# =============================================================================
# 設計方針: cost_protection.md §2、backend.md §2
# - allUsers に Storage Object Viewer のみ (ListObjects は付与しない)
# - Object Versioning 有効 (誤削除の保険)
# - iOS 側は直接 GCS URL を叩く (独自ドメインなし、Load Balancer なし)

resource "google_storage_bucket" "charts" {
  name          = local.charts_bucket_name
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age                = 30
      with_state         = "ARCHIVED"
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }
}

# allUsers にオブジェクト読み取り権限のみ付与 (ListObjects は付与しない)
resource "google_storage_bucket_iam_member" "charts_public_read" {
  bucket = google_storage_bucket.charts.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Cloud Run のサービスアカウントに書き込み権限
resource "google_storage_bucket_iam_member" "charts_cloudrun_writer" {
  bucket = google_storage_bucket.charts.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloudrun.email}"
}
