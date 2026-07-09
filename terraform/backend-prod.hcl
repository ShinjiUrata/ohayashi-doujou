# Terraform Backend Configuration (prod)
# 使用方法: terraform init -reconfigure -backend-config=backend-prod.hcl
#
# 通常は tf.sh 経由で自動的に指定される。

bucket = "ohayashi-doujou-terraform-state"
prefix = "prod"
