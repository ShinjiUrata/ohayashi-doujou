import SpriteKit
import Foundation

/// プレイ画面の SpriteKit シーン。
///
/// Phase 1(最小プロトタイプ)の実装:
/// - 静的レイアウト(4レーン + 判定ライン + 判定リング + 太鼓)
/// - デモ用のハードコード譜面を再生
/// - タップ位置で 3 ゾーン判別
/// - タイミング判定(良/可/不可)
/// - 効果音 + 触覚
/// - `isMultipleTouchEnabled = true`(両手同時打を Phase 2 で組み込むための下地)
///
/// Phase 2 以降で:
/// - `Chart` からノーツ列を受け取ってスケジュール
/// - 両手同時打 (`don_both`) 判定(50ms ウィンドウ)
/// - ホールドノート判定(頭 + 尾、±150ms)
/// - スコア / コンボ計算
@MainActor
final class PlayScene: SKScene {
  // MARK: - Layout constants
  private let hitLineY: CGFloat = 220
  private let laneCount: Int = 4
  private let fallDuration: TimeInterval = 2.5

  // MARK: - Judgment constants(暫定、実装後に試遊調整)
  private static let goodWindowMs: Int = 200
  private static let okWindowMs: Int = 400

  // MARK: - State
  private var startTime: TimeInterval = 0
  private var pendingNotes: [PendingNote] = []
  private var judgeLabel: SKLabelNode?

  private struct PendingNote {
    let id: UUID
    let targetTime: TimeInterval
    let type: NoteType
    weak var node: SKShapeNode?
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

    startTime = CACurrentMediaTime()
    scheduleDemoNotes()
  }

  override func willMove(from view: SKView) {
    removeAllActions()
    pendingNotes.removeAll()
  }

  // MARK: - Layout

  private func layoutBackground() {
    let overlay = SKShapeNode(rect: CGRect(x: 0, y: size.height - 80, width: size.width, height: 80))
    overlay.fillColor = SKColor(red: 0xc4 / 255.0, green: 0x21 / 255.0, blue: 0x1d / 255.0, alpha: 0.18)
    overlay.strokeColor = .clear
    overlay.zPosition = -10
    addChild(overlay)

    let title = SKLabelNode(fontNamed: "HiraginoSans-W6")
    title.text = "♪ お囃子の練習"
    title.fontSize = 14
    title.fontColor = SKColor(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0, alpha: 1)
    title.horizontalAlignmentMode = .left
    title.verticalAlignmentMode = .top
    title.position = CGPoint(x: 20, y: size.height - 20)
    title.zPosition = 10
    addChild(title)
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
    let drumRadius: CGFloat = 140
    let drum = SKShapeNode(circleOfRadius: drumRadius)
    drum.fillColor = SKColor(red: 0xc8 / 255.0, green: 0x21 / 255.0, blue: 0x1d / 255.0, alpha: 1)
    drum.strokeColor = SKColor(red: 0x4a / 255.0, green: 0x26 / 255.0, blue: 0x18 / 255.0, alpha: 1)
    drum.lineWidth = 4
    drum.position = CGPoint(x: size.width / 2, y: -20)
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

  private func scheduleDemoNotes() {
    // Phase 1 プロトタイプ: 判定と描画の疎通確認用に 6 音のパターンを永続ループさせる。
    // Phase 2 で `Chart` を注入する API に置き換え、このメソッドは削除する。
    let pattern: [(TimeInterval, NoteType)] = [
      (0.0, .don_l),
      (0.7, .ka_r),
      (1.4, .don_r),
      (2.1, .ka_l),
      (2.8, .don_l),
      (3.5, .don_r),
    ]
    let cycleLength: TimeInterval = 4.5
    let leadIn: TimeInterval = 2.0

    let scheduleCycle = SKAction.run { [weak self] in
      guard let self else { return }
      let cycleStart = CACurrentMediaTime() - self.startTime
      for (offset, type) in pattern {
        self.spawnNote(targetTime: cycleStart + offset + self.fallDuration, type: type)
      }
    }
    let wait = SKAction.wait(forDuration: cycleLength)
    let loop = SKAction.repeatForever(SKAction.sequence([scheduleCycle, wait]))

    // 起動後 leadIn 秒だけ待ってから 1 サイクル目を投入(準備が整うまでの間)
    run(SKAction.sequence([SKAction.wait(forDuration: leadIn), loop]))
  }

  private func spawnNote(targetTime: TimeInterval, type: NoteType) {
    let laneWidth = size.width / CGFloat(laneCount)
    let laneIndex: Int
    let isDon: Bool
    switch type {
    case .ka_l:
      laneIndex = 0; isDon = false
    case .don_l:
      laneIndex = 1; isDon = true
    case .don_r:
      laneIndex = 2; isDon = true
    case .ka_r:
      laneIndex = 3; isDon = false
    case .don_both:
      laneIndex = 1; isDon = true  // Phase 2 で中央にまたがる形に拡張
    }
    let x = (CGFloat(laneIndex) + 0.5) * laneWidth

    let radius: CGFloat = isDon ? 18 : 14
    let node = SKShapeNode(circleOfRadius: radius)
    node.zPosition = 3
    if isDon {
      node.fillColor = SKColor(red: 0xe2 / 255.0, green: 0x3b / 255.0, blue: 0x3b / 255.0, alpha: 1)
    } else {
      node.fillColor = SKColor(red: 0x4e / 255.0, green: 0xa7 / 255.0, blue: 0xd9 / 255.0, alpha: 1)
    }
    node.strokeColor = SKColor.white.withAlphaComponent(0.3)
    node.lineWidth = 1
    node.position = CGPoint(x: x, y: size.height + 40)

    let hand = SKLabelNode(fontNamed: "HiraginoSans-W6")
    hand.text = handLabel(for: type)
    hand.fontSize = 11
    hand.fontColor = .white
    hand.verticalAlignmentMode = .center
    node.addChild(hand)

    addChild(node)

    let id = UUID()
    let pending = PendingNote(id: id, targetTime: targetTime, type: type, node: node)
    pendingNotes.append(pending)

    let spawnDelay = max(0, targetTime - fallDuration)
    let wait = SKAction.wait(forDuration: spawnDelay)
    let fall = SKAction.moveTo(y: hitLineY, duration: fallDuration)
    let passThrough = SKAction.moveBy(x: 0, y: -60, duration: 0.5)
    let cleanup = SKAction.run { [weak self, id] in
      self?.expire(id: id)
    }
    let remove = SKAction.removeFromParent()
    node.run(SKAction.sequence([wait, fall, passThrough, cleanup, remove]))
  }

  private func handLabel(for type: NoteType) -> String {
    switch type {
    case .don_l, .ka_l: return "左"
    case .don_r, .ka_r: return "右"
    case .don_both: return "両"
    }
  }

  private func expire(id: UUID) {
    guard let idx = pendingNotes.firstIndex(where: { $0.id == id }) else { return }
    pendingNotes.remove(at: idx)
    showJudge("不可", color: SKColor(white: 0.6, alpha: 1))
  }

  // MARK: - Touch handling

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    let now = CACurrentMediaTime() - startTime
    for touch in touches {
      let location = touch.location(in: self)
      let zone = tapZone(forX: location.x)
      judge(tapTime: now, zone: zone)
    }
  }

  private func tapZone(forX x: CGFloat) -> NoteType.Zone {
    let width = size.width
    if x < width * 0.25 {
      return .leftKa
    } else if x <= width * 0.75 {
      return .center
    } else {
      return .rightKa
    }
  }

  private func judge(tapTime: TimeInterval, zone: NoteType.Zone) {
    let toleranceSec = TimeInterval(Self.okWindowMs) / 1000.0

    // ゾーンが一致する pending から、最も時刻が近いものを選ぶ
    let candidateIndex = pendingNotes
      .enumerated()
      .filter { matchesZone(noteZone: $0.element.type.zone, tapZone: zone) }
      .filter { abs($0.element.targetTime - tapTime) <= toleranceSec }
      .min(by: { abs($0.element.targetTime - tapTime) < abs($1.element.targetTime - tapTime) })?
      .offset

    guard let idx = candidateIndex else {
      // ウィンドウ内マッチなし
      showJudge("不可", color: SKColor(white: 0.6, alpha: 1))
      return
    }

    let note = pendingNotes[idx]
    let diffMs = Int(abs(note.targetTime - tapTime) * 1000)

    let judgeText: String
    let color: SKColor
    if diffMs <= Self.goodWindowMs {
      judgeText = "良!"
      color = SKColor(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0, alpha: 1)
    } else {
      judgeText = "可"
      color = SKColor(red: 0x6b / 255.0, green: 0xc9 / 255.0, blue: 0x8a / 255.0, alpha: 1)
    }

    AudioEngine.shared.play(for: note.type)
    Haptics.shared.fire(for: note.type)

    note.node?.removeAllActions()
    note.node?.removeFromParent()
    pendingNotes.remove(at: idx)

    showJudge(judgeText, color: color)
  }

  private func matchesZone(noteZone: NoteType.Zone, tapZone: NoteType.Zone) -> Bool {
    switch (noteZone, tapZone) {
    case (.leftKa, .leftKa),
         (.center, .center),
         (.rightKa, .rightKa),
         (.centerBoth, .center):
      // Phase 1 段階では centerBoth も中央タップ 1 発で暫定成立(Phase 2 で 2 タッチ判定へ)
      return true
    default:
      return false
    }
  }

  private func showJudge(_ text: String, color: SKColor) {
    judgeLabel?.removeFromParent()
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
