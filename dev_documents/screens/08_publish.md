# 公開画面(IAP + アップロード)

## 概要

譜面をサーバーにアップロードして他端末で DL 可能にする画面。
本アプリで **唯一の課金ポイント**(Consumable ¥1,000 / 曲、即時消費)。
資金決済法上の前払式支払手段に該当しない設計(購入と役務提供が同時)。

## 主要 UI 要素

- 譜面情報の確認(名前・地域・収録時間、編集画面から引き継ぎ)
- **公開 ID 入力欄**
  - 制作者が自由に決める(例: `shimoda-2026-irihayashi`)
  - 入力制約: 小英字・数字・ハイフンのみ、3〜64 文字
  - リアルタイム文字種チェック
- ID 事前確認ボタン(「このIDが使えるか確認」)
- 公開実行ボタン(IAP ダイアログを起動)
- 公開完了エリア(成功時)
  - 発行された ID を大きく表示
  - コピー / QR 表示(QR は将来対応)
  - 「地域内で告知してください」の案内
- キャンセル / 戻る

## ユーザーができること

- 公開 ID の入力
- ID の重複事前確認(課金前、無料)
- IAP 決済 → 公開実行
- 発行 ID のコピー
- (将来)QR 表示

## 完全フロー

```
[譜面編集画面] → 「公開」タップ
   ↓
[公開画面] 譜面名・地域確認 + ID入力
   ↓
[ID事前確認] POST /check-id { id }
   ├ 使用済み → エラー表示(課金前にここで止める)
   └ 利用可能 → 次へ進めるように
        ↓
[公開ボタンタップ]
   ↓
[IAP決済ダイアログ] ¥1,000
   ├ キャンセル → 何も起きない(ローカル譜面は残る、再試行可)
   └ 購入成功
        ↓
        POST /publish { signed_transaction (JWS), chart_json }
        ↓
   [Cloud Run 側処理]
   ├ Apple App Store Server API で JWS 検証
   ├ Firestore で transaction_id 重複チェック(未使用か)
   ├ Firestore で chart_id 重複チェック(競合発生時はエラー、サポート対応)
   ├ GCS に {id}.json 保存
   └ Firestore に台帳記録
        ↓
   [レスポンス] { id: "shimoda-2026-irihayashi" }
        ↓
[公開完了エリア表示]
   ID を大きく表示、コピー・QR 導線
```

## 必要な API / 通信

### 1. ID 事前確認

```
POST https://api-<hash>.asia-northeast1.run.app/check-id
Content-Type: application/json

{ "id": "shimoda-2026-irihayashi" }
```
※ URL は Cloud Run 発行のデフォルト、独自ドメイン不採用(dev / prod で hash が異なる)

レスポンス:
- `200 OK` — 利用可能
- `409 Conflict` — 使用済み

**目的**: 課金完了後に ID 重複エラーで決済損失を起こさないための事前確認。

### 2. 譜面公開

```
POST https://api-<hash>.asia-northeast1.run.app/publish
Content-Type: application/json

{
  "signed_transaction": "<JWS from StoreKit 2>",
  "chart_json": { ... 譜面全体 ... }
}
```

レスポンス:
- `200 OK` — `{ "id": "..." }`
- `400 Bad Request` — 譜面 JSON 不正
- `402 Payment Required` — トランザクション検証失敗
- `409 Conflict` — ID 競合(check-id を通ってもレース発生の可能性、サポート対応)
- `5xx` — サーバーエラー

### 3. IAP(StoreKit 2)

- プロダクト ID: `rhythm.chart.publish.single`(仮)
- タイプ: **Consumable**
- 価格: **¥1,000 / 曲**
- 課金タイミング: 公開ボタンを押した瞬間に課金 → 成功したら即 publish

## 周辺技術

- **StoreKit 2**
  - `Product.products(for:)` で商品情報取得
  - `product.purchase()` で決済実行
  - `Transaction` から JWS (`jwsRepresentation`) を取り出してバックエンドへ送信
  - 決済完了後は `transaction.finish()`
- **URLSession** (async/await) — Cloud Run API 呼び出し
- **JSONEncoder / JSONDecoder**
- SwiftUI(フォーム + 状態管理)

## セキュリティ / 課金設計

- サーバー側で JWS 検証を必須(Apple App Store Server API)
- Firestore で `transaction_id` の重複チェック → 二重使用防止
- ID 競合発生時は原則サポート対応(レアケース、check-id で事前に大半を防ぐ)
- **更新公開機能は持たない**(取り下げ→再公開で課金回避を防ぐため)

## 遷移元 / 遷移先

- **遷移元**: 譜面編集画面(07)から「公開」
- **遷移先**:
  - 公開成功 → 完了エリア表示 → 「一覧に戻る」で保存済み譜面一覧(02)
  - キャンセル / 失敗 → 譜面編集画面(07)に戻る

## 対応 Phase

- Phase 4(バックエンド接続、`/check-id` 実装)
- Phase 5(IAP、StoreKit 2 統合、`/publish` の JWS 検証接続)

## メモ

- DEBUG ビルドではバックエンド URL を開発環境に振り向ける(IAP はサンドボックスでOK)
- サンドボックス Apple ID の準備は §8 未決事項
- 発行 ID の告知手段(口頭・ポスター・QR 等)はアプリ外の運用
