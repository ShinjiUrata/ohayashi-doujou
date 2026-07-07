# =============================================================================
# Firestore Database (Native mode)
# =============================================================================
# 設計: backend.md §3
# - コレクション: charts, transactions (アプリ実装側で作成)
# - 直接アクセスなし (Cloud Run 経由のみ)

# NOTE: Firestore Database は「プロジェクトあたり 1 個」で不可逆のため、
# 初回は Console で作成し、それを terraform import する運用にする。
# import 例:
#   ./tf.sh dev import google_firestore_database.default \
#     projects/ohayashi-doujou-dev/databases/(default)

resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  # 削除防止 (アプリの心臓部)
  deletion_policy                   = "DELETE_PROTECTION_ENABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_DISABLED"

  lifecycle {
    prevent_destroy = true
  }
}
