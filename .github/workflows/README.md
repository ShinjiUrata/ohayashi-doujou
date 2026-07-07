# GitHub Actions ワークフロー運用ガイド

`terraform_and_deployment.md` §7 の設計に沿った 5 ワークフロー構成。afterglow の `{service}-ci` / `{service}-{env}-cd` パターンを踏襲。

## ワークフロー一覧

| ファイル | トリガ | 内容 |
|---|---|---|
| `api-ci.yml` | PR / push(main, dev) | TS lint + Vitest + Docker build 検証 |
| `api-dev-cd.yml` | push to `dev` ブランチ | Cloud Run dev へデプロイ + smoke |
| `api-prod-cd.yml` | push to `main` ブランチ | production environment 承認 → Cloud Run prod へデプロイ + smoke |
| `terraform-ci.yml` | PR(`terraform/**`) | dev/prod 両方の `plan` を実行、結果を PR コメント |
| `ios-ci.yml` | PR / push(main, dev) | Xcode ビルド + Swift Testing(macOS runner) |

## 認証: Workload Identity Federation

SA 鍵ファイルは使わず、GitHub Actions の OIDC トークンを WIF で交換して GCP を操作する。詳細は `dev_documents/implementation_notes/security.md` §9 と `terraform_and_deployment.md` §9。

Terraform で管理されている(`terraform/github_actions.tf`):
- WIF Pool: `github`
- WIF Provider: `github-actions`(`assertion.repository == "ShinjiUrata/ohayashi-doujou"` に制限)
- SA: `github-actions@ohayashi-doujou-{dev,prod}.iam.gserviceaccount.com`

各 SA は以下を持つ:
- `artifactregistry.writer`(Docker push)
- `run.developer`(Cloud Run 更新)
- `iam.serviceAccountUser` on `cloudrun-charts` SA(Cloud Run から使えるように)
- `iam.serviceAccountTokenCreator` on `terraform` SA(Terraform CI が impersonate)

## GitHub 側で必要な設定

### 1. Environment: `production`(prod デプロイの手動承認)

Settings → Environments → `production` を作成:
- **Required reviewers**: `ShinjiUrata`(または任意)を追加
- これで `main` への push で `api-prod-cd` は Approve 待ちになる
- Deployment branches → `main` のみに制限しておく

### 2. Repository Secrets

Settings → Secrets and variables → Actions:

| Secret 名 | 内容 |
|---|---|
| `ALERT_EMAIL` | Terraform の `alert_email` 変数。監視通知先。`kamohigashi.festival@gmail.com` を想定 |

その他の秘密は WIF 経由で不要。

### 3. Actions permissions

Settings → Actions → General:
- **Workflow permissions**: "Read and write permissions" にしておく(PR コメントを書けるように)

## ローカルでの CI 相当を再現するには

```bash
# api-ci 相当
cd backend
npm ci
npm run lint
npm test
docker build -t ohayashi-doujou-api:local .

# terraform-ci 相当
cd terraform
./tf.sh dev plan
./tf.sh prod plan

# ios-ci 相当
cd ios
xcodegen generate
xcodebuild \
  -project OhayashiDoujou.xcodeproj \
  -scheme OhayashiDoujou \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0.1' \
  -configuration Debug \
  test
```

## デプロイの流れ

### 開発サイクル

```
dev ブランチで作業
  ↓ push
api-ci(自動テスト)+ api-dev-cd(自動デプロイ)
  ↓ 動作確認
main ブランチに merge (PR)
  ↓ merge
api-ci + api-prod-cd(承認待ち → 承認 → prod デプロイ)
```

### Terraform 変更

```
terraform/*.tf 変更 in PR
  ↓
terraform-ci(dev/prod 両方の plan、PR コメント)
  ↓ 内容 OK 判断
main に merge
  ↓
ローカルで ./tf.sh dev apply → prod apply
```

Terraform apply は現状 CI に載せていない(状態が壊れた時のリカバリを慎重にしたいため)。将来 apply CD を作りたい場合は `main` push トリガの `terraform-apply.yml` を追加。

## 落とし穴

- **prod branch と dev branch の混同**: `git push origin dev` で prod 到達することはない(ワークフロー条件で守っている)が、ブランチ名の変更時は要注意
- **WIF principalSet の絞り込み**: `terraform/github_actions.tf` の `attribute_condition` を消したりリポジトリ名を空にすると、公開リポジトリの誰でも impersonate 可能になる。厳格に維持
- **prod deploy のロールバック**: Terraform では `ignore_changes = [image]` のため、Cloud Run の revision 切戻しは `gcloud run services update-traffic` で対応(`terraform_and_deployment.md` §17 の Runbook)
- **macOS runner の課金**: `ios-ci.yml` は macos-15 を使うため、他 runner より 10 倍高い。paths フィルタで無駄実行を抑制中
