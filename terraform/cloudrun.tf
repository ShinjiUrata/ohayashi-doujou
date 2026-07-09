# =============================================================================
# Cloud Run: api サービス
# =============================================================================
# 設計: backend.md §4-9、terraform_and_deployment.md §8
# - image は CI/CD 側で更新するため lifecycle.ignore_changes する
# - 未認証呼び出しを許可 (アプリからの匿名 POST)
# - 独自ドメイン不採用、Cloud Run 発行のデフォルト URL を iOS にハードコード

resource "google_cloud_run_v2_service" "api" {
  name     = local.cloudrun_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloudrun.email

    scaling {
      min_instance_count = var.cloudrun_min_instances
      max_instance_count = var.cloudrun_max_instances
    }

    containers {
      # プレースホルダ image。CI/CD が最新タグを --set-image で更新するため、
      # このフィールドは Terraform では追跡しない (ignore_changes)。
      image = "asia-northeast1-docker.pkg.dev/${var.project_id}/${local.artifact_repository}/api:bootstrap"

      resources {
        limits = {
          cpu    = var.cloudrun_cpu
          memory = var.cloudrun_memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "CHARTS_BUCKET"
        value = local.charts_bucket_name
      }
      env {
        name  = "APPLE_BUNDLE_ID"
        value = local.apple_bundle_id
      }
      env {
        name  = "APPLE_PRODUCT_ID"
        value = "rhythm.chart.publish.single"
      }
    }

    timeout = "60s"
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [
      # image は CI/CD が更新するので Terraform では追跡しない
      template[0].containers[0].image,
      # Cloud Run が自動で付ける annotation / label 群も無視
      client,
      client_version,
    ]
  }
}

# 未認証呼び出しを許可 (アプリからの匿名 POST を受け付ける)
resource "google_cloud_run_v2_service_iam_member" "api_public" {
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# 出力
# =============================================================================
# iOS 側の xcconfig にハードコードする URL

output "api_url" {
  description = "Cloud Run API サービスの URL (iOS の xcconfig に設定する)"
  value       = google_cloud_run_v2_service.api.uri
}

output "charts_bucket_public_url_prefix" {
  description = "譜面 JSON の公開 URL の prefix (iOS の xcconfig に設定する)"
  value       = "https://storage.googleapis.com/${google_storage_bucket.charts.name}"
}
