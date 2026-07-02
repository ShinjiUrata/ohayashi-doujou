# バックエンドセキュリティ — 気をつけること

**位置付け**: `dev_documents/implementation_plan/backend.md` で定義した実装項目のうち、セキュリティ観点で特に注意すべき点をまとめる。JWS 検証・race condition・権限最小化が主軸。

**関連**:
- 実装手順: `dev_documents/implementation_plan/backend.md` §5 `/check-id`, §6 `/publish`, §7 JWS 検証
- コスト: `dev_documents/implementation_notes/cost_protection.md`
- 課金・法務: `dev_documents/implementation_notes/iap_and_legal.md`

---

## 1. JWS 検証を「ライブラリ任せ」で終わらせない

**問題**: `app-store-server-library` (Node.js) を使えば署名検証は通るが、**payload の中身の妥当性チェック** はアプリ側の責任。ここを怠ると、正規の JWS(=別アプリ・別プロダクト・Sandbox の請求)で本番に譜面が publish される可能性がある。

**必須チェック項目**(payload デコード後):
- `bundleId == "com.zembrem.ohayashidoujou"`(本番)or `.dev`(開発)
- `productId == "rhythm.chart.publish.single"`
- `environment == "Production"` or `"Sandbox"` — 環境に応じたバケット/DB を使う
- `purchaseDate` が現在時刻から前後 24 時間以内
- `transactionId` が空でない

これらは全て検証コードの中でハードコード検証。ミスマッチはすべて `402 Payment Required`。

---

## 2. Sandbox と Production の混同

**問題**: JWS は環境情報を持つが、バックエンド側で「Production の請求で開発バケットに書く」あるいはその逆をやってしまうと、データが混ざる/使い物にならない。

**対策**:
- 開発プロジェクトの Cloud Run は環境変数 `ENVIRONMENT=dev` を持ち、JWS の `environment != "Sandbox"` なら拒否
- 本番プロジェクトは `ENVIRONMENT=prod` で `environment != "Production"` なら拒否
- 開発向けのユーザーは Debug ビルドを使うため .dev Bundle ID → 開発 Cloud Run → Sandbox JWS で完結する
- **本番 Cloud Run に Sandbox JWS が届いた場合は 402 で拒否**(通常ないが防御)

---

## 3. Transaction ID の二重使用

**問題**: 一度使った `transaction_id` で別の chart_id を publish されると、1 回の課金で複数の譜面が公開されてしまう。

**対策**:
- Firestore の `transactions/{transaction_id}` を主キーとして扱う
- `/publish` 内で Firestore Transaction を使い、以下を atomic に:
  1. `transactions/{transaction_id}` が既に存在するか読む
  2. 存在すれば 402 で拒否
  3. なければ書き込みと `charts/{chart_id}` 書き込みを同トランザクションで実施
- GCS への書き込みは Firestore トランザクション成功後に実施(順序重要)
- **注意**: GCS 書き込みが失敗した場合、Firestore は成功しているので不整合が生じる。この時のリカバリ手順を Runbook 化(`gsutil cp` で再アップロード)

---

## 4. Chart ID の race condition

**問題**: `/check-id` を通過した瞬間から `/publish` 完了までの間に、別ユーザーが同じ ID で publish する可能性がある。

**対策**:
- `/publish` 内で改めて `charts/{chart_id}` 存在チェック(Firestore Transaction 内で)
- 存在すれば `409 Conflict` を返す
- **課金は既に完了している**ため、この場合ユーザーに手動サポート案内を出す
- 発生確率は低いが、想定内であることを利用規約に明記(§iap_and_legal.md 参照)

---

## 5. リクエストサイズ制限

**問題**: 悪意ある大サイズ JSON を送りつけられて Cloud Run のメモリを枯渇させられる。

**対策**:
- Hono / Cloud Run で `Content-Length` を検証(100KB 超は 413 で拒否)
- `chart_json` を JSON デコード前にサイズチェック
- 通常譜面は数十 KB 程度、100KB は十分な余裕

---

## 6. サービスアカウント権限の最小化

**問題**: Cloud Run SA に過剰な権限を付与すると、コード侵害時の被害範囲が広がる。

**対策**:
- Cloud Run SA には以下のみ付与:
  - `roles/datastore.user`(Firestore、必要なコレクションに限定可能ならさらに絞る)
  - Cloud Storage の Object Admin は **charts バケットにのみ**(条件付き IAM で bucket 単位制限)
  - `roles/logging.logWriter`
- **絶対に付与しない**:
  - `roles/owner`, `roles/editor`
  - プロジェクト全体の Storage Admin
- 開発者の個人アカウントで Cloud Run を叩く運用はしない(必ず SA 経由)

---

## 7. Apple ルート証明書 / ライブラリの更新

**問題**: Apple のルート証明書は数年ごとに更新される。古いライブラリを放置すると、ある日突然 JWS 検証が全て通らなくなる。

**対策**:
- `app-store-server-library` の Dependabot / Renovate を有効化
- Apple の Developer News を購読して証明書更新の告知を追う
- 検証ライブラリのバージョンは Node.js の `package.json` で pin し、更新時は必ずテスト

---

## 8. Rate Limiting

**問題**: `/check-id` は「使いたい ID を打って確認」を繰り返すので、正当利用でも数回叩かれる。しかし、悪意ある推測攻撃で 1000 req/s を送られると、Cloud Run の課金や Firestore の read 課金が跳ねる。

**対策**:
- **`/check-id`**: 単一 IP から 1 秒に 10 回以上 → 429 Too Many Requests
- **`/publish`**: 単一 IP から 1 分に 3 回以上 → 429
- 実装は Cloud Run のメモリ内キャッシュ(単純な token bucket)で十分
- 悪質な場合は Cloud Armor 導入を Phase 6+ で検討

---

## 9. `.p8` 秘密鍵の管理

**問題**: App Store Server API の `.p8` ファイルは 1 度しかダウンロードできない。漏洩すると Apple 側のトランザクション情報にアクセスされる。

**対策**:
- 発行後すぐに **GCP Secret Manager** に格納
- ローカル PC に置いた `.p8` はダウンロード後即削除
- `.gitignore` に `*.p8` 登録済み(既に対応済)
- 万一漏洩したら App Store Connect で **即座に revoke → 新規発行**

---

## 10. エラーメッセージの情報漏洩

**問題**: エラーメッセージが具体的すぎると、攻撃者が挙動を推測できる。

**対策**:
- クライアントに返すエラーは種別のみ(`INVALID_REQUEST` / `TRANSACTION_ALREADY_USED` / `ID_CONFLICT`)
- 詳細メッセージ・スタックトレースは Cloud Logging に構造化ログとして
- 「なぜ 402 が返ったか」の判断ができるログを内部だけに残す
- スタックトレースは Error Reporting 経由(Cloud Logging 本体には要約のみ)

---

## 11. 認証ヘッダの信用しすぎ

**問題**: `User-Agent`, `X-Forwarded-For` などのヘッダは容易に偽装できる。

**対策**:
- **認証の根拠は JWS のみ**
- IP はログ・レート制限用途で使うが、認証には使わない
- カスタムヘッダで「アプリからのリクエスト」を判定しようとしない(意味がない)

---

## 12. Firestore ドキュメントの 1MB 制限

**問題**: 譜面が大きい将来を考えると、Firestore の 1MB/document 制限に触れる可能性(現状は数 KB なので無問題)。

**対策**:
- 現状は問題なしだが、譜面 JSON 本体は **Firestore に保存しない**(GCS のみ)
- Firestore はメタデータ台帳としてのみ使う設計を維持

---

## 13. GCS Object 公開設定の誤操作

**問題**: バケット全体を Public にしてしまうと ListObjects も許可される可能性がある(誤設定パターン)。

**対策**:
- `allUsers` に付与する権限は **`Storage Object Viewer` のみ**
- `Storage Object Lister` / `Storage Admin` は絶対に付与しない
- IaC(Terraform 等)化を検討 — 手動設定の間違いを防げる
- 定期的に `gcloud storage buckets get-iam-policy` で確認

---

## 14. デプロイ時のシークレット混入

**問題**: 環境変数として `.p8` の内容を Cloud Run に直接埋め込むと、デプロイログや gcloud CLI 履歴に残る可能性。

**対策**:
- 環境変数には Secret Manager の参照だけを設定(Cloud Run の `--set-secrets`)
- 秘密の中身は Cloud Run 起動時に自動注入される
- デプロイスクリプトのログ、CI/CD の環境変数出力に注意

---

## 15. 監査ログの保持

**問題**: 事後調査時に「誰がいつどの操作をしたか」が分からないと原因追跡できない。

**対策**:
- Cloud Audit Logs(Admin Activity)を最低 30 日保持
- 特に Cloud Storage の IAM 変更、Firestore の削除操作
- コスト最適化(`cost_protection.md` §1C)と保持期間のバランスを取る

---

## 実装チェックリスト

- [ ] JWS 検証: bundle_id / product_id / environment / purchaseDate をコード内で明示検証
- [ ] Sandbox/Production の混同防止(環境変数 + 検証)
- [ ] transaction_id の Firestore トランザクショナル記録
- [ ] chart_id の race condition 対応(Transaction 内で再チェック)
- [ ] リクエストサイズ 100KB 制限
- [ ] Cloud Run SA の権限最小化
- [ ] Apple ルート証明書更新対応(依存ライブラリ pin + 定期チェック)
- [ ] Rate Limiting(check-id 10 req/s, publish 3 req/min)
- [ ] `.p8` は Secret Manager 格納
- [ ] クライアント向けエラーの汎化(内部詳細は隠蔽)
- [ ] GCS 公開設定は allUsers に Viewer のみ
- [ ] Secret Manager 経由での秘密注入
- [ ] Cloud Audit Logs 保持 30 日以上
