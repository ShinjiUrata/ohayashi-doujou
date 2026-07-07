# Phase 5 App Store Connect セットアップ手順

**位置付け**: Phase 5-A/B(iOS StoreKit 2 + backend 実 JWS 検証)は完了済み。実際に Sandbox / 本番で購入テスト・リリース可能な状態にするための、App Store Connect 側の手動セットアップ手順。

**関連**:
- 全体設計: `CLAUDE.md` §3.8
- 実装手順: `implementation_plan/others.md` §3-5
- 課金 / 法務: `iap_and_legal.md`

---

## チェックリスト(通しの流れ)

- [ ] ステップ 1: App Store Connect でアプリ登録
- [ ] ステップ 2: Consumable IAP プロダクト登録
- [ ] ステップ 3: Sandbox テスターアカウント作成
- [ ] ステップ 4: 実機 iPhone に Sandbox アカウントを紐付け
- [ ] ステップ 5: 実機で E2E 購入テスト
- [ ] ステップ 6 (Phase 6+): App Store Server API 用 `.p8` 発行 → GCP Secret Manager 投入

---

## ステップ 1: App Store Connect でアプリ登録

<https://appstoreconnect.apple.com/apps>

`+ 新規App` から作成:

| 項目 | 値 |
|---|---|
| プラットフォーム | iOS |
| 名前 | `お囃子道場` |
| 主要言語 | 日本語 |
| Bundle ID | `com.zembrem.ohayashidoujou`(prod のみ、Debug 用の `.dev` は Sandbox テスト時に別 Bundle として自動認識) |
| SKU | `ohayashi-doujou-ios` (適当な内部識別子) |
| ユーザーアクセス | フルアクセス |

- [ ] 完了

---

## ステップ 2: Consumable IAP プロダクト登録

作成したアプリ → 「機能 → App内課金」 → `+ 新規`

| 項目 | 値 |
|---|---|
| **タイプ** | **Consumable(消費型)** |
| **参照名** | `譜面公開 (1曲)` (社内表示のみ) |
| **プロダクト ID** | `rhythm.chart.publish.single` **← StoreKitConfig.storekit と完全一致** |
| **価格ティア** | ¥1,000 に相当するティア(Japan 最新)。SBP 適用検討で 15% 手数料狙い |

日本語ローカライズ:
| 項目 | 値 |
|---|---|
| 表示名 | 譜面を公開する |
| 説明 | 1曲分の譜面をサーバーに公開して、他のプレイヤーがダウンロードできるようにします。 |

Review 情報:
| 項目 | 値 |
|---|---|
| Screenshot | ChartPublishView のスクリーンショット(Xcode シミュレータ、`.storekit` 有効化状態で撮影可) |
| Review notes | 「1曲分の譜面公開 = 1回の役務。同一の公開行為は再度実行できない (取り消し不可、修正版は別 ID で新規公開)」 |

保存後、ステータスが「準備完了」または「Waiting for Review」になれば OK。

- [ ] プロダクト登録完了
- [ ] プロダクト ID = `rhythm.chart.publish.single` を確認

---

## ステップ 3: Sandbox テスターアカウント作成

<https://appstoreconnect.apple.com/access/users>

**Users and Access → Sandbox → Testers → `+`**

| 項目 | 値 |
|---|---|
| First / Last Name | 任意(例: `Sandbox`, `Tester1`) |
| Email | **実 Apple ID として未使用のメールアドレス**(kamohigashi.festival+sandbox@gmail.com 等のエイリアスで OK) |
| Password | Apple ID の要件を満たすパスワード |
| Country / Region | `Japan` |

- [ ] Sandbox テスター 1〜複数作成

---

## ステップ 4: 実機 iPhone に Sandbox アカウントを紐付け

対象実機で:

1. 設定 → **App Store** → **Sandbox アカウント**
2. **サインイン** → ステップ 3 で作った Sandbox アカウントの認証情報を入力
3. 完了

**注意点**:
- 実 Apple ID は通常の App Store 用にサインインしたまま、Sandbox アカウントだけ「App Store」設定で別途登録する形が正しい
- iPhone の **設定 → iCloud** で実 Apple ID にサインインしたままで OK
- Sandbox テスターとして誤って実 Apple ID を使うと、購入履歴の紐付けが破綻するので厳禁

- [ ] iPhone で Sandbox アカウント紐付け完了

---

## ステップ 5: 実機で E2E 購入テスト

1. Xcode で Release / Debug でも「実機ターゲット」で Run
2. アプリ内で 録音 → 編集 → 「この譜面を公開する」
3. 課金ダイアログが出る
4. Sandbox アカウントの認証情報を再入力(場合による)
5. 購入 → JWS が backend に送られる
6. backend の JWS 実検証を通過 → **/publish 成功 → 発行 ID を表示**

### Xcode で StoreKit Configuration File を **OFF** にする

Sandbox で購入する場合は、Xcode の **Scheme → Run → Options → StoreKit Configuration** を **None** に切替える必要がある(`.storekit` 有効時はローカル署名になり、Apple の Sandbox にリクエストが飛ばないため)。

**開発中の使い分け**:
- UI テスト・iOS 側だけ試したい → `.storekit` 有効(Debug 実行)
- Backend まで含めた E2E → `.storekit` を **None**、Sandbox アカウントで実端末実行

### 確認ポイント

- iOS の課金ダイアログに `[Environment: Sandbox]` バッジが出る
- backend のログに `bundle_id=com.zembrem.ohayashidoujou.dev` と `environment=Sandbox` が現れる
- 譜面が GCS の `ohayashi-charts-dev` に保存され、別端末で ID DL できる

- [ ] Sandbox 経由の完全 E2E 購入 → publish 成功を確認
- [ ] 別端末で ID 検索 → DL → プレイ 成功を確認

---

## ステップ 6(Phase 6 でも可): App Store Server API 用 `.p8`

**このステップは MVP では省略可能**。JWS のオフライン検証だけで規約上十分。将来 App Store Server Notifications V2 で refund 通知を受けたい時に必要。

**用意する場合の手順**:

1. App Store Connect → Users and Access → **Keys** → **In-App Purchase**
2. **`+ Generate API Key`** で `.p8` ダウンロード(**1 回だけダウンロード可**)
3. 同ページの **Key ID** / **Issuer ID** を控える
4. `.p8` を GCP Secret Manager に投入:
   ```bash
   gcloud secrets versions add apple-p8 \
     --data-file=./AuthKey_XXXXXXXXXX.p8 \
     --project=ohayashi-doujou-prod
   ```
5. ローカルの `.p8` ファイルは削除
6. Cloud Run から Secret を参照するように `terraform/cloudrun.tf` で `env` 追加(次回改修時)

- [ ] Phase 6 以降で対応

---

## Bundle ID 差異に関する注意

| 環境 | Bundle ID | 想定 IAP プロダクト |
|---|---|---|
| Debug (`.dev`) | `com.zembrem.ohayashidoujou.dev` | Debug ビルドの Sandbox 購入は `rhythm.chart.publish.single` の Sandbox 版で扱われる |
| Release | `com.zembrem.ohayashidoujou` | 本番 App Store 経由の Consumable 課金 |

backend の `APPLE_BUNDLE_ID` は Terraform で環境ごとに自動切替済み:
- dev Cloud Run → `com.zembrem.ohayashidoujou.dev`
- prod Cloud Run → `com.zembrem.ohayashidoujou`

**Apple 側の Bundle ID 登録**:
- App Store Connect には **本番 Bundle ID (`com.zembrem.ohayashidoujou`) だけ**登録する
- `.dev` バリアントは Debug 開発中の便宜的なもので、App Store には出さない
- Sandbox 購入時に `.dev` Bundle ID が Apple に伝わり、Apple 側は本番プロダクトに対する Sandbox 決済として扱う

---

## トラブルシューティング

### 課金ダイアログで「購入エラー」

- Sandbox アカウントで実 Apple ID とサインインが混ざっている → 設定 → App Store → Sandbox アカウントを再設定
- プロダクト ID が違う → StoreKitConfig.storekit と ASC 側の productID が完全一致か確認

### `TRANSACTION_INVALID` が backend から返る

- iOS が `.storekit` 有効モードで動いている → Sandbox 経由の検証なら Xcode Scheme の StoreKit Configuration を None に
- `APPLE_BUNDLE_ID` が Cloud Run 側と実 Bundle ID で違う → Cloud Run 環境変数を再確認

### `TRANSACTION_ALREADY_USED` が返る

- 一度成功した transaction を再送している → Sandbox で一度 finish したものを別 chart_id で再送しても失敗する。新しい Sandbox 購入からやり直す

---

## 実装チェックリスト(Phase 5-C 全体)

- [ ] App Store Connect でアプリ登録
- [ ] IAP プロダクト `rhythm.chart.publish.single` 登録(Consumable, ¥1,000)
- [ ] Sandbox テスター作成
- [ ] 実機 iPhone に Sandbox アカウント紐付け
- [ ] `.storekit` を Off にして Sandbox 実機で E2E 購入テスト成功
- [ ] backend で JWS 検証を通過 → publish 成功 → GCS に譜面 → 別端末で DL 成功
- [ ] `.p8` 発行と Secret Manager 投入(Phase 6 で OK)
