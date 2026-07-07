# =============================================================================
# Secret Manager: Apple App Store Server API 用の .p8 秘密鍵
# =============================================================================
# 設計: security.md §9、terraform_and_deployment.md §11
# - Terraform は「枠」だけ管理、シークレットの値は手動投入
# - Cloud Run が secretAccessor 権限で参照する

resource "google_secret_manager_secret" "apple_p8" {
  secret_id = "apple-p8"

  labels = {
    purpose     = "app-store-server-api"
    environment = var.environment
  }

  replication {
    auto {}
  }
}

# NOTE: 値の投入は Phase 5 で以下のコマンドを実行して手動で行う:
#   gcloud secrets versions add apple-p8 --data-file=./AuthKey_XXXX.p8
# .p8 ファイルは 1 度しかダウンロードできないため厳重管理。
# Cloud Run は env の value_source.secret_key_ref で最新版を参照する
# (Phase 5 で cloudrun.tf に追加)。
