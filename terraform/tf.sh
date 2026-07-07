#!/usr/bin/env bash
# Terraform 環境切替ラッパー
#
# 使用例:
#   ./tf.sh dev plan
#   ./tf.sh dev apply
#   ./tf.sh prod plan
#   ./tf.sh prod apply
#
# 動作:
#   1. 指定された環境のバックエンドに init -reconfigure で切替
#   2. 指定された環境の .tfvars を -var-file で渡して terraform コマンド実行
#
# 設計理由:
#   ハードコードされたバックエンド/変数を間違える事故 (dev に prod を apply する等)
#   を防ぐため、必ず env を明示的に指定する形にしている。

set -euo pipefail

ENV="${1:-}"
shift || true
CMD="${1:-plan}"
shift || true
EXTRA_ARGS=("$@")

if [[ "${ENV}" != "dev" && "${ENV}" != "prod" ]]; then
  echo "❌ 第 1 引数は dev または prod を指定してください"
  echo ""
  echo "使用例:"
  echo "  $0 dev plan"
  echo "  $0 dev apply"
  echo "  $0 prod plan"
  echo "  $0 prod apply"
  exit 1
fi

BACKEND_CONFIG="backend-${ENV}.hcl"
VAR_FILE="env-${ENV}.tfvars"

# dev のみ既存の terraform.tfvars を使う (後方互換)
if [[ "${ENV}" == "dev" && -f "terraform.tfvars" ]]; then
  VAR_FILE="terraform.tfvars"
fi

if [[ ! -f "${BACKEND_CONFIG}" ]]; then
  echo "❌ バックエンド設定ファイルが見つかりません: ${BACKEND_CONFIG}"
  exit 1
fi
if [[ ! -f "${VAR_FILE}" ]]; then
  echo "❌ 変数ファイルが見つかりません: ${VAR_FILE}"
  echo "   terraform.tfvars.example をコピーして値を埋めてください"
  exit 1
fi

# prod の場合は強調表示で警告
if [[ "${ENV}" == "prod" ]]; then
  echo ""
  echo "============================================================"
  echo "⚠️  PROD 環境への操作です"
  echo "    プロジェクト: ohayashi-doujou-prod"
  echo "    バックエンド: gs://ohayashi-doujou-terraform-state/prod/"
  echo "============================================================"
  echo ""
fi

echo "→ Backend 切替: ${BACKEND_CONFIG}"
terraform init -reconfigure -backend-config="${BACKEND_CONFIG}" >/dev/null

# 変数ファイルを受け付けるコマンドのみ -var-file を渡す。
# force-unlock / state / output / workspace 等は -var-file 非対応。
case "${CMD}" in
  plan|apply|destroy|refresh|validate|console|import|taint|untaint)
    VAR_FILE_ARGS=(-var-file="${VAR_FILE}")
    ;;
  *)
    VAR_FILE_ARGS=()
    ;;
esac

echo "→ 実行: terraform ${CMD} ${VAR_FILE_ARGS[*]:-} ${EXTRA_ARGS[*]:-}"
if [[ ${#EXTRA_ARGS[@]} -eq 0 && ${#VAR_FILE_ARGS[@]} -eq 0 ]]; then
  terraform "${CMD}"
elif [[ ${#EXTRA_ARGS[@]} -eq 0 ]]; then
  terraform "${CMD}" "${VAR_FILE_ARGS[@]}"
elif [[ ${#VAR_FILE_ARGS[@]} -eq 0 ]]; then
  terraform "${CMD}" "${EXTRA_ARGS[@]}"
else
  terraform "${CMD}" "${VAR_FILE_ARGS[@]}" "${EXTRA_ARGS[@]}"
fi
