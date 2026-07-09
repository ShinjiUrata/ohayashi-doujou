# Terraform Backend Configuration (dev)
# 使用方法: terraform init -reconfigure -backend-config=backend-dev.hcl
#
# 通常は tf.sh 経由で自動的に指定される。

bucket = "ohayashi-doujou-terraform-state"
prefix = "dev"
