import SpriteKit
import Foundation

/// プレイ画面の SpriteKit シーン。
///
/// 完成版:
/// - `Chart` を受け取り、`notes` を時系列でスケジュール
/// - 3 ゾーン判定 + タイミング判定(良/可/不可)
/// - **両手同時打**(`don_both`)判定: 中央左右半分に 50ms 以内の 2 タッチで成立
/// - **ホールドノート**(`duration > 0`)判定: 頭 + 尾 の 2 段、尾は ±150ms
/// - スコア / コンボを計算し、コールバックで SwiftUI 側へ通知
/// - 譜面終了検出 → 完了コールバック
///
/// 和風モダン UI(2026-07 確定):
/// - 太鼓の達人風の太鼓(タン縁 + クリーム皮 + 黒鋲 40 個)
/// - 判定ライン = 注連縄(金の帯)+ 紙垂
/// - レーン分けは木の柱(wood-dark 2px)
/// - ノーツはフラット、文字なし、朱 #FD4720 / 青 #44C2C1
@MainActor
final class PlayScene: SKScene {
  // MARK: - Layout constants
  private let hitLineY: CGFloat = 220
  private let laneCount: Int = 4
  private let fallDuration: TimeInterval = 2.5
  private let drumRadius: CGFloat = 140
  private let drumCenterY: CGFloat = -20

  // MARK: - Judgment constants
  private static let goodWindowMs: Int = 200
  private static let okWindowMs: Int = 400
  private static let holdTailToleranceMs: Int = 150
  private static let bothPairWindowSec: TimeInterval = 0.05
  private static let missGraceSec: TimeInterval = 0.5

  // MARK: - Mode

  /// シーンの動作モード。
  /// - interactive: 通常プレイ(タッチ判定・スコア加算あり)
  /// - autoPlay: 自動再生プレビュー(タッチ判定なし、譜面通りに音のみ再生)
  enum Mode {
    case interactive
    case autoPlay
  }
  var mode: Mode = .interactive

  // MARK: - Public API
  var onScoreChanged: (@MainActor (ScoreState) -> Void)?
  var onFinished: (@MainActor (ScoreState) -> Void)?

  // MARK: - State
  private var chart: Chart?
  private(set) var score = ScoreState()
  private var startTime: TimeInterval = 0
  private var pendingNotes: [PendingNote] = []
  private var judgeLabel: SKLabelNode?

  private var recentTouches: [RecentTouch] = []
  private var activeHolds: [ObjectIdentifier: ActiveHold] = [:]

  /// don_both が近時刻に pending だが相方がまだ届いていない中央タッチを
  /// bothPairWindowSec 待って再判定するためのバッファ。
  /// 待機中に相方が届いて don_both として消費されれば isConsumed 判定でスキップ、
  /// 届かなければ judgeSingle に落ちる(orphan タップ扱い)。
  private var deferredCenterTaps: [DeferredCenterTap] = []
  private struct DeferredCenterTap {
    let id: ObjectIdentifier
    let tapTime: TimeInterval
    let touch: UITouch
  }

  private struct PendingNote {
    let id: UUID
    let targetTime: TimeInterval
    let type: NoteType
    let durationSec: TimeInterval
    weak var node: SKShapeNode?
    weak var tail: SKShapeNode?
    /// 元 chart.notes 配列でのインデックス。編集モード時の adjustments 適用に使う。
    let originalIndex: Int
  }

  private enum CenterHalf { case left, right }

  private struct RecentTouch {
    let id: ObjectIdentifier
    let time: TimeInterval
    let zone: NoteType.Zone
    let centerHalf: CenterHalf?
    var consumed: Bool
  }

  private struct ActiveHold {
    let noteId: UUID
    let type: NoteType
    let expectedReleaseTime: TimeInterval
    weak var headNode: SKShapeNode?
    weak var tailNode: SKShapeNode?
    let partnerTouchId: ObjectIdentifier?
  }

  // MARK: - Wafuu Palette (SKColor)
  private static let wDon      = SKColor(red: 0xFD/255, green: 0x47/255, blue: 0x20/255, alpha: 1)
  private static let wDonDim   = SKColor(red: 0xB0/255, green: 0x30/255, blue: 0x0F/255, alpha: 1)
  private static let wKa       = SKColor(red: 0x44/255, green: 0xC2/255, blue: 0xC1/255, alpha: 1)
  private static let wKaDim    = SKColor(red: 0x26/255, green: 0x87/255, blue: 0x86/255, alpha: 1)
  private static let wGold     = SKColor(red: 0xB8/255, green: 0x93/255, blue: 0x5A/255, alpha: 1)
  private static let wGoldHi   = SKColor(red: 0xF0/255, green: 0xD8/255, blue: 0x96/255, alpha: 1)
  private static let wSilver   = SKColor(red: 0xC9/255, green: 0xD4/255, blue: 0xDC/255, alpha: 1)
  private static let wSumi     = SKColor(red: 0x2A/255, green: 0x26/255, blue: 0x20/255, alpha: 1)
  private static let wSumiSoft = SKColor(red: 0x5C/255, green: 0x52/255, blue: 0x48/255, alpha: 1)
  private static let wWoodMid  = SKColor(red: 0xC8/255, green: 0xA9/255, blue: 0x76/255, alpha: 1)
  private static let wWoodDark = SKColor(red: 0x8B/255, green: 0x6A/255, blue: 0x3C/255, alpha: 1)
  private static let wWoodDeep = SKColor(red: 0x5C/255, green: 0x42/255, blue: 0x25/255, alpha: 1)
  private static let wWoodSumi = SKColor(red: 0x2B/255, green: 0x1A/255, blue: 0x0E/255, alpha: 1)
  private static let wSkin     = SKColor(red: 0xF5/255, green: 0xED/255, blue: 0xD8/255, alpha: 1)
  private static let wPaper    = SKColor(red: 0xFD/255, green: 0xF6/255, blue: 0xE3/255, alpha: 1)
  private static let wMoss     = SKColor(red: 0x4D/255, green: 0x6C/255, blue: 0x3E/255, alpha: 1)

  // MARK: - Public entry

  func load(chart: Chart) {
    loadInternal(chart: chart, atSec: 0)
    // 新規ロード時は再生状態にリセット
    isEditingPaused = false
    self.speed = 1
    pausedAtSec = nil
    onScoreChanged?(score)
  }

  /// 現在再生中の chart を、指定時刻から再度ロード(seek 用途)。
  /// 再生/停止状態は維持する。
  func seek(toSec: TimeInterval) {
    guard let chart = self.chart else { return }
    let clamped = max(0, min(toSec, TimeInterval(chart.durationMs) / 1000.0))
    loadInternal(chart: chart, atSec: clamped)
    if isEditingPaused {
      pausedAtSec = clamped
    }
  }

  /// 内部ロード実装。scene の状態を一旦全部クリアして atSec の時点から
  /// スケジューリングし直す。isEditingPaused と speed には手を付けない。
  private func loadInternal(chart: Chart, atSec offsetSec: TimeInterval) {
    self.chart = chart
    self.score = ScoreState()
    for pending in pendingNotes {
      pending.node?.parent?.removeFromParent()
    }
    pendingNotes.removeAll()
    recentTouches.removeAll()
    activeHolds.removeAll()
    deferredCenterTaps.removeAll()
    hideAdjustmentEditor()
    removeAllActions()

    // 再生時間トラッキング用の base をリセット
    basePlaybackSec = offsetSec
    basePlaybackWallTime = CACurrentMediaTime()

    // SKAction の startTime は「offsetSec だけ過去に開始した」と見なす
    startTime = CACurrentMediaTime() - offsetSec
    scheduleNotes(from: chart, offsetSec: offsetSec)
    scheduleFinish(after: TimeInterval(chart.durationMs) / 1000.0 - offsetSec + Self.missGraceSec)

    if mode == .autoPlay {
      scheduleAutoPlayAudio(from: chart, offsetSec: offsetSec)
    }
  }

  /// 自動再生モード時の音の再生スケジュール。
  /// 各ノーツの target 時刻から offsetSec を差し引いた時点で再生。
  /// 既に過去のノーツ(effectiveTargetSec < 0)はスキップする。
  private func scheduleAutoPlayAudio(from chart: Chart, offsetSec: TimeInterval = 0) {
    for note in chart.notes {
      let targetSec = TimeInterval(note.t) / 1000.0 - offsetSec
      guard targetSec >= 0 else { continue }
      let type = note.type
      let wait = SKAction.wait(forDuration: targetSec)
      let play = SKAction.run {
        AudioEngine.shared.play(for: type)
      }
      // ホールドの場合は尾のリリース時刻でもう一発鳴らす選択もあるが、
      // 太鼓の達人でもホールドは頭で 1 発だけなので頭のみ再生する。
      run(SKAction.sequence([wait, play]))
    }
  }

  // MARK: - Pause / Resume(自動再生モード用)

  /// 編集モードでの一時停止フラグ(SKNode.isPaused とは別管理)。
  /// SKNode.isPaused = true にすると環境によってはタッチ配信が止まる
  /// 副作用があるため、scene.speed = 0 で SKAction を止めつつ、
  /// タッチ配信は維持する方針をとる。
  private(set) var isEditingPaused: Bool = false

  // MARK: - Playback time tracking(再生位置を SwiftUI 側に返すため)

  /// 直近ロード / seek の起点となる仮想時刻(秒)。ここから開始して再生。
  private var basePlaybackSec: TimeInterval = 0
  /// 上記 base を設定した wall-clock 時刻(CACurrentMediaTime())。
  private var basePlaybackWallTime: TimeInterval = 0
  /// 一時停止中の再生時刻スナップ。nil = 再生中。
  private var pausedAtSec: TimeInterval? = nil

  /// 現在の仮想再生時刻(秒)。
  func currentPlaybackTimeSec() -> TimeInterval {
    if let paused = pausedAtSec { return paused }
    return basePlaybackSec + (CACurrentMediaTime() - basePlaybackWallTime)
  }

  /// 譜面の総時間(秒)。
  func durationSec() -> TimeInterval {
    guard let chart else { return 0 }
    return TimeInterval(chart.durationMs) / 1000.0
  }

  /// シーン全体を一時停止する(SKAction 進行を止める)。
  /// isPaused は使わず speed = 0 でアクションだけ止め、touchesBegan は
  /// 引き続き配信される状態に保つ(編集タップを受けるため)。
  func pauseGame() {
    guard !isEditingPaused else { return }
    pausedAtSec = currentPlaybackTimeSec()
    isEditingPaused = true
    self.speed = 0
  }

  /// シーン全体を再開する。
  func resumeGame() {
    guard isEditingPaused else { return }
    // 一時停止していた時刻から再開する。base を今の wall-clock に合わせる。
    if let paused = pausedAtSec {
      basePlaybackSec = paused
      basePlaybackWallTime = CACurrentMediaTime()
      pausedAtSec = nil
    }
    hideAdjustmentEditor()
    isEditingPaused = false
    self.speed = 1
  }

  // MARK: - AutoPlay editing mode(停止中のノーツ位置調整)

  /// 現在停止中に選択されているノーツの original index。nil = 未選択。
  private var selectedOriginalIndex: Int? = nil
  /// original index → 累積調整量 (ms)。正 = 後ろにずらす、負 = 前にずらす。
  private var noteAdjustmentsMs: [Int: Int] = [:]
  /// 選択中のノーツに表示する ▲▼ 編集 UI コンテナ。
  private var editorOverlay: SKNode?

  /// ▲▼ ボタンのタップ半径(overlay 原点からの相対座標)。
  private static let arrowButtonRadius: CGFloat = 30
  /// ▲▼ ボタンの縦オフセット(overlay 原点から ±方向)。
  private static let arrowButtonOffsetY: CGFloat = 30

  /// 停止中に PlayView から呼ばれる想定の外部 API。
  /// adjustments 適用済みの Chart を返す。
  func currentAdjustedChart() -> Chart? {
    guard var c = chart else { return nil }
    guard !noteAdjustmentsMs.isEmpty else { return c }
    for (idx, deltaMs) in noteAdjustmentsMs {
      guard idx >= 0 && idx < c.notes.count else { continue }
      let newT = max(0, c.notes[idx].t + deltaMs)
      c.notes[idx].t = newT
    }
    c.notes.sort { $0.t < $1.t }
    return c
  }

  /// 停止中タップの処理。
  /// - 選択済みノーツの ▲▼ 領域なら調整
  /// - ノーツにヒットしたら選択切り替え
  /// - どこにもヒットしなければ選択解除
  private func handleEditingTap(at location: CGPoint) {
    // 1) 既存 overlay 上の ▲▼ タップを優先チェック
    //    SpriteKit の nodes(at:) は SKScene.isPaused = true の状態で
    //    信頼性が低い(タイミングによっては空配列が返る)ため、
    //    距離ベースの判定で確実にヒットさせる。
    if let overlay = editorOverlay {
      let dx = location.x - overlay.position.x
      let dyUp = location.y - (overlay.position.y + Self.arrowButtonOffsetY)
      let distUp = sqrt(dx * dx + dyUp * dyUp)
      if distUp <= Self.arrowButtonRadius {
        adjustSelectedNote(deltaMs: 100)  // +0.1s = 後ろへ
        return
      }
      let dyDown = location.y - (overlay.position.y - Self.arrowButtonOffsetY)
      let distDown = sqrt(dx * dx + dyDown * dyDown)
      if distDown <= Self.arrowButtonRadius {
        adjustSelectedNote(deltaMs: -100) // -0.1s = 前へ
        return
      }
    }

    // 2) ノーツにヒットするか
    if let pick = pickPendingNote(at: location) {
      selectedOriginalIndex = pick.originalIndex
      showAdjustmentEditor(near: pick)
    } else {
      // 3) 何もヒットしなければ解除
      hideAdjustmentEditor()
    }
  }

  private func pickPendingNote(at location: CGPoint) -> PendingNote? {
    // container の position からの距離が短いものを優先
    var best: (PendingNote, CGFloat)? = nil
    for pending in pendingNotes {
      guard pending.originalIndex >= 0 else { continue }
      guard let container = pending.node?.parent else { continue }
      // シーン内に表示されているもののみ(画面外はスキップ)
      let pos = container.position
      guard pos.y > -100 && pos.y < size.height + 100 else { continue }
      let dx = location.x - pos.x
      let dy = location.y - pos.y
      let dist = sqrt(dx * dx + dy * dy)
      // ピックアップ半径 40px(ノーツサイズ + 余裕)
      guard dist < 40 else { continue }
      if best == nil || dist < best!.1 {
        best = (pending, dist)
      }
    }
    return best?.0
  }

  private func showAdjustmentEditor(near pending: PendingNote) {
    hideAdjustmentEditor()
    guard let container = pending.node?.parent else { return }

    let overlay = SKNode()
    overlay.zPosition = 200

    // 位置: 右カッはノーツの左、それ以外は右
    let arrowOffsetX: CGFloat = 50
    let side: CGFloat = (pending.type == .ka_r) ? -1 : 1
    overlay.position = CGPoint(
      x: container.position.x + arrowOffsetX * side,
      y: container.position.y
    )

    // 上ボタン: 0.1s 遅らせる(上向き三角)
    let up = makeArrowButton(pointsUp: true)
    up.position = CGPoint(x: 0, y: Self.arrowButtonOffsetY)
    overlay.addChild(up)

    // 下ボタン: 0.1s 早める(下向き三角)
    let down = makeArrowButton(pointsUp: false)
    down.position = CGPoint(x: 0, y: -Self.arrowButtonOffsetY)
    overlay.addChild(down)

    // 累積調整量ラベル(▲と▼の間、右側 or 左側)
    let deltaMs = noteAdjustmentsMs[pending.originalIndex] ?? 0
    let label = SKLabelNode(fontNamed: "HiraMinProN-W6")
    label.name = "delta_label"
    label.text = formatDelta(deltaMs)
    label.fontSize = 11
    label.fontColor = Self.wSumi
    label.verticalAlignmentMode = .center
    label.horizontalAlignmentMode = (side > 0) ? .left : .right
    // ▲▼の外側にラベルを寄せる
    label.position = CGPoint(x: 24 * side, y: 0)
    overlay.addChild(label)

    // 選択中ノーツを不透明・少し拡大して視認性を上げる
    // (scene.speed = 0 で動作中のため、SKAction ではなく即時値変更で反映)
    container.alpha = 1.0
    container.setScale(1.15)

    addChild(overlay)
    editorOverlay = overlay
  }

  private func hideAdjustmentEditor() {
    // 選択中ノーツの拡大を元に戻す
    if let idx = selectedOriginalIndex {
      for pending in pendingNotes where pending.originalIndex == idx {
        pending.node?.parent?.setScale(1.0)
      }
    }
    editorOverlay?.removeFromParent()
    editorOverlay = nil
    selectedOriginalIndex = nil
  }

  /// ▲ or ▼ の丸ボタンを SKShapeNode で構築。
  /// タップ判定は handleEditingTap 側の距離計算で行うため、name / hitArea は不要。
  private func makeArrowButton(pointsUp: Bool) -> SKNode {
    let container = SKNode()

    // 背景の丸(直径 48)
    let bg = SKShapeNode(circleOfRadius: 24)
    bg.fillColor = Self.wPaper
    bg.strokeColor = Self.wWoodDeep
    bg.lineWidth = 1.5
    bg.zPosition = 0
    container.addChild(bg)

    // 三角形(上向き or 下向き)を SKShapeNode の path で描く
    let triangle = SKShapeNode(path: trianglePath(pointsUp: pointsUp))
    triangle.fillColor = Self.wSumi
    triangle.strokeColor = Self.wSumi
    triangle.lineWidth = 1
    triangle.zPosition = 1
    container.addChild(triangle)

    return container
  }

  /// 中心 (0,0) に配置される、辺 20 の正三角形パス。
  private func trianglePath(pointsUp: Bool) -> CGPath {
    let path = CGMutablePath()
    let side: CGFloat = 20
    let h = side * (sqrt(3) / 2)  // 高さ
    // 重心を (0,0) にする調整オフセット(重心 = 頂点から高さの 1/3 下)
    let offsetY = -h / 3

    if pointsUp {
      path.move(to: CGPoint(x: 0, y: h * 2 / 3 + offsetY))               // 頂点(上)
      path.addLine(to: CGPoint(x: -side / 2, y: -h / 3 + offsetY))       // 左下
      path.addLine(to: CGPoint(x: side / 2, y: -h / 3 + offsetY))        // 右下
    } else {
      path.move(to: CGPoint(x: 0, y: -h * 2 / 3 - offsetY))              // 頂点(下)
      path.addLine(to: CGPoint(x: -side / 2, y: h / 3 - offsetY))        // 左上
      path.addLine(to: CGPoint(x: side / 2, y: h / 3 - offsetY))         // 右上
    }
    path.closeSubpath()
    return path
  }

  private func adjustSelectedNote(deltaMs: Int) {
    guard let idx = selectedOriginalIndex else { return }
    noteAdjustmentsMs[idx, default: 0] += deltaMs

    // ラベル更新
    if let overlay = editorOverlay,
       let label = overlay.childNode(withName: "delta_label") as? SKLabelNode {
      label.text = formatDelta(noteAdjustmentsMs[idx] ?? 0)
    }
  }

  private func formatDelta(_ ms: Int) -> String {
    if ms == 0 { return "±0.0s" }
    let sign = ms > 0 ? "+" : "-"
    let abs = Swift.abs(ms)
    let sec = Double(abs) / 1000.0
    return String(format: "%@%.1fs", sign, sec)
  }

  // MARK: - Scene lifecycle
  override func didMove(to view: SKView) {
    view.isMultipleTouchEnabled = true
    view.ignoresSiblingOrder = true
    view.allowsTransparency = true
    backgroundColor = .clear
    scaleMode = .resizeFill

    layoutBackground()
    layoutLanes()
    layoutHitLine()
    layoutMarkers()
    layoutTatamiEdge()
    layoutDrum()
  }

  override func willMove(from view: SKView) {
    removeAllActions()
    pendingNotes.removeAll()
    recentTouches.removeAll()
    activeHolds.removeAll()
    deferredCenterTaps.removeAll()
  }

  // MARK: - Layout: wafuu elements

  private func layoutBackground() {
    // SwiftUI 側の WafuuBackground が透過表示されるので背景は空。
    // 上部に淡い緑のアクセント帯だけ足す(和風の落ち着き)。
    let accent = SKShapeNode(rect: CGRect(x: 0, y: size.height - 60, width: size.width, height: 60))
    accent.fillColor = Self.wMoss.withAlphaComponent(0.06)
    accent.strokeColor = .clear
    accent.zPosition = -10
    addChild(accent)
  }

  private func layoutLanes() {
    // レーン境界を木の柱として描画(2px wood-dark)
    let laneWidth = size.width / CGFloat(laneCount)
    for i in 1..<laneCount {
      let x = CGFloat(i) * laneWidth
      let isCenter = (i == 2)
      let pillar = SKShapeNode(
        rect: CGRect(x: x - 1, y: 0, width: 2, height: size.height)
      )
      pillar.fillColor = isCenter ? Self.wGold.withAlphaComponent(0.55) : Self.wWoodDark
      pillar.strokeColor = .clear
      pillar.zPosition = -5
      addChild(pillar)
    }
  }

  private func layoutHitLine() {
    // 注連縄(金の帯)
    let rope = SKShapeNode(
      rect: CGRect(x: 0, y: hitLineY - 1.5, width: size.width, height: 3)
    )
    rope.fillColor = Self.wGold
    rope.strokeColor = .clear
    rope.glowWidth = 2
    rope.zPosition = 4
    addChild(rope)

    // 紙垂(しで)2 本 — 白い縦の垂れ
    for x in [size.width * 0.28, size.width * 0.72] {
      let shide = SKShapeNode(rect: CGRect(x: x - 1.5, y: hitLineY - 12, width: 3, height: 10))
      shide.fillColor = Self.wPaper
      shide.strokeColor = .clear
      shide.zPosition = 5
      addChild(shide)
    }
  }

  private func layoutMarkers() {
    let laneWidth = size.width / CGFloat(laneCount)
    let types: [NoteType] = [.ka_l, .don_l, .don_r, .ka_r]
    for i in 0..<laneCount {
      let x = (CGFloat(i) + 0.5) * laneWidth
      let type = types[i]
      let isDon = (type == .don_l || type == .don_r)

      // 木の丸枠(外側)
      let outerRing = SKShapeNode(circleOfRadius: 19)
      outerRing.strokeColor = Self.wWoodDeep
      outerRing.fillColor = .clear
      outerRing.lineWidth = 2
      outerRing.position = CGPoint(x: x, y: hitLineY)
      outerRing.zPosition = 5
      addChild(outerRing)

      // 色分け内輪
      let innerRing = SKShapeNode(circleOfRadius: 11)
      innerRing.strokeColor = (isDon ? Self.wDonDim : Self.wKaDim).withAlphaComponent(0.55)
      innerRing.fillColor = .clear
      innerRing.lineWidth = 1.5
      innerRing.position = CGPoint(x: x, y: hitLineY)
      innerRing.zPosition = 6
      addChild(innerRing)
    }
  }

  private func layoutTatamiEdge() {
    // 太鼓の下、画面最下部に畳の縁を模した深緑の細い帯
    let edge = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: 8))
    edge.fillColor = Self.wMoss
    edge.strokeColor = .clear
    edge.zPosition = 10
    addChild(edge)
  }

  private func layoutDrum() {
    let center = CGPoint(x: size.width / 2, y: drumCenterY)

    // 外側の縁(タン色)
    let outerRim = SKShapeNode(circleOfRadius: drumRadius)
    outerRim.fillColor = Self.wWoodMid
    outerRim.strokeColor = .clear
    outerRim.position = center
    outerRim.zPosition = 1
    addChild(outerRim)

    // 縁と皮の境界(細い濃色線で立体感)
    let boundary = SKShapeNode(circleOfRadius: drumRadius * 0.897)
    boundary.fillColor = Self.wWoodDark
    boundary.strokeColor = .clear
    boundary.position = center
    boundary.zPosition = 2
    addChild(boundary)

    // 皮(クリーム色)
    let skin = SKShapeNode(circleOfRadius: drumRadius * 0.878)
    skin.fillColor = Self.wSkin
    skin.strokeColor = .clear
    skin.position = center
    skin.zPosition = 3
    addChild(skin)

    // 鋲(40 個、9° 間隔で外縁の少し内側に配置)
    let studRadius: CGFloat = drumRadius * 0.949
    for i in 0..<40 {
      let angle = CGFloat(i) * (.pi / 20) - .pi / 2
      let sx = center.x + cos(angle) * studRadius
      let sy = center.y + sin(angle) * studRadius
      let stud = SKShapeNode(circleOfRadius: 2.5)
      stud.fillColor = Self.wWoodSumi
      stud.strokeColor = .clear
      stud.position = CGPoint(x: sx, y: sy)
      stud.zPosition = 4
      addChild(stud)
    }
  }

  // MARK: - Note scheduling

  private func scheduleNotes(from chart: Chart, offsetSec: TimeInterval = 0) {
    for (idx, note) in chart.notes.enumerated() {
      let originalTargetSec = TimeInterval(note.t) / 1000.0
      let effectiveTargetSec = originalTargetSec - offsetSec
      let durationSec = TimeInterval(note.duration ?? 0) / 1000.0
      // 既に終端まで過ぎたノーツはスキップ
      // (ホールドなら target + duration が過去、単発なら target が過去)
      let endSec = effectiveTargetSec + durationSec
      if endSec < -Self.missGraceSec { continue }
      spawnNote(
        targetTime: effectiveTargetSec,
        type: note.type,
        durationSec: durationSec,
        originalIndex: idx
      )
    }
  }

  private func scheduleFinish(after delay: TimeInterval) {
    let wait = SKAction.wait(forDuration: delay)
    let notify = SKAction.run { [weak self] in
      guard let self else { return }
      self.onFinished?(self.score)
    }
    run(SKAction.sequence([wait, notify]), withKey: "finish")
  }

  private func spawnNote(
    targetTime: TimeInterval,
    type: NoteType,
    durationSec: TimeInterval,
    originalIndex: Int = -1
  ) {
    let laneWidth = size.width / CGFloat(laneCount)
    let x: CGFloat
    let isDon: Bool
    let isBoth: Bool
    switch type {
    case .ka_l:
      x = 0.5 * laneWidth; isDon = false; isBoth = false
    case .don_l:
      x = 1.5 * laneWidth; isDon = true;  isBoth = false
    case .don_r:
      x = 2.5 * laneWidth; isDon = true;  isBoth = false
    case .ka_r:
      x = 3.5 * laneWidth; isDon = false; isBoth = false
    case .don_both:
      x = size.width / 2;  isDon = true;  isBoth = true
    }

    let spawnY = size.height + 40
    let fallDistance = spawnY - hitLineY
    let fallSpeedPerSec = fallDistance / fallDuration
    let startY: CGFloat
    let spawnDelay: TimeInterval
    let actualFallDuration: TimeInterval
    if targetTime >= fallDuration {
      startY = spawnY
      spawnDelay = targetTime - fallDuration
      actualFallDuration = fallDuration
    } else {
      let clampedTarget = max(0, targetTime)
      startY = hitLineY + fallSpeedPerSec * CGFloat(clampedTarget)
      spawnDelay = 0
      actualFallDuration = clampedTarget
    }

    // ノーツサイズ(和風モダン v2 準拠、フラット + 2 重縁)
    let baseRadius: CGFloat = isDon ? 20 : 16
    let radius: CGFloat = isBoth ? 26 : baseRadius

    // 2 重縁を作るため、外側から順に大きさ違いの SKShapeNode をコンテナに追加
    let container = SKNode()
    container.position = CGPoint(x: x, y: startY)
    container.zPosition = isBoth ? 4 : 3

    let mainColor: SKColor = isDon ? Self.wDon : Self.wKa
    let outerBorder: SKColor = isDon ? Self.wDonDim : Self.wKaDim
    let innerBorder: SKColor = isDon ? Self.wGold : Self.wSilver
    let borderWidthOuter: CGFloat = isBoth ? 4 : 3
    let borderWidthInner: CGFloat = isBoth ? 3 : 2

    // 一番外(濃色の縁)
    let outerRing = SKShapeNode(circleOfRadius: radius + borderWidthOuter)
    outerRing.fillColor = outerBorder
    outerRing.strokeColor = .clear
    container.addChild(outerRing)

    // 中間(金 or 銀の縁)
    let midRing = SKShapeNode(circleOfRadius: radius + borderWidthInner)
    midRing.fillColor = innerBorder
    midRing.strokeColor = .clear
    container.addChild(midRing)

    // 本体
    let node = SKShapeNode(circleOfRadius: radius)
    node.fillColor = mainColor
    node.strokeColor = .clear
    container.addChild(node)

    // ホールドの尾(頭の「上」に伸びる)
    var tailNode: SKShapeNode?
    if durationSec > 0 {
      let tailLength = fallSpeedPerSec * CGFloat(durationSec)
      let tailWidth: CGFloat = 12
      let tail = SKShapeNode(
        rect: CGRect(x: -tailWidth / 2, y: 0, width: tailWidth, height: tailLength)
      )
      tail.fillColor = mainColor.withAlphaComponent(0.5)
      tail.strokeColor = outerBorder.withAlphaComponent(0.6)
      tail.lineWidth = 1
      tail.zPosition = -1
      container.addChild(tail)
      tailNode = tail
    }

    addChild(container)

    let id = UUID()
    let pending = PendingNote(
      id: id,
      targetTime: targetTime,
      type: type,
      durationSec: durationSec,
      node: node,
      tail: tailNode,
      originalIndex: originalIndex
    )
    pendingNotes.append(pending)

    // container を落下対象にする(全体が一緒に動く)
    let wait = SKAction.wait(forDuration: spawnDelay)
    let fall = SKAction.moveTo(y: hitLineY, duration: actualFallDuration)
    let remove = SKAction.removeFromParent()

    if mode == .autoPlay {
      // 自動再生モード: タッチ判定なし
      // - 単発ノーツ: 判定ラインに到達したら即座に削除(interactive で
      //   タップされた瞬間に消えるのと同じ挙動)
      // - ホールドノーツ: 判定ラインに到達したら「押されている」演出に切り替え
      //   * 頭は hit line に固定
      //   * 尾は durationSec で 0 にスケール(interactive の registerHold と同じ演出)
      //   * durationSec 経過後、まとめて削除
      var actions: [SKAction] = [wait, fall]
      if durationSec > 0, let tail = tailNode {
        let dur = durationSec
        actions.append(SKAction.run { [weak container, weak tail] in
          // 頭を半透明にしてホールド継続中の視覚フィードバック
          container?.alpha = 0.4
          // 尾を残り時間で縮ませる(頭固定、尾が上から下へ縮む)
          if let tail {
            let shrink = SKAction.scaleY(to: 0, duration: dur)
            shrink.timingMode = .linear
            tail.run(shrink)
          }
        })
        actions.append(SKAction.wait(forDuration: dur))
      }
      // 単発は wait/fall の直後、ホールドは wait/fall + shrink 完了直後に削除
      actions.append(remove)
      container.run(SKAction.sequence(actions))
    } else {
      // interactive モード: 既存動作(タッチされなければ miss として cleanup)
      let passThrough = SKAction.moveBy(x: 0, y: -60, duration: Self.missGraceSec)
      let cleanup = SKAction.run { [weak self, id] in
        self?.expireAsMiss(id: id)
      }
      container.run(SKAction.sequence([wait, fall, passThrough, cleanup, remove]))
    }
  }

  private func expireAsMiss(id: UUID) {
    guard let idx = pendingNotes.firstIndex(where: { $0.id == id }) else { return }
    pendingNotes.remove(at: idx)
    score.record(.miss)
    onScoreChanged?(score)
    showJudge(.miss)
  }

  // MARK: - Touch handling

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    if mode == .autoPlay {
      // 自動再生モード: 停止中のみ編集タップを受け付ける(再生中は無視)
      if isEditingPaused, let touch = touches.first {
        handleEditingTap(at: touch.location(in: self))
      }
      return
    }

    let now = CACurrentMediaTime() - startTime

    // 50ms を超えた古いエントリは相方判定の対象外(掃除)
    recentTouches.removeAll { now - $0.time > Self.bothPairWindowSec }

    // 1) 全タッチを recentTouches / newEntries に登録
    var newEntries: [RecentTouch] = []
    for touch in touches {
      let location = touch.location(in: self)
      let zone = tapZone(at: location)
      let half: CenterHalf?
      if zone == .center {
        half = location.x < size.width / 2 ? .left : .right
      } else {
        half = nil
      }
      let entry = RecentTouch(
        id: ObjectIdentifier(touch),
        time: now,
        zone: zone,
        centerHalf: half,
        consumed: false
      )
      recentTouches.append(entry)
      newEntries.append(entry)
    }

    // 2) 中央タッチ:まず両手同時打の相方を優先チェック、なければ判定を遅延
    for entry in newEntries where entry.zone == .center {
      // Bug fix 1: 先行 iteration の tryMatchDonBoth で相方として消費済みなら
      // 二度判定を回避(recentTouches は既に consumed=true)
      if isConsumed(id: entry.id) { continue }

      if tryMatchDonBoth(entry: entry, now: now, touchesBeganWith: touches) {
        continue
      }

      // Bug fix 2: don_both が近時刻に pending なのに相方がまだいない場合、
      // bothPairWindowSec 待って再判定する(相方が別 touchesBegan で来る可能性)。
      // これをしないと、片手だけ先に届いた両手ドンが誤って don_l/don_r を
      // 消費したり、判定失敗の「不可」表示を出したりする。
      if hasDonBothPendingNear(time: now) {
        if let touch = touches.first(where: { ObjectIdentifier($0) == entry.id }) {
          scheduleDeferredCenterJudge(id: entry.id, tapTime: now, touch: touch)
        }
      } else {
        if let touch = touches.first(where: { ObjectIdentifier($0) == entry.id }) {
          judgeSingle(tapTime: now, zone: .center, touch: touch)
        }
      }
    }

    // 3) 外側ゾーン(カッ)は don_both と無関係なので即座に判定
    for entry in newEntries where entry.zone != .center {
      if let touch = touches.first(where: { ObjectIdentifier($0) == entry.id }) {
        judgeSingle(tapTime: now, zone: entry.zone, touch: touch)
      }
    }
  }

  private func isConsumed(id: ObjectIdentifier) -> Bool {
    recentTouches.first(where: { $0.id == id })?.consumed ?? false
  }

  private func hasDonBothPendingNear(time: TimeInterval) -> Bool {
    let toleranceSec = TimeInterval(Self.okWindowMs) / 1000.0
    return pendingNotes.contains { pending in
      pending.type == .don_both && abs(pending.targetTime - time) <= toleranceSec
    }
  }

  private func scheduleDeferredCenterJudge(
    id: ObjectIdentifier,
    tapTime: TimeInterval,
    touch: UITouch
  ) {
    deferredCenterTaps.append(DeferredCenterTap(id: id, tapTime: tapTime, touch: touch))
    // bothPairWindowSec 分だけ待つ(相方の到達を待つ)
    let touchId = id
    run(SKAction.sequence([
      SKAction.wait(forDuration: Self.bothPairWindowSec + 0.005),
      SKAction.run { [weak self] in
        self?.resolveDeferredCenterJudge(id: touchId)
      },
    ]))
  }

  private func resolveDeferredCenterJudge(id: ObjectIdentifier) {
    guard let idx = deferredCenterTaps.firstIndex(where: { $0.id == id }) else { return }
    let deferred = deferredCenterTaps.remove(at: idx)

    // 待機中に相方の tryMatchDonBoth が成功して、この entry が消費されている場合はスキップ
    if isConsumed(id: id) { return }

    // 相方到達での don_both マッチをもう一度試みる
    // (相方が別 touchesBegan で来て、まだ deferred バッファ内なら
    //  そのまま consumed=false のまま残っているケース)
    if let entry = recentTouches.first(where: { $0.id == id }) {
      let dummySet: Set<UITouch> = [deferred.touch]
      if tryMatchDonBoth(entry: entry, now: deferred.tapTime, touchesBeganWith: dummySet) {
        return
      }
    }

    // 相方来ず。orphan タップとして単発判定に落とす。
    judgeSingle(tapTime: deferred.tapTime, zone: .center, touch: deferred.touch)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard mode == .interactive else { return }
    finishHolds(for: touches, cancelled: false)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard mode == .interactive else { return }
    finishHolds(for: touches, cancelled: true)
  }

  private func tapZone(at point: CGPoint) -> NoteType.Zone {
    let cx = size.width / 2
    let dx = point.x - cx
    let dy = point.y - drumCenterY
    if dx * dx + dy * dy <= drumRadius * drumRadius {
      return .center
    }
    let width = size.width
    if point.x < width * 0.25 {
      return .leftKa
    } else if point.x <= width * 0.75 {
      return .center
    } else {
      return .rightKa
    }
  }

  // MARK: - Judge: two-hand (既存ロジック維持)

  private func tryMatchDonBoth(
    entry: RecentTouch,
    now: TimeInterval,
    touchesBeganWith touches: Set<UITouch>
  ) -> Bool {
    guard entry.zone == .center, let myHalf = entry.centerHalf else { return false }

    let toleranceSec = TimeInterval(Self.okWindowMs) / 1000.0
    guard let noteIdx = pendingNotes.firstIndex(where: { pending in
      pending.type == .don_both &&
      abs(pending.targetTime - now) <= toleranceSec
    }) else {
      return false
    }

    let pairIdx = recentTouches.lastIndex(where: { other in
      other.id != entry.id &&
      !other.consumed &&
      other.zone == .center &&
      other.centerHalf != nil &&
      other.centerHalf != myHalf &&
      now - other.time <= Self.bothPairWindowSec
    })

    guard let pairIdx else { return false }
    recentTouches[pairIdx].consumed = true
    if let selfIdx = recentTouches.lastIndex(where: { $0.id == entry.id }) {
      recentTouches[selfIdx].consumed = true
    }

    let note = pendingNotes[noteIdx]
    let diffMs = Int(abs(note.targetTime - now) * 1000)
    let result: JudgeResult = diffMs <= Self.goodWindowMs ? .good : .ok

    AudioEngine.shared.play(for: note.type)
    Haptics.shared.fire(for: note.type)

    if note.durationSec > 0 {
      if let anchorTouch = touches.first(where: { ObjectIdentifier($0) == entry.id }) {
        let partnerId = recentTouches[pairIdx].id
        registerHold(note: note, touch: anchorTouch, partnerId: partnerId, atTime: now)
      }
    } else {
      note.node?.parent?.removeAllActions()
      note.node?.parent?.removeFromParent()
    }

    pendingNotes.remove(at: noteIdx)
    score.record(result)
    onScoreChanged?(score)
    showJudge(result)
    return true
  }

  // MARK: - Judge: single tap(既存ロジック維持)

  private func judgeSingle(tapTime: TimeInterval, zone: NoteType.Zone, touch: UITouch) {
    let toleranceSec = TimeInterval(Self.okWindowMs) / 1000.0

    let candidateIndex = pendingNotes
      .enumerated()
      .filter { $0.element.type != .don_both }
      .filter { matchesZone(noteZone: $0.element.type.zone, tapZone: zone) }
      .filter { abs($0.element.targetTime - tapTime) <= toleranceSec }
      .min(by: { abs($0.element.targetTime - tapTime) < abs($1.element.targetTime - tapTime) })?
      .offset

    guard let idx = candidateIndex else {
      showJudge(.miss)
      return
    }

    let note = pendingNotes[idx]
    let diffMs = Int(abs(note.targetTime - tapTime) * 1000)
    let result: JudgeResult = diffMs <= Self.goodWindowMs ? .good : .ok

    AudioEngine.shared.play(for: note.type)
    Haptics.shared.fire(for: note.type)

    if note.durationSec > 0 {
      registerHold(note: note, touch: touch, atTime: tapTime)
    } else {
      note.node?.parent?.removeAllActions()
      note.node?.parent?.removeFromParent()
    }

    pendingNotes.remove(at: idx)
    score.record(result)
    onScoreChanged?(score)
    showJudge(result)
  }

  // MARK: - Hold tracking(既存ロジック維持、node.parent = container を対象に修正)

  private func registerHold(
    note: PendingNote,
    touch: UITouch,
    partnerId: ObjectIdentifier? = nil,
    atTime tapTime: TimeInterval
  ) {
    note.node?.parent?.removeAllActions()
    if let container = note.node?.parent {
      container.position = CGPoint(x: container.position.x, y: hitLineY)
    }
    note.node?.parent?.alpha = 0.4

    let expected = note.targetTime + note.durationSec

    if let tail = note.tail, note.durationSec > 0 {
      tail.removeAllActions()
      let remaining = max(0, expected - tapTime)
      if remaining > 0 {
        let shrink = SKAction.scaleY(to: 0, duration: remaining)
        shrink.timingMode = .linear
        tail.run(shrink)
      } else {
        tail.yScale = 0
      }
    }

    let anchorId = ObjectIdentifier(touch)

    activeHolds[anchorId] = ActiveHold(
      noteId: note.id,
      type: note.type,
      expectedReleaseTime: expected,
      headNode: note.node,
      tailNode: note.tail,
      partnerTouchId: partnerId
    )

    if let partnerId = partnerId {
      activeHolds[partnerId] = ActiveHold(
        noteId: note.id,
        type: note.type,
        expectedReleaseTime: expected,
        headNode: note.node,
        tailNode: note.tail,
        partnerTouchId: anchorId
      )
    }
  }

  private func finishHolds(for touches: Set<UITouch>, cancelled: Bool) {
    let now = CACurrentMediaTime() - startTime
    for touch in touches {
      let key = ObjectIdentifier(touch)
      guard let hold = activeHolds.removeValue(forKey: key) else { continue }
      if let partnerId = hold.partnerTouchId {
        activeHolds.removeValue(forKey: partnerId)
      }
      let diffMs = Int(abs(hold.expectedReleaseTime - now) * 1000)
      let result: JudgeResult
      if cancelled {
        result = .miss
      } else if diffMs <= Self.holdTailToleranceMs {
        result = .good
      } else if now < hold.expectedReleaseTime {
        let earlyMs = Int((hold.expectedReleaseTime - now) * 1000)
        result = earlyMs <= Self.okWindowMs ? .ok : .miss
      } else {
        result = .ok
      }

      hold.tailNode?.removeFromParent()
      hold.headNode?.parent?.removeAllActions()
      hold.headNode?.parent?.removeFromParent()

      score.record(result)
      onScoreChanged?(score)
      showJudge(result)
    }
  }

  private func matchesZone(noteZone: NoteType.Zone, tapZone: NoteType.Zone) -> Bool {
    switch (noteZone, tapZone) {
    case (.leftKa, .leftKa),
         (.center, .center),
         (.rightKa, .rightKa):
      return true
    default:
      return false
    }
  }

  // MARK: - Judge display

  private func showJudge(_ result: JudgeResult) {
    judgeLabel?.removeFromParent()
    let (text, color): (String, SKColor)
    switch result {
    case .good:
      text = "良!"
      color = Self.wGold
    case .ok:
      text = "可"
      color = Self.wKaDim
    case .miss:
      text = "不可"
      color = Self.wSumiSoft
    }

    let label = SKLabelNode(fontNamed: "HiraMinProN-W6")
    label.text = text
    label.fontSize = 30
    label.fontColor = color
    label.position = CGPoint(x: size.width / 2, y: hitLineY + 100)
    label.setScale(0.6)
    label.alpha = 0
    label.zPosition = 100
    addChild(label)
    label.run(SKAction.sequence([
      SKAction.group([
        SKAction.fadeIn(withDuration: 0.1),
        SKAction.scale(to: 1.1, duration: 0.15),
      ]),
      SKAction.scale(to: 1.0, duration: 0.1),
      SKAction.wait(forDuration: 0.35),
      SKAction.fadeOut(withDuration: 0.2),
      SKAction.removeFromParent(),
    ]))
    judgeLabel = label
  }
}
