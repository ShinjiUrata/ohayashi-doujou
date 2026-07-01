# コスト保護対策 — 必須実装項目

**位置付け**: 本プロジェクトのバックエンドは GCP の無料枠内収まりを前提とした構成だが、以下の2つのリスクは放置すると想定外の課金を招く可能性がある。**実装時に必ず対応する。**

**対象リスク**:
1. Cloud Logging のログ量暴走
2. Cloud Storage への悪意ある大量ダウンロード

**参照**:
- `CLAUDE.md` §3.8 譜面共有(バックエンド)
- `infra-proposal.html` §8 リスクと注意点

---

## 1. ログ量の暴走

### リスク
Cloud Logging は 50GB/月まで無料だが、以下の状況で無料枠を超える可能性がある:
- Cloud Run のエラー時にスタックトレースが繰り返し記録される
- HTTP 200 の詳細ログが大量に蓄積される
- 悪意ある大量リクエストによる連鎖的ログ増加

### 必須対応

#### A. Log Router で除外フィルタを設定

Cloud Run の HTTP 200 アクセスログは通常運用では不要。以下のフィルタを `_Default` sink から除外:

```
resource.type = "cloud_run_revision"
AND httpRequest.status = 200
AND NOT severity >= "ERROR"
```

設定方法(gcloud):
```bash
gcloud logging sinks update _Default \
  --add-exclusion=name=http200-noise,filter='resource.type="cloud_run_revision" AND httpRequest.status=200 AND severity<"ERROR"'
```

#### B. Cloud Run 側で構造化ログ(JSON)出力を徹底

アプリケーションコード側で:
- **INFO**: 識別に必要な情報のみ(`transaction_id`, `chart_id`, `duration_ms`)
- **ERROR**: エラーメッセージ + 短い trace ID(フルスタックトレースは含めない)
- **フルスタックトレース**: Cloud Error Reporting に送出、Cloud Logging には概要のみ

避けるべきパターン:
- リクエスト/レスポンスの全ボディをログ出力
- ループ内での高頻度ログ
- DEBUG レベルログの本番出力

#### C. ログ保持期間の短縮

`_Default` バケットの保持期間を **14日** に(デフォルトは30日):
```bash
gcloud logging buckets update _Default \
  --location=global --retention-days=14
```

#### D. アラート設定(Cloud Monitoring)

- **日次ログ量 1 GB/日超え** → Warning 通知
- **月次ログ量 20 GB/月超え** → Critical 通知(無料枠40%消費時点で対応判断)

### 実装チェックリスト

- [ ] Cloud Run コード: 構造化ログ(JSON)のみ出力
- [ ] Cloud Run コード: リクエストボディ全体をログ出力しない
- [ ] Cloud Run コード: エラー時はスタックトレースを Error Reporting へ、Logging には要約と error ID のみ
- [ ] Log Router: HTTP 200 かつ severity < ERROR を `_Default` sink から除外
- [ ] `_Default` sink の保持期間を 14日 に設定
- [ ] Cloud Monitoring アラート: 日次 1 GB/日 (Warning)
- [ ] Cloud Monitoring アラート: 月次 20 GB/月 (Critical)
- [ ] 通知チャネル(メール等)の設定

---

## 2. Cloud Storage への悪意ある大量ダウンロード

### リスク

- 公開バケット構成のため `GET storage.googleapis.com/{bucket}/{id}.json` は誰でも実行可能
- 悪意ある大量DL 攻撃で egress 課金が発生する可能性
- 現実的な金銭リスクは限定的(1M DL × 20 KB = 20 GB = ~$2.40)
- ただし、無視すべきではない。予兆検知と即応体制が重要

### 必須対応

#### A. GCP 予算アラート(3段階)

GCP コンソール(Billing → Budgets & alerts)で:
- **¥500/月** — Warning(通知のみ)
- **¥1,000/月** — Alert(通知強化)
- **¥3,000/月** — Critical(即時対応判断ライン)

想定運用では月額 ¥100 未満のため、¥500 で異常検知可能。

#### B. Cloud Monitoring: リクエスト頻度異常検知

Cloud Storage バケットの `storage.googleapis.com/api/request_count` メトリクスに対して:
- **1時間 1,000 req 超** → Warning
- **1時間 10,000 req 超** → Critical(即座にバケット公開停止判断)

想定正常値: 1時間あたり数〜数十 req 程度。

#### C. クライアント側キャッシュの徹底

iOS アプリ側で:
- ローカル保存済み譜面は再DLしない(ID → local file 存在チェック)
- 同一セッション内での再DLも防止
- 「ID検索 → ローカルヒット → その場でDL済み表示」のフローを最優先

これにより正当ユーザーによる同一譜面の繰り返しDLを構造的にゼロにする。

#### D. 緊急対応手順(Runbook)

異常検知時に即座に実行できる手順:

```bash
# ─── 1. バケットの公開アクセスを一時停止(egress を止める)
gsutil iam ch -d allUsers:objectViewer gs://ohayashi-charts

# ─── 2. 攻撃元の分析
# Cloud Logging で bucket リクエストログを絞り込み、httpRequest.remoteIp を集計
gcloud logging read \
  'resource.type="gcs_bucket" AND resource.labels.bucket_name="ohayashi-charts"' \
  --limit=1000 --format=json | jq -r '.[].httpRequest.remoteIp' | sort | uniq -c | sort -rn

# ─── 3. 復旧(問題解消を確認してから)
gsutil iam ch allUsers:objectViewer gs://ohayashi-charts
```

上記コマンドを **README 等に置き、コピペで実行できる状態にする**(緊急時は判断せずに実行できることが重要)。

### 実装チェックリスト

- [ ] GCP 請求アラート ¥500 / ¥1,000 / ¥3,000(3段階)を設定
- [ ] Cloud Monitoring: バケット req 頻度アラート(1時間 1K, 10K)
- [ ] iOS: ローカルキャッシュ実装(`Documents/charts/{id}.json` 存在チェック)
- [ ] iOS: 同一セッション内の再DL防止(メモリキャッシュ)
- [ ] Runbook: バケット公開停止手順を README に記載
- [ ] 通知チャネル(メール + Slack等)の確定と接続確認
- [ ] 緊急対応の通知連絡先を関係者間で共有

---

## 3. 実装時のセルフレビュー

Cloud Run / iOS / GCP 設定の実装完了時に、本ドキュメントのチェックリスト全項目を確認する。
チェック未完了の項目がある場合、本番リリースは行わない。

---

## 4. 変更履歴

| 日付 | 変更内容 |
|---|---|
| 2026-07-02 | 初版作成(ログ量暴走 / GCS 大量DL の必須対応) |
