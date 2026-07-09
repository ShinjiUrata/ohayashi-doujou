# =============================================================================
# 通知チャネルとアラートポリシー
# =============================================================================
# 設計: cost_protection.md §1D + §2A/B
# - メール通知
# - 予算アラート 3 段階
# - GCS リクエスト頻度アラート
# - ログ量アラート

resource "google_monitoring_notification_channel" "email" {
  display_name = "お囃子道場 コスト / 障害通知メール (${var.environment})"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

# =============================================================================
# 予算アラート 3 段階
# =============================================================================
# NOTE: 予算アラートは billing account に紐づくので、
# billing_account 変数を追加するか、Console で手動設定する。
# ここではメール通知チャネルだけ Terraform で持つ設計にとどめ、
# 予算そのものは README.md の bootstrap 手順で Console から設定する。

# =============================================================================
# ログ量: 日次 1 GB Warning
# =============================================================================

resource "google_monitoring_alert_policy" "log_volume_warning" {
  display_name = "[Warning] ログ量 (日次) — cost_protection §1D"
  combiner     = "OR"

  conditions {
    display_name = "日次ログ量が Warning 閾値を超過"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/billing/bytes_ingested\" resource.type=\"global\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.log_bytes_daily_warning
      aggregations {
        alignment_period     = "3600s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  documentation {
    content = "cost_protection.md §1D を参照。ログ増加の原因を特定し、必要なら Log Router の除外フィルタを追加。"
  }
}

# =============================================================================
# GCS リクエスト頻度: 1 時間 1K Warning
# =============================================================================

resource "google_monitoring_alert_policy" "gcs_request_warning" {
  display_name = "[Warning] GCS リクエスト頻度 — cost_protection §2B"
  combiner     = "OR"

  conditions {
    display_name = "charts バケットへのリクエストが 1 時間で ${var.gcs_request_warning_per_hour} を超過"
    condition_threshold {
      filter          = "metric.type=\"storage.googleapis.com/api/request_count\" resource.type=\"gcs_bucket\" resource.label.bucket_name=\"${local.charts_bucket_name}\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.gcs_request_warning_per_hour
      aggregations {
        alignment_period     = "3600s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  documentation {
    content = "cost_protection.md §2B / §2D の Runbook を参照。異常なら allUsers 権限を一時撤去。"
  }
}

# =============================================================================
# GCS リクエスト頻度: 1 時間 10K Critical (即対応)
# =============================================================================

resource "google_monitoring_alert_policy" "gcs_request_critical" {
  display_name = "[Critical] GCS リクエスト頻度 — 即バケット公開停止判断"
  combiner     = "OR"

  conditions {
    display_name = "charts バケットへのリクエストが 1 時間で ${var.gcs_request_critical_per_hour} を超過"
    condition_threshold {
      filter          = "metric.type=\"storage.googleapis.com/api/request_count\" resource.type=\"gcs_bucket\" resource.label.bucket_name=\"${local.charts_bucket_name}\""
      duration        = "0s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.gcs_request_critical_per_hour
      aggregations {
        alignment_period     = "3600s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  documentation {
    content = "cost_protection.md §2D の Runbook を実行。gsutil iam ch -d allUsers:objectViewer で公開を止める。"
  }
}
