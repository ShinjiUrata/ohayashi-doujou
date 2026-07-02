# iOS アプリ実装手順

このドキュメントは iOS アプリ側の実装を項目単位で網羅する。各項目には「何を / 技術 / 粒度 / 対応 Phase」を明記する。

参照:
- 全体設計: `CLAUDE.md`
- 各画面詳細: `dev_documents/screens/0X_*.md`
- コスト保護: `dev_documents/implementation_notes/cost_protection.md`

---

## 全体方針

- **SwiftUI が画面ラップ、SpriteKit がゲーム描画・当たり判定を担当**
- 譜面データはローカル JSON、通信は最小限(DL / 公開のみ)
- 課金は StoreKit 2、Consumable 1種類のみ
- ローカライズは日本語のみ(MVP)
- iOS 17.0+ を最小サポート(Swift 6.2, Xcode 26.0.1 想定)
- 縦持ち固定、iPhone のみ(iPad 非対応)

---

## 1. Xcode プロジェクト初期設定

**何を**: 新規 App プロジェクトを作成し、基本設定を確定する。

**技術**: Xcode 26.0.1, SwiftUI App template, Swift 6.2

**粒度**:
- Bundle ID: `com.zembrem.ohayashidoujou`(Release)/ `com.zembrem.ohayashidoujou.dev`(Debug)
- 表示名: 「お囃子道場」
- Deployment target: iOS 17.0+
- Orientation: Portrait 固定(`Info.plist` の `UISupportedInterfaceOrientations`)
- Capabilities: **In-App Purchase** を追加(StoreKit 2 用)
- `Info.plist`:
  - `UIFileSharingEnabled = NO`
  - `LSSupportsOpeningDocumentsInPlace = NO`
- xcconfig で Debug/Release 分岐(API URL・Bundle ID を切替)

**Phase**: Phase 1(最初)

---

## 2. リポジトリ / ディレクトリ構成

**何を**: `ios/` 配下に Xcode プロジェクトを配置し、責務ごとにディレクトリを分ける。

```
ios/
└── OhayashiDoujou.xcodeproj
    OhayashiDoujou/
    ├── App/                    ← エントリポイント (@main)
    ├── Views/                  ← SwiftUI 画面
    │   ├── Title/
    │   ├── Library/
    │   ├── Download/
    │   ├── Play/
    │   ├── Result/
    │   ├── Recording/
    │   ├── Edit/
    │   └── Publish/
    ├── Scenes/                 ← SpriteKit シーン
    │   ├── PlayScene.swift
    │   └── RecordingScene.swift
    ├── Model/                  ← データモデル (Chart, Note)
    ├── Storage/                ← ローカル永続化 (ChartStorage)
    ├── Audio/                  ← 効果音再生 (AudioEngine)
    ├── Haptics/                ← 触覚
    ├── Network/                ← API クライアント
    ├── IAP/                    ← StoreKit 2 ラッパー
    ├── Config/                 ← 環境設定 (AppConfig, xcconfig)
    ├── Resources/              ← WAV、画像、Assets
    └── Tests/                  ← ユニット / UI テスト
```

**技術**: SwiftPM(将来のライブラリ追加に備え SPM ベース)

**粒度**: 最初から責務ごとに分ける。SPM の外部ライブラリは MVP では不使用の想定。

**Phase**: Phase 1

---

## 3. データモデル & ストレージ

**何を**: 譜面 JSON の Codable モデルと、アプリ専用ディレクトリへの永続化。

**技術**: Foundation(`Codable`, `FileManager`, `JSONEncoder`, `JSONDecoder`)

**粒度**:
- `Chart` struct(Codable): `id`, `name`, `region`, `created_at (ISO8601)`, `duration_ms`, `notes: [Note]`
- `Note` struct: `t: Int (ms)`, `type: NoteType`
- `NoteType` enum(String, Codable): `don_l`, `don_r`, `ka_l`, `ka_r`
- `ChartStorage` クラス:
  - 保存先: `Application Support/charts/{id}.json`(Documents 直下は避ける)
  - `list() -> [ChartSummary]`(軽量パース: `notes` を読み飛ばす形)
  - `load(id) -> Chart`
  - `save(chart)`
  - `delete(id)`
  - `exists(id) -> Bool`
- 一覧表示用に `ChartSummary` 型(`notes` を含まない軽量版)を分けると良い

**Phase**: Phase 1 (Chart / Note) / Phase 3 (ChartStorage 完全実装)

---

## 4. オーディオエンジン

**何を**: ドン / カッ の効果音を低遅延で再生する。

**技術**: AVFoundation(`AVAudioEngine`, `AVAudioPCMBuffer`, `AVAudioPlayerNode`, `AVAudioSession`)

**粒度**:
- アプリバンドル同梱の WAV(`don.wav`, `ka.wav`)を起動時にプリロード(`AVAudioPCMBuffer`)
- `AudioEngine` クラス:
  - `start()`: エンジン起動、`AVAudioSession` を `.playback` / `.mixWithOthers` で設定
  - `play(type: NoteType)`: 該当バッファを `scheduleBuffer` して即再生
  - 同時再生対応のため、各 type について複数の `AVAudioPlayerNode` をプールする(連打時のオーバーラップを許容)
- 楽曲(BGM)対応の設計余地は残す(将来的にトラック追加できる構造)

**Phase**: Phase 1(基本)/ Phase 6(ポリッシュ)

---

## 5. 触覚フィードバック

**何を**: 打点時の触覚振動。

**技術**: UIKit(`UIImpactFeedbackGenerator`)

**粒度**:
- `Haptics` クラス(シングルトン)
- ドン: `.medium`
- カッ: `.light`
- 各 generator を保持し、事前 `prepare()` を呼んで即時発火に備える
- 発火後は次回のための `prepare()` を呼び直す

**Phase**: Phase 1(組み込み)/ Phase 6(調整)

---

## 6. プレイシーン(コア体験)

**何を**: 譜面を再生しながらノーツを落下させ、タップ判定を行う。

**技術**: SpriteKit(`SKScene`, `SKAction`, `SKSpriteNode`, `SKShapeNode`)、SwiftUI(`SpriteView`)

**粒度**:

### Phase 1(最小プロトタイプ)
- `PlayScene: SKScene` サブクラス
- 静的レイアウト:
  - 4 レーン(グリッド)
  - 判定ライン(黄金)
  - 判定リング(4 個)
  - 太鼓画像(下部)
- 単一ノーツを上から下へ落下(`SKAction.moveTo`)
- タップ位置で 3 ゾーン判別(x 座標で左外 / 中央 / 右外)
- タイミング判定: ノーツと判定ラインの距離を時間換算し、良/可/不可 に分類
- 効果音 + 触覚
- スコア表示なし、譜面もハードコード

### Phase 2(譜面再生)
- 譜面 JSON からノーツ列を読み込み、`t` の時刻順にスケジュール
- 落下速度: 「ノーツ生成から判定ライン到達までの時間」を一定(暫定 3 秒)
- スコア / コンボ計算
- 良: 高得点+コンボ加算、可: 中得点+コンボ加算、不可: 加算なし+コンボリセット
- 譜面終了検出 → `ResultView` へ SwiftUI 側で遷移
- ヘッダの終了ボタン → 中断

### Phase 6(仕上げ)
- タップ位置の波紋エフェクト
- 太鼓の一瞬光る演出
- 判定文字(良/可/不可)の表示アニメーション
- 判定窓の最終調整(試遊フィードバック反映)

**Phase**: Phase 1-2, 6

---

## 7. リザルト画面

**何を**: プレイ終了後のスコア表示、リトライ/戻る導線。

**技術**: SwiftUI

**粒度**:
- 総合スコア(大表示)
- 良 / 可 / 不可 / 最大コンボの内訳
- 星評価(5 段階、算出式は Phase 2 で仮決め)
- 「もう一度」→ `PlayView` に再突入
- 「一覧に戻る」→ `ChartLibraryView` へ
- スコアはメモリ内のみ、ローカル保存なし(仕様上)

**Phase**: Phase 2

---

## 8. ライブラリ画面(保存済み譜面一覧)

**何を**: 端末ローカル譜面の一覧・選択・削除。

**技術**: SwiftUI(`List`, `NavigationLink`, `.swipeActions`)、`FileManager`

**粒度**:
- `ChartStorage.list()` の結果を表示
- カード: 譜面名 / 地域 / 収録時間 / 作成日
- タップ → `PlayView` に遷移
- 左スワイプで削除
- 空状態: 「まだ譜面がありません」+ 「IDで入手」「録音する」導線
- ヘッダの「+ IDで入手」→ `ChartDownloadView` へ
- 並び順: 作成日 降順 固定
- NEW ハイライト: 直前 DL / 録音の譜面をカラーバッジ表示(セッション内で保持)

**Phase**: Phase 3(基本)/ Phase 6(リネーム機能追加)

---

## 9. 録音シーン

**何を**: 太鼓を左右分割表示し、指導者のタップ位置から譜面を生成する。

**技術**: SpriteKit(`SKScene`, `CACurrentMediaTime`)、AudioEngine、Haptics

**粒度**:
- `RecordingScene: SKScene`
- 太鼓を中央で左右分割表示(録音時のみ)
- タップ位置 → `type` を判定:
  - 太鼓左外 → `ka_l`
  - 太鼓内 左半分 → `don_l`
  - 太鼓内 右半分 → `don_r`
  - 太鼓右外 → `ka_r`
- 開始時刻(`CACurrentMediaTime()`)からの経過ミリ秒を記録
- 打点時に効果音 + 触覚(プレイ時と同じ)
- 直前打点をログ表示(視覚確認用)
- 停止ボタン → タップ列を `Chart`(id/name/region 空)に組み立てて `ChartEditView` へ

**Phase**: Phase 3

---

## 10. 譜面編集画面

**何を**: 録音直後の譜面メタデータ入力、試遊、保存、公開への導線。

**技術**: SwiftUI(`Form`, `TextField`, `List`)、`FileManager`

**粒度**:
- 譜面名 / 地域 の TextField
- 譜面サマリ(時間・ノーツ数・状態)
- ノーツリスト(時系列、type バッジ、× で個別削除)
- 「試遊」→ ドラフト譜面を `PlayView` に渡す、戻り先はこの画面
- 「保存」→ ローカル ID(UUID)を生成して `ChartStorage.save()` → ライブラリへ
- 「公開」→ `PublishView` へ(ドラフトを引き継ぐ)
- 「破棄」→ タイトルへ、ドラフト削除
- MVP ではノーツ位置の微修正 UI は実装しない(削除のみ)

**Phase**: Phase 3(基本)/ Phase 4(公開への接続)

---

## 11. 譜面検索 / DL 画面

**何を**: ID を入力して譜面をサーバーから取得し、ローカル保存する。

**技術**: SwiftUI、URLSession(async/await)、`JSONDecoder`

**粒度**:
- ID 入力欄(等幅フォント推奨)
- バリデーション:
  - 小英字・数字・ハイフン
  - 3〜64 文字
  - 実行前に UI で先に検証
- 既存 ID なら DL スキップ(ローカルヒット表示)
- `APIClient.fetchChart(id:)` 呼び出し
- 成功 → 検証(JSON パース) → ローカル保存 → ライブラリ画面へ戻る(NEW ハイライト)
- エラー:
  - 404 → 「この譜面IDは見つかりません」
  - ネットワークエラー → 「通信に失敗しました」
- QR スキャンは MVP に含めない

**Phase**: Phase 4

---

## 12. 公開画面(IAP + アップロード)

**何を**: 譜面をサーバーにアップロードする(要課金)。

**技術**: SwiftUI、StoreKit 2、URLSession、APIClient

**粒度**:

### フロー
1. 譜面サマリ表示
2. 公開 ID 入力(バリデーション)
3. 「ID確認」→ `APIClient.checkID(id:)` を呼ぶ → 200/409 で状態表示
4. 「公開する ¥1,000」→ `StoreKitManager.purchase()` を呼ぶ
5. StoreKit 決済ダイアログ(Apple 標準)
6. 購入成功 → JWS を取り出す → `APIClient.publish(jws:, chart:)`
7. Cloud Run 側で処理 → レスポンスの `id` を受け取り、`transaction.finish()`
8. 完了エリアで発行 ID をコピー可能に表示

### 実装ポイント
- 決済とアップロードを 1 セットのトランザクションとして扱う
- publish 失敗時のリカバリ: JWS を保持して再試行可能に(端末側で「未確定 publish」状態のキュー)
- ネットワーク切断時の扱い: 再送 or 手動リトライ UI

**Phase**: Phase 4(バックエンド接続)/ Phase 5(IAP 統合)

---

## 13. タイトル / メニュー画面

**何を**: アプリ起動時のエントリ画面。

**技術**: SwiftUI

**粒度**:
- タイトル・タグライン・装飾
- 「プレイ」CTA(朱色、目立たせる)
- 「録音する」CTA(パネル色、控えめ)
- 「譜面をIDで入手」サブリンク
- 遷移: `NavigationStack` 経由で各画面へ

**Phase**: Phase 6(MVP 内では Phase 1-3 は各画面を直接起動しても可)

---

## 14. API クライアント

**何を**: バックエンドとの通信レイヤー。

**技術**: URLSession(async/await)、`Codable`

**粒度**:
- `APIClient` クラス(単一責務)
- エンドポイント定義:
  - `fetchChart(id: String) async throws -> Chart` — GCS の GET
  - `checkID(id: String) async throws -> Bool` — Cloud Run の `/check-id`
  - `publish(jws: String, chart: Chart) async throws -> String` — Cloud Run の `/publish`、返り値は確定 ID
- エラー型: `APIError`(`.notFound`, `.conflict`, `.network`, `.decoding`, `.server`)
- URL は `AppConfig` から取得(環境切り替え)
- タイムアウト: 30 秒
- リトライは自動化しない(ユーザーが再試行するモデル)

**Phase**: Phase 4

---

## 15. StoreKit 2 統合

**何を**: 譜面公開時の課金処理。

**技術**: StoreKit 2(`Product`, `Transaction`, `VerificationResult`)

**粒度**:
- `StoreKitManager`(Observable)
- 起動時に `Product.products(for: ["rhythm.chart.publish.single"])` で商品情報取得
- `purchase() async throws -> String`(JWS を返す)
  - `product.purchase()` 呼び出し
  - `.success(let verification)` 分岐で `verification.jwsRepresentation` を取り出す
  - 検証失敗は throw
- `finish(transaction:)` は publish 成功後に呼ぶ
  - publish 失敗時は finish しない(次回起動時に未処理として再試行できる)
- `StoreKit Configuration File` を `.storekit` として Xcode プロジェクトに追加(ローカル開発用)

**Phase**: Phase 5

---

## 16. 環境設定 / xcconfig

**何を**: Debug / Release で API URL や Bundle ID を切り替える。

**技術**: xcconfig, `Info.plist`, `Bundle.main.object(forInfoDictionaryKey:)`

**粒度**:
- `Debug.xcconfig`:
  - `PRODUCT_BUNDLE_IDENTIFIER = com.zembrem.ohayashidoujou.dev`
  - `API_BASE_URL = https://api-<dev-hash>.asia-northeast1.run.app`(Cloud Run 発行 URL、Terraform 出力から取得)
  - `CHARTS_BASE_URL = https://storage.googleapis.com/ohayashi-charts-dev`
- `Release.xcconfig`:
  - `PRODUCT_BUNDLE_IDENTIFIER = com.zembrem.ohayashidoujou`
  - `API_BASE_URL = https://api-<prod-hash>.asia-northeast1.run.app`
  - `CHARTS_BASE_URL = https://storage.googleapis.com/ohayashi-charts-prod`

**独自ドメイン不採用**: 本プロジェクトはドメインを取得しない方針(`backend.md` §11 / `others.md` §6 参照)。URL は Cloud Run と GCS が自動発行するものをそのまま使う。
- `Info.plist` に `$(API_BASE_URL)` 経由で埋め込み
- `AppConfig` 静的 struct で `Bundle.main` から読み出す

**Phase**: Phase 4

---

## 17. リソース

**何を**: WAV、アイコン、色パレット、スプラッシュ等の素材。

**技術**: Xcode Assets Catalog, LaunchScreen storyboard

**粒度**:
- Phase 1: WAV 2 種(ドン / カッ) — フリー素材で開始
- Phase 6-7:
  - アプリアイコン(1024px + 自動生成分)
  - スプラッシュ(和柄 + タイトル)
  - カラーパレット(朱・金・黒・クリーム)を Assets 化
  - 効果音の差し替え(祭り運用時に最終決定)

**Phase**: Phase 1 / Phase 6-7

---

## 18. テスト

**何を**: 主要ロジックのユニットテストと、実機での UI 確認。

**技術**: Swift Testing(Xcode 26+ 推奨、`@Test` マクロ)/ XCTest

**粒度**:

### ユニットテスト対象
- `Chart` の Codable 往復
- スコア計算ロジック(良/可/不可 × コンボ)
- ゾーン判定(座標 → `NoteType`)
- タイミング判定(ms 差 → 判定)
- API レスポンスのパース

### UI テスト
- MVP では最小限
- タイトル → プレイ → リザルト のスモークテストのみ

### StoreKit テスト
- StoreKit Configuration File を使ったユニットテスト
- 成功 / キャンセル / エラーの各パス

### 実機手動テスト
- Phase 完了ごとに実機で通し確認
- 祭り運用直前に長時間連続プレイテスト

**Phase**: Phase 全般(継続的)

---

## 19. アクセシビリティ / 子供向け配慮

**何を**: 子供が触ってすぐ使える UI 配慮。

**技術**: SwiftUI Accessibility, DynamicType

**粒度**:
- タップ領域を十分大きく(最低 44pt)
- 主要ボタンは色 + テキスト + アイコンの3要素で区別可能に
- 大きなスコア表示・分かりやすい判定表示
- サウンドと触覚の同時発火で「叩いた感」を強調
- MVP では VoiceOver 対応は最小限(祭り運用でスクリーンリーダー要件は薄い)

**Phase**: Phase 6-7

---

## 20. ビルド設定 / CI

**何を**: ローカルビルド設定と、将来の CI 化。

**技術**: Xcode, GitHub Actions(将来)

**粒度**:
- MVP: ローカルビルドのみ、Archive → TestFlight は手動
- Phase 7 以降:
  - GitHub Actions で PR ごとにビルド + テスト
  - fastlane でリリースビルド自動化(検討)

**Phase**: Phase 7(将来)

---

## 21. Phase 対応マトリクス

| Phase | 実装項目(節番号) |
|---|---|
| Phase 1 | 1, 2, 3(Chart/Note), 4, 5, 6(静的+単ノーツ) |
| Phase 2 | 6(譜面再生), 7 |
| Phase 3 | 3(ChartStorage), 8, 9, 10(基本) |
| Phase 4 | 10(公開接続), 11, 12(バックエンド接続), 14, 16 |
| Phase 5 | 12(IAP), 15 |
| Phase 6 | 6(エフェクト), 13, 17(素材), 19 |
| Phase 7 | 17(最終), 18(実機QA), 20(CI) |
