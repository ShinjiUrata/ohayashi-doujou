# 環境ごとに異なる値を定義。
# 実際の値は terraform.tfvars (dev) / env-prod.tfvars (prod) に記載
# (どちらも gitignored)。

variable "project_id" {
  description = "GCP プロジェクト ID (例: ohayashi-doujou-dev / ohayashi-doujou-prod)"
  type        = string
}

variable "project_number" {
  description = "GCP プロジェクト番号"
  type        = string
}

variable "region" {
  description = "GCP リージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "environment" {
  description = "環境名 (dev / prod) — リソース名のサフィックスに使用"
  type        = string
}

variable "alert_email" {
  description = "アラート通知先メールアドレス"
  type        = string
}

variable "github_repository" {
  description = "GitHub Actions Workload Identity Federation で許可するリポジトリ (owner/name)"
  type        = string
  default     = "ShinjiUrata/ohayashi-doujou"
}

# =============================================================================
# Cloud Run チューニング (dev/prod で値を切替)
# =============================================================================

variable "cloudrun_min_instances" {
  description = "Cloud Run の最小インスタンス数 (0 なら cold start 許容)"
  type        = number
  default     = 0
}

variable "cloudrun_max_instances" {
  description = "Cloud Run の最大インスタンス数 (大量アクセス時の上限)"
  type        = number
  default     = 5
}

variable "cloudrun_cpu" {
  description = "Cloud Run の vCPU"
  type        = string
  default     = "1"
}

variable "cloudrun_memory" {
  description = "Cloud Run のメモリ"
  type        = string
  default     = "512Mi"
}

# =============================================================================
# コスト保護アラート閾値 (dev/prod で値を切替)
# `dev_documents/implementation_notes/cost_protection.md` §2A 参照
# =============================================================================

variable "budget_amounts_yen" {
  description = "予算アラートの 3 段階 (円)。Warning / Alert / Critical の順"
  type        = list(number)
  default     = [500, 1000, 3000]
}

variable "gcs_request_warning_per_hour" {
  description = "1 時間あたり GCS リクエスト数の Warning 閾値"
  type        = number
  default     = 1000
}

variable "gcs_request_critical_per_hour" {
  description = "1 時間あたり GCS リクエスト数の Critical 閾値"
  type        = number
  default     = 10000
}

variable "log_bytes_daily_warning" {
  description = "日次ログ量の Warning 閾値 (bytes)"
  type        = number
  default     = 1073741824 # 1 GB
}

variable "log_bytes_monthly_critical" {
  description = "月次ログ量の Critical 閾値 (bytes)"
  type        = number
  default     = 21474836480 # 20 GB
}
