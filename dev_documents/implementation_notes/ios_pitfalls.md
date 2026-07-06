# iOS 実装の落とし穴 — 気をつけること

**位置付け**: iOS アプリの実装で遭遇しがちな Bug・レイテンシ・リソースリークの落とし穴。特に SpriteKit + AVAudioEngine + StoreKit 2 の組み合わせで起きやすい問題を先取り。

**関連**:
- 実装手順: `dev_documents/implementation_plan/ios.md`
- 各画面設計: `dev_documents/screens/`
- 課金: `dev_documents/implementation_notes/iap_and_legal.md`

---

## 1. AVAudioEngine のライフサイクル

**問題**:
- アプリのバックグラウンド遷移で `AVAudioEngine` が停止することがある
- Route change(イヤホン抜き差し)、interruption(電話着信)で `AVAudioEngineConfigurationChange` 通知が飛ぶ
- 気付かず放置するとフォアグラウンド復帰時に音が鳴らない

**対策**:
- `NotificationCenter` で `.AVAudioEngineConfigurationChange` を購読
- 通知受信時に `engine.start()` を再実行
- `AVAudioSession.interruptionNotification` も購読(電話・Siri)

---

## 2. AVAudioSession のカテゴリ

**問題**:
- カテゴリ設定を間違うと BGM アプリを止めてしまう、音が出ない、無音モードで消える等の症状
- 特に子供が「マナーモードで持ってきた iPhone」で無音になるリスク

**対策**:
- カテゴリ: `.playback` を選択(マナーモードでも鳴る)
- オプション: `.mixWithOthers` を付ける(他アプリの音を止めない)
- 起動時に一度設定、`AVAudioSession.sharedInstance().setActive(true)`

---

## 3. 効果音の同時発火 / 連打

**問題**:
- 単一の `AVAudioPlayerNode` に `scheduleBuffer` を連続して呼ぶと、直前の音を切って新しい音を再生する
- 連打時に「最後の 1 音しか聞こえない」現象

**対策**:
- 同 type について複数(3-5個)の `AVAudioPlayerNode` をプール
- Round-robin で使い回す
- または `AVAudioSourceNode` で低レベル制御(複雑度は上がる)

---

## 4. CACurrentMediaTime vs Date

**問題**:
- 録音時のタイムスタンプに `Date()` を使うと、NTP 補正で時計が戻った時にズレる
- プレイ時の時間経過管理でも同様

**対策**:
- 時間差の測定は **`CACurrentMediaTime()`**(単調増加、システム時計変更の影響なし)
- 絶対時刻(created_at 等)は `ISO8601DateFormatter` + `Date()`

---

## 5. SpriteKit のフレームレート

**問題**:
- 判定処理をフレーム更新に依存させると、ProMotion(120Hz)と 60Hz 端末で挙動が変わる
- ノーツの位置計算をフレーム数で管理すると倍速表示になる

**対策**:
- 判定・座標計算は **時間ベース**(秒/ミリ秒)で行う
- `SKScene.update(_ currentTime:)` の `currentTime` を基準に
- `preferredFramesPerSecond` は自動でリフレッシュレートに合わせる(明示指定不要)

---

## 6. SwiftUI と SpriteKit のブリッジ

**問題**:
- `SpriteView` の中で SKScene が SwiftUI 側の状態変更を検知できない
- 逆に SpriteScene から SwiftUI 側に「譜面終了」を通知するのが難しい

**対策**:
- SKScene 側にコールバック用のクロージャを持たせる:
  ```swift
  class PlayScene: SKScene {
      var onComplete: ((ScoreResult) -> Void)?
  }
  ```
- SwiftUI 側で SKScene インスタンスを `@StateObject` の中に保持し、生成時にコールバックを設定
- Combine の PassthroughSubject でも代替可

---

## 7. Swift 6 の Concurrency(Sendable)

**問題**:
- Swift 6.2 は Strict Concurrency Checking がデフォルト
- `Chart` / `Note` などのモデルを別スレッドに渡す時、`Sendable` でないとエラー
- Actor 境界を跨ぐ呼び出しで `await` を忘れやすい

**対策**:
- モデルは全て `struct` + `Codable, Sendable` に
- `SwiftUI View` は暗黙的に `@MainActor`、`URLSession` は非同期 → `Task { await ... }` で橋渡し
- `StoreKit 2` は元々 async/await ネイティブ
- 開発初期に一度 `-strict-concurrency=complete` でビルドして問題箇所を洗い出す

---

## 8. ローカルファイルの保存先

**問題**:
- `Documents/` 直下は `UIFileSharingEnabled = YES` にすると Files アプリから見えてしまう
- MVP では意図的に「アプリ内からのみ参照可能」設計

**対策**:
- 保存先は **`Application Support/charts/`**(サブディレクトリ)
- `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`
- 初回起動時にサブディレクトリを `createDirectory(withIntermediateDirectories: true)` で作成
- Info.plist の `UIFileSharingEnabled = NO` / `LSSupportsOpeningDocumentsInPlace = NO` を確認

---

## 9. JSON パース失敗時の扱い

**問題**:
- サーバーから壊れた JSON、あるいは互換性のない形式のデータが来る可能性
- ローカルファイルもファイルシステムのクラッシュで破損することがある

**対策**:
- `JSONDecoder` の失敗時にファイルを削除しない
- 破損ファイルは `Application Support/quarantine/` に退避
- ユーザーには「読み込めない譜面があります」の穏やかな表示
- ログには詳細(どのフィールドが原因か)を Cloud Logging に送信できると理想

---

## 10. StoreKit 2 の Transaction.finish() タイミング

**問題**:
- 課金成功後、`transaction.finish()` を **公開処理(publish)前に呼ぶ**と、publish 失敗時に「¥1,000 払ったが公開されない」状態が確定してしまう
- StoreKit は finish されていないトランザクションを次回起動時に `Transaction.updates` で再通知するので、再送チャンスがある

**対策**:
- **必ず publish 成功後にのみ `transaction.finish()` を呼ぶ**
- publish 失敗時は finish しない
- アプリ起動時に `Transaction.updates` を購読、未 finish のトランザクションを検知 → 対応するドラフト譜面と紐付けて再送提案

---

## 11. StoreKit Configuration File の落とし穴

**問題**:
- `.storekit` ファイルを Xcode プロジェクトに追加しても、Scheme 設定で紐付けないと使われない
- 「なぜかテスト環境で商品が取得できない」の典型パターン

**対策**:
- Xcode → Scheme → Run → Options → StoreKit Configuration で `.storekit` を指定
- CI で自動テストする場合は Scheme を Git 管理下に入れる(`.xcscheme` の共有設定)

---

## 12. iPhone のセーフエリア / ノッチ

**問題**:
- 太鼓を画面下部に配置すると、iPhone のホームインジケーター領域と重なる
- Recording 画面 / Play 画面で特に注意

**対策**:
- SwiftUI: `.ignoresSafeArea(.container, edges: .bottom)` を慎重に使う
- SpriteKit 内: `view.safeAreaInsets` で下端の余白を取得し、シーンの座標を調整
- 判定ゾーンの座標定義は Safe Area を考慮

---

## 13. リソースリーク

**問題**:
- 画面遷移で SKScene が deinit されない場合、SKAction・SKNode が残り続けて音・振動が鳴り続ける
- クロージャ内の `self` キャプチャで retain cycle
- Combine のサブスクリプション未 cancel

**対策**:
- SKScene の `willMove(from:)` で `removeAllActions()` `removeAllChildren()`
- クロージャは `[weak self]` を明示
- Combine の `cancellables` は `AnyCancellable` の Set に格納して deinit で破棄
- 開発中は Instruments の Allocation / Leaks で定期チェック

---

## 14. 画面回転の抑制

**問題**:
- Info.plist で Portrait を指定しても、iPad などで横向きに回転してしまう場合がある

**対策**:
- Info.plist:
  - `UISupportedInterfaceOrientations` = Portrait のみ
  - `UISupportedInterfaceOrientations~ipad` は指定しない(iPad 非対応)
- App の Target Settings で iPad を Deployment Info からチェック外す

---

## 15. ダークモード / ライトモード

**問題**:
- MVP は独自配色の「和柄+朱+金+黒」で固定したい
- OS のダークモード切替で配色が意図せず変わる

**対策**:
- SwiftUI: `.preferredColorScheme(.dark)` をルートビューに指定
- Assets Catalog の Color はすべて Any Appearance で固定色
- テストは Light / Dark 両モードで確認

---

## 16. Bundle Resource の読み込み失敗

**問題**:
- `Bundle.main.url(forResource: "don", withExtension: "wav")` が nil を返す
- ファイル名の typo、Target Membership 未設定、`.xcassets` 内のバグなど原因は多岐

**対策**:
- 起動時に必要な効果音を一括ロード + 検証
- 失敗時は開発中は `fatalError`、本番は「アプリを再インストールしてください」の穏やかな表示
- Xcode の Build Phases → Copy Bundle Resources に対象ファイルが含まれているか確認

---

## 17. スリープ抑制(idleTimerDisabled)

**問題**:
- プレイ中に自動スリープに入って画面が消える
- 逆に、常時抑制するとバッテリー消耗が激しい

**対策**:
- プレイ中のみ `UIApplication.shared.isIdleTimerDisabled = true`
- プレイ終了・タイトル遷移で `false` に戻す
- 会場運用時は Guided Access に依拠する選択肢もある

---

## 18. ProMotion(120Hz)ディスプレイの対応

**問題**:
- iPhone 13 Pro 以降は 120Hz、それ以外は 60Hz
- SpriteKit は自動対応するが、CADisplayLink を直接使う場合は明示設定必要

**対策**:
- MVP は SpriteKit 内の `SKView.preferredFramesPerSecond` を指定しない(自動)
- 判定・座標は時間ベースなので、リフレッシュレートに関わらず同じ挙動になる

---

## 19. Xcode 26 / Swift 6.2 の新機能への対応

**問題**:
- Swift Testing(新しいテストフレームワーク)は XCTest とは書き方が異なる
- SwiftUI の Observation フレームワークで `@Observable` マクロが使える

**対策**:
- MVP は Swift Testing を推奨(`@Test` / `#expect`)
- StoreKitManager / ChartStorage 等の状態オブジェクトは `@Observable` マクロで簡略化

---

## 20. TestFlight ビルドのプロビジョニング

**問題**:
- Bundle ID の Debug/Release 分離を組んでいると、TestFlight 用に Release ビルドしたつもりが Debug になっていて Sandbox 決済にならない

**対策**:
- Archive 時は必ず Release configuration
- Scheme の Archive アクションで Configuration を確認
- App Store Connect 上で Bundle ID を確認(`.dev` サフィックスが付いていないこと)

---

## 21. マルチタッチ(両手同時打)の落とし穴

**問題**:
- `UIView.isMultipleTouchEnabled` は **デフォルトで false**、明示的に true にしないと 2 タッチ目以降が届かない
- `SKView` にも同じ設定が必要(SpriteView 経由の SKScene も影響を受ける)
- `touchesBegan(_:with:)` は「同時」でも複数タッチが 1 コールで届くとは限らない(2 コールに分かれる)
- 「50ms 以内の 2 タッチを同時と見なす」判定を自前で実装する必要がある

**対策**:
- `PlayScene` / `RecordingScene` の初期化時に `view?.isMultipleTouchEnabled = true`
- タッチイベントを**時系列バッファ**(直近 100ms)に蓄積、`touchesBegan` のたびに走査してペアを検出
- `UITouch` インスタンスの同一性は `ObjectIdentifier` で追跡(`==` 演算子は Hashable ではない)
- Palm rejection(手のひら誤検出)対策として、太鼓ゾーン外のタッチは無視

---

## 22. ホールドノート(長押し)の落とし穴

**問題**:
- **標準の `UILongPressGestureRecognizer` は使わない**:
  - 内部で 500ms 待ってから発火する遅延方式のため、リアルタイム判定に不向き
  - タッチ開始時刻の記録・継続中のエフェクト表示ができない
- 各タッチの `began` → `moved` → `ended` を自前で追跡し、時刻差を測る必要がある
- `UITouch` インスタンスは移動中も同一だが、`touchesCancelled` で消える可能性があることを忘れると誤判定

**対策**:
- `touchesBegan` で `[ObjectIdentifier: TouchInfo]` の辞書に開始時刻・開始座標を記録
- `touchesEnded` で辞書を引いて継続時間を計算、500ms を閾値に単発/ホールドを分岐
- `touchesCancelled` でも辞書から削除(電話着信・システムアラート対策)
- ホールド中の視覚エフェクト: `SKAction.repeatForever` で振動アニメを継続、`touchesEnded` で停止
- ホールド尾判定は「頭タイミング + `duration` 前後 ±150ms でリリース検出」
- `CACurrentMediaTime()` で計測(`Date` は NTP 補正で戻ることがあるため不可)

---

## 実装チェックリスト

- [ ] AVAudioEngine の interruption / configurationChange 対応
- [ ] AVAudioSession は `.playback` + `.mixWithOthers`
- [ ] 効果音は Round-robin の複数プレイヤープール
- [ ] 時間管理は `CACurrentMediaTime()`、日時記録は `Date()`
- [ ] SpriteKit の判定は時間ベース(フレーム数依存しない)
- [ ] SKScene → SwiftUI のコールバック設計
- [ ] Swift 6.2 Strict Concurrency で `Sendable` 準拠
- [ ] 保存先は Application Support/charts/
- [ ] JSON パース失敗時はファイル退避
- [ ] StoreKit Transaction.finish() は publish 成功後のみ
- [ ] StoreKit Configuration File の Scheme 紐付け確認
- [ ] Safe Area を考慮した座標計算
- [ ] リソースリーク検査(Instruments)
- [ ] Portrait 固定 + iPad Target 外し
- [ ] ダークモード対応(独自配色固定)
- [ ] Bundle Resource の起動時検証
- [ ] プレイ中のみ isIdleTimerDisabled
- [ ] ProMotion 対応(SpriteKit 自動)
- [ ] TestFlight ビルドの Configuration 確認
- [ ] `isMultipleTouchEnabled = true`(PlayScene / RecordingScene)
- [ ] タッチイベントを時系列バッファで蓄積、50ms 以内のペアを `don_both` として検出
- [ ] ホールドは `UILongPressGestureRecognizer` を使わず自前で `began`/`ended` 差分計測
- [ ] `touchesCancelled` でタッチ辞書を確実にクリーンアップ
- [ ] ホールド尾判定 ±150ms、途中離しの減点実装
