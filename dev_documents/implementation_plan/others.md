# その他 実装手順(iOS/バックエンド以外)

このドキュメントは iOS アプリ・バックエンド以外の実装・準備事項を網羅する。
各項目には「何を / 技術 / 粒度 / 対応 Phase」を明記する。

参照:
- 全体設計: `CLAUDE.md`
- iOS 実装: `dev_documents/implementation_plan/ios.md`
- バックエンド実装: `dev_documents/implementation_plan/backend.md`

---

## 全体方針

- Apple / Google の 2 つのプラットフォーム契約が土台
- ドメイン・法務・素材準備は開発初期に並行して進める
- 譜面素材はお囃子指導者との連携が必要 → 早めに調整着手
- MVP は「弊社取引先の自治体1つ」の運用を最初のターゲットに、段階的に横展開

---

## 1. Apple Developer Program

**何を**: iOS アプリ配信の前提となる Apple の年間契約。

**技術**: Apple Developer Portal

**粒度**:
- 契約種別: 法人アカウント(D-U-N-S ナンバー必要)
- 費用: ¥12,800 / 年
- Team メンバー招待
- 発行物:
  - iOS Development Certificate
  - iOS Distribution Certificate
  - App ID: `com.zembrem.ohayashidoujou` / `com.zembrem.ohayashidoujou.dev`
  - Capability: **In-App Purchase** を有効化
  - Provisioning Profiles(Development / App Store Distribution)

**Phase**: Phase 1 の前段(既に契約予定の状態、CLAUDE.md §2 記載)

---

## 2. App Store Connect(App 登録)

**何を**: App Store 上のアプリ情報登録と IAP プロダクト設定。

**技術**: App Store Connect Web UI

**粒度**:

### App 情報
- Bundle ID: `com.zembrem.ohayashidoujou`
- Primary Language: 日本語
- カテゴリ: Games > Music
- サブタイトル・キーワード
- 説明文(祭りブース設置想定を明記)
- サポート URL(要準備、GitHub Pages 等でも可)
- プライバシーポリシー URL(要準備)

### App プライバシー
- データ収集: なし(トランザクション情報のみサーバー保持)
- 認証・アカウント: なし

### アイコン・スクリーンショット
- App アイコン(1024x1024)
- iPhone スクリーンショット(6.9"/6.5"/5.5" 等の必須サイズ)
- App プレビュー動画(任意)

**Phase**: Phase 6-7

---

## 3. App Store Connect(IAP プロダクト)

**何を**: 課金対象の Consumable プロダクト登録。

**技術**: App Store Connect > In-App Purchase

**粒度**:
- Product ID: `rhythm.chart.publish.single`
- Type: **Consumable**
- Reference Name(社内用): 「譜面公開(1曲)」
- Localizations(JP):
  - Display Name: 「譜面を公開する」
  - Description: 「1曲分の譜面をサーバーに公開して他のプレイヤーがダウンロードできるようにします」
- Price Tier: ¥1,000(Tier 10 or 相当、税込表示に注意)
- Review 提出時の Screenshot: 公開画面のモック or 実機スクショ

**Phase**: Phase 5

---

## 4. App Store Server API 用の鍵

**何を**: バックエンドが Apple サーバーと通信するための認証情報。

**技術**: App Store Connect > Users and Access > Keys > In-App Purchase

**粒度**:
- Key を発行:
  - `.p8` ファイル(秘密鍵) — 1 度しかダウンロードできない、厳重保管
  - Key ID
  - Issuer ID(アカウント全体で1つ)
- 保管:
  - GCP Secret Manager に格納
  - ローカル環境変数から参照
- `.p8` ファイルは絶対に Git に commit しない(`.gitignore` に登録済み)

**Phase**: Phase 5(バックエンドの JWS 検証で必須になったタイミング)

---

## 5. Sandbox テスター

**何を**: 開発中の課金テスト用ダミー Apple ID。

**技術**: App Store Connect > Users and Access > Sandbox

**粒度**:
- テスター用 Apple ID を数個作成(実在のドメインでない架空メールでOK)
- 各実機の「設定 → App Store → Sandbox アカウント」に紐付け
- Consumable の性質上、繰り返し購入可能

**Phase**: Phase 5

---

## 6. URL 方針(独自ドメインなし)

**何を**: 本プロジェクトでは**独自ドメインを取得しない**。API は Cloud Run 発行のデフォルト URL、charts は GCS の直接 URL を使う。

**技術**: Cloud Run + Cloud Storage(いずれも SSL 自動、URL 自動発行)

**粒度**:
- **API**: `https://api-<hash>.asia-northeast1.run.app`(dev / prod で hash が異なる)
- **Charts**: `https://storage.googleapis.com/ohayashi-charts-{env}/{id}.json`
- iOS の xcconfig に実 URL をハードコード(Terraform 出力から取得)
- 詳細は `backend.md` §11 参照

**メリット**:
- ドメイン維持コスト・DNS 管理・SSL 証明書管理がすべて不要
- Cloud Load Balancer も不要(月額 $18 節約)
- DNS 伝播を待たずにリリース可能

**デメリット**:
- URL の見た目が長い(が、iOS 側ハードコードでユーザーには見えない)
- Cloud Run サービス削除 → 再作成で hash 変更のリスク(通常運用では発生しない)

**Phase**: Phase 4

---

## 7. DNS / SSL 設定

**削除**: §6 の方針により DNS 設定は不要。SSL は Cloud Run / Cloud Storage が自動対応。

---

## 8. アプリアイコン

**何を**: App Store とホーム画面用のアイコン。

**技術**: 画像制作(Figma / Illustrator 等)、Xcode Assets Catalog

**粒度**:
- サイズ:
  - 1024x1024(App Store 用マスター)
  - Xcode Assets で 20pt〜1024pt を自動生成
- デザイン方向:
  - 太鼓シルエット + 「囃」文字
  - 朱・金・黒の祭り配色
  - 単色背景で子供に視認性良く
- 素材:
  - MVP: 簡易版で開始
  - Phase 7 で最終版に差し替え

**Phase**: Phase 6-7

---

## 9. スプラッシュ / LaunchScreen

**何を**: アプリ起動直後の画面。

**技術**: LaunchScreen.storyboard(Xcode)

**粒度**:
- 和柄背景 + タイトル文字のシンプル構成
- 起動時のフリッカーを避けるため、初回 SwiftUI ビューと視覚的に連続する配色を採る
- iPhone 全機種の縦画面に対応(Safe Area 考慮)

**Phase**: Phase 6-7

---

## 10. 効果音素材

**何を**: ドン / カッ の 2 種類の WAV。

**技術**: フリー音源サイト(効果音ラボ、DOVA-SYNDROME 等)、GarageBand for編集

**粒度**:
- フォーマット: WAV(44.1kHz / 16bit、モノラルで十分)
- 長さ: 0.5 秒以内(打感重視)
- ライセンス: 商用利用可・帰属表記要否を確認
- MVP: フリー素材で開始
- Phase 7: 和太鼓・締太鼓の本物音源に差し替え検討

**Phase**: Phase 1(初期)/ Phase 7(最終)

---

## 11. 譜面素材の作成

**何を**: 開発中の動作確認用 + リリース時の初期公開譜面。

**技術**: アプリ本体の録音モード

**粒度**:

### 開発中(Phase 2-4)
- 簡単なテスト譜面 1〜2 個を JSON 直書きで用意
  - 例: 4拍の単純パターン、獅子舞の入りだけ
- 開発者(社内)が手打ちで作る

### リリース時(Phase 7)
- お囃子指導者との調整:
  - 弊社取引先の自治体経由で紹介依頼
  - 録音セッションの日程調整
  - アプリの録音モードで実際に叩いてもらう
- 数曲用意(獅子舞、神輿囃子、屋台囃子 等)
- 初期公開:
  - 弊社アカウントで先行公開
  - 課金は自社内なので実質無料
  - もしくは開発中は check-id を通さず `gsutil cp` で直接 GCS にアップロード(管理者運用)

**Phase**: Phase 2(開発用)/ Phase 7(リリース用)

---

## 12. 利用規約

**何を**: サービス利用のルール文書、特に IAP に関わる規定。

**技術**: HTML/Markdown を GitHub Pages / GCS に配置

**粒度**:
- 主要項目:
  - サービス概要
  - IAP について:
    - Consumable(消費型)である旨
    - 購入後の返金不可
    - 譜面公開後のキャンセル不可
  - 譜面公開ポリシー:
    - 著作権侵害・不適切コンテンツの禁止
    - 弊社判断で取り下げる場合がある旨
    - 譜面 ID の推測アクセスは仕様上許容
  - 免責事項
  - 準拠法・裁判管轄
- 弁護士レビュー推奨(IAP 規約は特に重要)

**Phase**: Phase 5-6(App Store 提出前必須)

---

## 13. プライバシーポリシー

**何を**: 個人情報取り扱いに関する説明。

**技術**: HTML/Markdown

**粒度**:
- 収集情報:
  - 基本: なし(アカウント/認証なし)
  - 通信ログ(IP、User Agent):Cloud Run のアクセスログとして 14 日保持
  - 課金トランザクション: Apple 経由、弊社は transaction_id と chart_id を紐付けて保持
- 第三者提供:
  - Apple(決済)
  - Google(GCP インフラ)
- クッキー・トラッキング: なし
- お問い合わせ窓口: メール

**Phase**: Phase 5-6(App Store 提出前必須)

---

## 14. 特定商取引法に基づく表記

**何を**: 課金があるサービスに義務付けられている表記。

**技術**: HTML/Markdown、専用URL

**粒度**:
- 販売事業者名(法人名)
- 所在地
- 代表者名
- 連絡先(電話番号・メール)
- 商品名: 「譜面公開サービス」
- 販売価格: ¥1,000(税込)
- 支払方法: Apple 決済(App Store)
- 商品引き渡し時期: 決済完了後即時
- 返品・キャンセル: 原則不可(Consumable、購入と役務提供が同時のため)
- 動作環境: iOS 17 以上

**Phase**: Phase 5-6(App Store 提出前必須)

---

## 15. 譜面取り下げ運用

**何を**: 不適切な譜面の削除運用ルール。

**技術**: `gsutil`, `gcloud firestore`, メール受付

**粒度**:

### MVP(手動運用)
- 受付方法: 弊社サポートメール
- 判断基準:
  - 明らかな著作権侵害
  - 不適切コンテンツ(暴力・差別 等)
  - 個人情報漏洩
- 実施手順:
  1. GCS から `{id}.json` 削除(`gsutil rm`)
  2. Firestore の `charts.{id}.status` を `withdrawn` に更新
  3. 対応記録を残す
- 影響: DL 済み端末はそのまま使えるが、新規 DL 不可

### Phase 6+(自動化検討)
- 管理画面 or CLI ツール
- 削除履歴の管理

**Phase**: Phase 6-7(運用ルール整備)

---

## 16. テスト戦略(全体)

**何を**: 各層のテストと総合的な品質保証。

**技術**: XCTest / Swift Testing, Jest, Firebase Emulator, 実機

**粒度**:

### iOS
- ユニットテスト(主要ロジック)
- UI テスト(スモーク、主要フローのみ)
- StoreKit Configuration File での自動購入テスト

### バックエンド
- ユニットテスト(Jest)
- 統合テスト(Firebase Emulator)
- Sandbox 経由の E2E

### 総合テスト
- Sandbox 課金 → 譜面公開 → 別端末で DL → プレイ の一連フロー
- ネットワーク切断時の挙動(DL 中断、公開中断)

### 祭り運用テスト(Phase 7)
- 子供が連続してプレイする想定シナリオ
- 判定窓の調整(実際の子供に触ってもらう)
- 電池消耗・端末発熱の観察
- 譜面が2曲以上あるときのライブラリ選択の使いやすさ

**Phase**: 各 Phase で継続

---

## 17. リリース準備(App Store)

**何を**: App Store 審査提出。

**技術**: App Store Connect

**粒度**:
- App プレビュー画像(必須サイズを全て用意)
- App プレビュー動画(任意、あると審査で有利)
- Review Notes(審査官向けの補足):
  - IAP テストアカウント情報(Sandbox とは別、Review 用の実 Apple ID を要する場合あり)
  - 譜面 ID 「shimoda-2026-irihayashi」等の実例 ID を提示
  - アプリの想定使用シーン(祭りブース)を説明
- Rating Questionnaire(子供向けアプリ)
- Export Compliance(暗号化: HTTPS のみなら Standard、要確認)

**Phase**: Phase 7

---

## 18. 審査で注意すべき Guideline

**何を**: Apple Review で拒否されがちなポイントの事前チェック。

**技術**: App Store Review Guidelines 熟読

**粒度**:
- **3.1.1** IAP は Apple の StoreKit を使うこと(該当、対応済)
- **3.1.3** Consumable の性質と実装が一致すること(該当、要説明準備)
- **1.3** 子供向けカテゴリ:
  - MVP は「Kids Category」を選ばず、通常カテゴリで提出予定
  - Kids Category を選ぶと審査が厳しくなる
- **5.1.1** プライバシーポリシー必須
- **5.6** 開発者情報の正確性
- Sandbox テスト完了しているか、実機での動作確認済みか

**Phase**: Phase 7(提出直前)

---

## 19. リリース後の運用

**何を**: リリース後の観察と対応。

**技術**: Cloud Monitoring, App Store Connect Analytics, サポートメール

**粒度**:
- **観察**:
  - Cloud Monitoring:ログ量・バケット req 頻度
  - App Store Connect: DL 数、IAP トランザクション数、クラッシュレポート
  - Firestore: 公開譜面数
- **対応**:
  - 譜面取り下げ依頼
  - ユーザー問い合わせ(メール)
  - クラッシュ発生時のホットフィックスリリース
- **コスト観察**:
  - 週次で予算アラート確認
  - 月次でコスト集計

**Phase**: Phase 7 以降(継続)

---

## 20. 弊社取引先(自治体)への提案

**何を**: MVP リリース後の自治体向け展開。

**技術**: 営業活動、資料作成

**粒度**:
- 説明資料(パワポ or PDF):
  - アプリ概要
  - 使い方(会場設置手順、譜面公開手順)
  - コスト(¥1,000/曲)
- 初期利用自治体との調整:
  - 秋祭りシーズンに向けた事前準備
  - お囃子指導者の紹介
  - 会場設置用の iPhone / iPad 端末の手配(弊社貸出 or 自治体調達)

**Phase**: Phase 7 以降

---

## 21. 将来対応(MVP 外)

- **AirDrop 譜面共有**(CLAUDE.md §3.7)
- **QR コード**(公開ID告知 / DL 補助)
- **譜面のノーツ個別編集 UI**(位置微調整)
- **連打ノート / 両手同時打**(§8 未決事項 #5, #6)
- **楽曲(BGM)対応**(§4 に将来余地の記載あり)
- **iPad 対応 / 横持ち対応**
- **英語ローカライズ**(海外展開時)
- **CI/CD 自動化**(GitHub Actions + fastlane)
- **CDN 導入**(GCS 前段、規模拡大時)
- **管理画面**(譜面取り下げ、返金対応)
- **統計ダッシュボード**(公開譜面数、DL 数の集計)

---

## 22. Phase 対応マトリクス

| Phase | その他項目(節番号) |
|---|---|
| Phase 0(前段) | 1(Apple 契約) |
| Phase 4 | 6, 7, 15(基本) |
| Phase 5 | 3, 4, 5, 12, 13, 14 |
| Phase 6 | 8(初期), 9, 15(自動化検討) |
| Phase 7 | 2(App Store 登録), 8(最終), 10(最終), 11, 16(祭り運用), 17, 18, 19, 20 |
