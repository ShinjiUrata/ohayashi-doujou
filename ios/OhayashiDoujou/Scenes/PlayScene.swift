import SpriteKit
import Foundation

/// プレイ画面の SpriteKit シーン。
///
/// Phase 2 完成版:
/// - `Chart` を受け取り、`notes` を時系列でスケジュール
/// - 3 ゾーン判定 + タイミング判定(良/可/不可)
/// - **両手同時打**(`don_both`)判定: 中央左右半分に 50ms 以内の 2 タッチで成立
/// - **ホールドノート**(`duration > 0`)判定: 頭 + 尾 の 2 段、尾は ±150ms
/// - スコア / コンボを計算し、コールバックで SwiftUI 側へ通知
/// - 譜面終了検出 → 完了コールバック
///
/// 実装方針の落とし穴は `implementation_notes/ios_pitfalls.md` §21-22 を参照。
@MainActor
final class PlayScene: SKScene {
  // MARK: - Layout constants
  private let hitLineY: CGFloat = 220
  private let laneCount: Int = 4
  private let fallDuration: TimeInterval = 2.5
  private let drumRadius: CGFloat = 140
  private let drumCenterY: CGFloat = -20

  // MARK: - Judgment constants(暫定、Phase 6 で試遊調整)
  private static let goodWindowMs: Int = 200
  private static let okWindowMs: Int = 400
  private static let holdTailToleranceMs: Int = 150
  /// 両手同時打の 2 タッチ同時判定ウィンドウ。
  private static let bothPairWindowSec: TimeInterval = 0.05
  /// ミス確定までの猶予(判定ラインを過ぎてから)。
  private static let missGraceSec: TimeInterval = 0.5

  // MARK: - Public API (SwiftUI 側から設定)
  var onScoreChanged: (@MainActor (ScoreState) -> Void)?
  var onFinished: (@MainActor (ScoreState) -> Void)?

  // MARK: - State
  private var chart: Chart?
  private(set) var score = ScoreState()
  private var startTime: TimeInterval = 0
  private var pendingNotes: [PendingNote] = []
  private var judgeLabel: SKLabelNode?

  /// 直近のタッチ履歴(両手同時打の相方を探すため)。
  /// `bothPairWindowSec` を大きく超えたエントリは破棄する。
  private var recentTouches: [RecentTouch] = []

  /// 進行中のホールド(頭が判定済みで、尾のリリース待ち)。
  private var activeHolds: [ObjectIdentifier: ActiveHold] = [:]

  private struct PendingNote {
    let id: UUID
    let targetTime: TimeInterval
    let type: NoteType
    let durationSec: TimeInterval  // 0 = 単発、>0 = ホールド
    weak var node: SKShapeNode?
    weak var tail: SKShapeNode?
  }

  private enum CenterHalf { case left, right }

  private struct RecentTouch {
    let id: ObjectIdentifier
    let time: TimeInterval
    let zone: NoteType.Zone
    let centerHalf: CenterHalf?  // zone == .center の時のみ意味を持つ
    var consumed: Bool
  }

  private struct ActiveHold {
    let noteId: UUID
    let type: NoteType
    let expectedReleaseTime: TimeInterval
    weak var headNode: SKShapeNode?
    weak var tailNode: SKShapeNode?
    /// 両手同時打ホールドの相方タッチ ID(単発ホールドでは nil)。
    /// どちらかの指が離れた時点で hold を確定させ、もう片方のエントリを掃除するために使う。
    let partnerTouchId: ObjectIdentifier?
  }

  // MARK: - Public entry

  /// 譜面を注入して再生を開始する。
  func load(chart: Chart) {
    self.chart = chart
    self.score = ScoreState()
    for pending in pendingNotes {
      pending.node?.removeAllActions()
      pending.node?.removeFromParent()
      pending.tail?.removeFromParent()
    }
    pendingNotes.removeAll()
    recentTouches.removeAll()
    activeHolds.removeAll()
    removeAllActions()

    startTime = CACurrentMediaTime()
    scheduleNotes(from: chart)
    scheduleFinish(after: TimeInterval(chart.durationMs) / 1000 + Self.missGraceSec)

    onScoreChanged?(score)
  }

  // MARK: - Scene lifecycle
  override func didMove(to view: SKView) {
    view.isMultipleTouchEnabled = true
    view.ignoresSiblingOrder = true
    backgroundColor = SKColor(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x1d / 255.0, alpha: 1)
    scaleMode = .resizeFill

    layoutBackground()
    layoutLanes()
    layoutMarkers()
    layoutHitLine()
    layoutDrum()
  }

  override func willMove(from view: SKView) {
    removeAllActions()
    pendingNotes.removeAll()
    recentTouches.removeAll()
    activeHolds.removeAll()
  }

  // MARK: - Layout

  private func layoutBackground() {
    let overlay = SKShapeNode(rect: CGRect(x: 0, y: size.height - 80, width: size.width, height: 80))
    overlay.fillColor = SKColor(red: 0xc4 / 255.0, green: 0x21 / 255.0, blue: 0x1d / 255.0, alpha: 0.18)
    overlay.strokeColor = .clear
    overlay.zPosition = -10
    addChild(overlay)
  }

  private func layoutLanes() {
    let laneWidth = size.width / CGFloat(laneCount)
    for i in 1..<laneCount {
      let x = CGFloat(i) * laneWidth
      let path = CGMutablePath()
      path.move(to: CGPoint(x: x, y: 0))
      path.addLine(to: CGPoint(x: x, y: size.height))
      let line = SKShapeNode(path: path)
      line.strokeColor = SKColor(white: 1, alpha: 0.06)
      line.lineWidth = 1
      line.zPosition = -5
      addChild(line)
    }
  }

  private func layoutMarkers() {
    let laneWidth = size.width / CGFloat(laneCount)
    let types: [NoteType] = [.ka_l, .don_l, .don_r, .ka_r]
    for i in 0..<laneCount {
      let x = (CGFloat(i) + 0.5) * laneWidth
      let type = types[i]
      let isDon = (type == .don_l || type == .don_r)
      let ring = SKShapeNode(circleOfRadius: 20)
      ring.strokeColor = isDon
        ? SKColor(red: 0xe2 / 255.0, green: 0x3b / 255.0, blue: 0x3b / 255.0, alpha: 0.7)
        : SKColor(red: 0x4e / 255.0, green: 0xa7 / 255.0, blue: 0xd9 / 255.0, alpha: 0.7)
      ring.fillColor = ring.strokeColor.withAlphaComponent(0.08)
      ring.lineWidth = 2
      ring.position = CGPoint(x: x, y: hitLineY)
      ring.zPosition = 5
      addChild(ring)
    }
  }

  private func layoutHitLine() {
    let line = SKShapeNode(
      rect: CGRect(x: 0, y: hitLineY - 1, width: size.width, height: 2)
    )
    line.fillColor = SKColor(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0, alpha: 1)
    line.strokeColor = .clear
    line.glowWidth = 4
    line.zPosition = 4
    addChild(line)
  }

  private func layoutDrum() {
    let drum = SKShapeNode(circleOfRadius: drumRadius)
    drum.fillColor = SKColor(red: 0xc8 / 255.0, green: 0x21 / 255.0, blue: 0x1d / 255.0, alpha: 1)
    drum.strokeColor = SKColor(red: 0x4a / 255.0, green: 0x26 / 255.0, blue: 0x18 / 255.0, alpha: 1)
    drum.lineWidth = 4
    drum.position = CGPoint(x: size.width / 2, y: drumCenterY)
    drum.zPosition = 1
    addChild(drum)

    let mon = SKShapeNode(circleOfRadius: 28)
    mon.fillColor = SKColor(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0, alpha: 0.15)
    mon.strokeColor = SKColor(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0, alpha: 0.3)
    mon.lineWidth = 1
    mon.position = CGPoint(x: size.width / 2, y: drumRadius / 3)
    mon.zPosition = 2
    addChild(mon)
  }

  // MARK: - Note scheduling

  private func scheduleNotes(from chart: Chart) {
    for note in chart.notes {
      let targetSec = TimeInterval(note.t) / 1000.0
      let durationSec = TimeInterval(note.duration ?? 0) / 1000.0
      spawnNote(targetTime: targetSec, type: note.type, durationSec: durationSec)
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

  private func spawnNote(targetTime: TimeInterval, type: NoteType, durationSec: TimeInterval) {
    let laneWidth = size.width / CGFloat(laneCount)
    let x: CGFloat
    let isDon: Bool
    let isBoth: Bool
    switch type {
    case .ka_l:
      x = 0.5 * laneWidth
      isDon = false; isBoth = false
    case .don_l:
      x = 1.5 * laneWidth
      isDon = true;  isBoth = false
    case .don_r:
      x = 2.5 * laneWidth
      isDon = true;  isBoth = false
    case .ka_r:
      x = 3.5 * laneWidth
      isDon = false; isBoth = false
    case .don_both:
      // 両手打は 2 つのドンレーンのちょうど真ん中(画面中央)に落とす
      x = size.width / 2
      isDon = true;  isBoth = true
    }

    let baseRadius: CGFloat = isDon ? 18 : 14
    let radius: CGFloat = isBoth ? baseRadius + 6 : baseRadius

    let node = SKShapeNode(circleOfRadius: radius)
    node.zPosition = 3
    if isDon {
      node.fillColor = SKColor(red: 0xe2 / 255.0, green: 0x3b / 255.0, blue: 0x3b / 255.0, alpha: 1)
    } else {
      node.fillColor = SKColor(red: 0x4e / 255.0, green: 0xa7 / 255.0, blue: 0xd9 / 255.0, alpha: 1)
    }
    node.strokeColor = SKColor.white.withAlphaComponent(isBoth ? 0.85 : 0.3)
    node.lineWidth = isBoth ? 3 : 1
    node.position = CGPoint(x: x, y: size.height + 40)

    if isBoth {
      let glow = SKShapeNode(circleOfRadius: radius + 6)
      glow.fillColor = .clear
      glow.strokeColor = SKColor.red.withAlphaComponent(0.4)
      glow.lineWidth = 6
      glow.glowWidth = 8
      glow.zPosition = 2
      node.addChild(glow)
    }

    let hand = SKLabelNode(fontNamed: "HiraginoSans-W6")
    hand.text = handLabel(for: type)
    hand.fontSize = isBoth ? 13 : 11
    hand.fontColor = .white
    hand.verticalAlignmentMode = .center
    node.addChild(hand)

    // ホールドの尾(帯)を描画
    var tailNode: SKShapeNode?
    if durationSec > 0 {
      // 尾の長さは落下速度と duration の積
      let pixelsPerSec = (size.height + 40 - hitLineY) / fallDuration
      let tailLength = pixelsPerSec * durationSec
      let tail = SKShapeNode(rect: CGRect(x: -6, y: 0, width: 12, height: tailLength))
      tail.fillColor = node.fillColor.withAlphaComponent(0.35)
      tail.strokeColor = .clear
      tail.zPosition = 2
      // 尾は頭ノードの子として付けるとフォールスクロールが自然
      node.addChild(tail)
      tailNode = tail
    }

    addChild(node)

    let id = UUID()
    let pending = PendingNote(
      id: id,
      targetTime: targetTime,
      type: type,
      durationSec: durationSec,
      node: node,
      tail: tailNode
    )
    pendingNotes.append(pending)

    let spawnDelay = max(0, targetTime - fallDuration)
    let wait = SKAction.wait(forDuration: spawnDelay)
    let fall = SKAction.moveTo(y: hitLineY, duration: fallDuration)
    let passThrough = SKAction.moveBy(x: 0, y: -60, duration: Self.missGraceSec)
    let cleanup = SKAction.run { [weak self, id] in
      self?.expireAsMiss(id: id)
    }
    let remove = SKAction.removeFromParent()
    node.run(SKAction.sequence([wait, fall, passThrough, cleanup, remove]))
  }

  private func handLabel(for type: NoteType) -> String {
    switch type {
    case .don_l, .ka_l: return "左"
    case .don_r, .ka_r: return "右"
    case .don_both:     return "両"
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
    let now = CACurrentMediaTime() - startTime

    // 古いエントリを掃除(50ms を超えたペア検出は無効)
    recentTouches.removeAll { now - $0.time > Self.bothPairWindowSec }

    // 1) まず全タッチをバッファに登録
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

    // 2) 新規タッチについて、まず両手同時打の相方を優先的にチェック
    for entry in newEntries where entry.zone == .center {
      if tryMatchDonBoth(entry: entry, now: now, touchesBeganWith: touches) {
        continue
      }
      // don_both マッチしなかった中央タッチは通常判定
      if let touch = touches.first(where: { ObjectIdentifier($0) == entry.id }) {
        judgeSingle(tapTime: now, zone: .center, touch: touch)
      }
    }

    // 3) 外側ゾーンのタッチは常に通常判定
    for entry in newEntries where entry.zone != .center {
      if let touch = touches.first(where: { ObjectIdentifier($0) == entry.id }) {
        judgeSingle(tapTime: now, zone: entry.zone, touch: touch)
      }
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishHolds(for: touches, cancelled: false)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishHolds(for: touches, cancelled: true)
  }

  private func tapZone(at point: CGPoint) -> NoteType.Zone {
    // 太鼓の円の内部なら中央(ドン)扱いにする。太鼓の視覚境界が斜めに
    // 走っているため、単純な x 座標のバーティカル境界だと「円の中なのに
    // ka 判定」になる帯ができてしまうため、円内優先で判定する。
    let cx = size.width / 2
    let dx = point.x - cx
    let dy = point.y - drumCenterY
    if dx * dx + dy * dy <= drumRadius * drumRadius {
      return .center
    }
    // 円の外側は x 座標ベース(落下ノーツエリア含む)
    let width = size.width
    if point.x < width * 0.25 {
      return .leftKa
    } else if point.x <= width * 0.75 {
      return .center
    } else {
      return .rightKa
    }
  }

  // MARK: - Judge: two-hand (don_both)

  /// 両手同時打(`don_both`)を判定する。マッチ成功時は true を返す。
  ///
  /// 中央ゾーンのタッチが 2 つ(左半分・右半分)、50ms 以内に検出されたとき成立する。
  private func tryMatchDonBoth(
    entry: RecentTouch,
    now: TimeInterval,
    touchesBeganWith touches: Set<UITouch>
  ) -> Bool {
    guard entry.zone == .center, let myHalf = entry.centerHalf else { return false }

    // 判定ウィンドウ内の don_both ノーツを探す
    let toleranceSec = TimeInterval(Self.okWindowMs) / 1000.0
    guard let noteIdx = pendingNotes.firstIndex(where: { pending in
      pending.type == .don_both &&
      abs(pending.targetTime - now) <= toleranceSec
    }) else {
      return false
    }

    // 直近 50ms 以内で、まだ未消費かつ反対半分の中央タッチを探す
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

    // ホールド (don_both + duration > 0) の場合は両手同時追跡
    if note.durationSec > 0 {
      if let anchorTouch = touches.first(where: { ObjectIdentifier($0) == entry.id }) {
        let partnerId = recentTouches[pairIdx].id
        registerHold(note: note, touch: anchorTouch, partnerId: partnerId, atTime: now)
      }
    } else {
      note.node?.removeAllActions()
      note.node?.removeFromParent()
    }

    pendingNotes.remove(at: noteIdx)
    score.record(result)
    onScoreChanged?(score)
    showJudge(result)
    return true
  }

  // MARK: - Judge: single tap

  private func judgeSingle(tapTime: TimeInterval, zone: NoteType.Zone, touch: UITouch) {
    let toleranceSec = TimeInterval(Self.okWindowMs) / 1000.0

    let candidateIndex = pendingNotes
      .enumerated()
      .filter { $0.element.type != .don_both }  // don_both は tryMatchDonBoth 側で扱う
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
      note.node?.removeAllActions()
      note.node?.removeFromParent()
    }

    pendingNotes.remove(at: idx)
    score.record(result)
    onScoreChanged?(score)
    showJudge(result)
  }

  // MARK: - Hold tracking

  private func registerHold(
    note: PendingNote,
    touch: UITouch,
    partnerId: ObjectIdentifier? = nil,
    atTime tapTime: TimeInterval
  ) {
    // 落下シーケンスを停止(この時点でシーケンス末尾の cleanup + remove も失われる)
    note.node?.removeAllActions()
    // 頭を判定ラインへスナップ(タップ時の位置がバラつくため見た目を安定させる)
    if let node = note.node {
      node.position = CGPoint(x: node.position.x, y: hitLineY)
    }
    // 頭を半透明にしてホールド継続中の視覚フィードバック
    note.node?.alpha = 0.4

    let expected = note.targetTime + note.durationSec

    // 尾を残り時間で縮ませる。頭ノードの子として rect(y: 0 → tailLength) で
    // 描かれているため、yScale を 1 → 0 に補間すれば下端(頭)固定で上端が
    // 徐々に頭へ降りてくる、標準的な音ゲーのホールド演出になる。
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

    // アンカー側のエントリ
    activeHolds[anchorId] = ActiveHold(
      noteId: note.id,
      type: note.type,
      expectedReleaseTime: expected,
      headNode: note.node,
      tailNode: note.tail,
      partnerTouchId: partnerId
    )

    // 両手同時打の場合、パートナー側にも同じ hold を登録
    // (どちらかが release されたら hold 判定が確定する)
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
      // 両手同時打の場合、相方エントリも同時に片付ける(二重判定防止)
      if let partnerId = hold.partnerTouchId {
        activeHolds.removeValue(forKey: partnerId)
      }
      // 尾判定
      let diffMs = Int(abs(hold.expectedReleaseTime - now) * 1000)
      let result: JudgeResult
      if cancelled {
        result = .miss
      } else if diffMs <= Self.holdTailToleranceMs {
        result = .good
      } else if now < hold.expectedReleaseTime {
        // 早離し
        let earlyMs = Int((hold.expectedReleaseTime - now) * 1000)
        result = earlyMs <= Self.okWindowMs ? .ok : .miss
      } else {
        // 遅離し(尾ウィンドウを過ぎた、スコアは可扱いで加点)
        result = .ok
      }

      // 頭・尾をまとめて削除(尾は頭の子ノードなので厳密には頭を消せば十分だが、
      // 安全のため明示的に片付ける)
      hold.tailNode?.removeFromParent()
      hold.headNode?.removeAllActions()
      hold.headNode?.removeFromParent()

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
      color = SKColor(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0, alpha: 1)
    case .ok:
      text = "可"
      color = SKColor(red: 0x6b / 255.0, green: 0xc9 / 255.0, blue: 0x8a / 255.0, alpha: 1)
    case .miss:
      text = "不可"
      color = SKColor(white: 0.6, alpha: 1)
    }

    let label = SKLabelNode(fontNamed: "HiraginoSans-W6")
    label.text = text
    label.fontSize = 28
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
