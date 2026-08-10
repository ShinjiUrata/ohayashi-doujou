import SpriteKit
import Foundation

/// 録音画面の SpriteKit シーン(和風モダン UI 適用)。
///
/// - 太鼓を中央で左右分割表示
/// - 外側のカッゾーン(左外・右外)
/// - タップ位置から type を判別(`ka_l` / `don_l` / `don_r` / `ka_r`)
/// - 中央左右半分に 50ms 以内の 2 タッチで `don_both` として合成
/// - 500ms 以上押し続けたタッチはホールドノート(`duration` 付き)として記録
/// - 打点ごとに効果音 + 触覚 + タップ位置の波紋
///
/// mockup: `mockups/06_recording_wafuu.html`
@MainActor
final class RecordingScene: SKScene {
  // MARK: - Constants
  private static let bothPairWindowSec: TimeInterval = 0.05
  private static let holdThresholdMs: Int = 500
  private let drumRadius: CGFloat = 140
  private let drumCenterY: CGFloat = 40

  // MARK: - Public API
  var onNoteRecorded: (@MainActor (Note) -> Void)?

  // MARK: - Recorded state
  private(set) var startedAt: TimeInterval = 0
  private(set) var recordedNotes: [Note] = []

  // MARK: - Touch tracking
  private struct PendingTouch {
    let id: ObjectIdentifier
    let startTime: TimeInterval
    let position: CGPoint
    let zone: NoteType.Zone
    let centerHalf: CenterHalf?
  }
  private enum CenterHalf { case left, right }

  private var pendingTouches: [ObjectIdentifier: PendingTouch] = [:]
  private var partnerMap: [ObjectIdentifier: ObjectIdentifier] = [:]
  private var consumedPartners: Set<ObjectIdentifier> = []

  // MARK: - Wafuu Palette
  private static let wDon      = SKColor(red: 0xFD/255, green: 0x47/255, blue: 0x20/255, alpha: 1)
  private static let wDonDim   = SKColor(red: 0xB0/255, green: 0x30/255, blue: 0x0F/255, alpha: 1)
  private static let wKa       = SKColor(red: 0x44/255, green: 0xC2/255, blue: 0xC1/255, alpha: 1)
  private static let wKaDim    = SKColor(red: 0x26/255, green: 0x87/255, blue: 0x86/255, alpha: 1)
  private static let wGold     = SKColor(red: 0xB8/255, green: 0x93/255, blue: 0x5A/255, alpha: 1)
  private static let wSumi     = SKColor(red: 0x2A/255, green: 0x26/255, blue: 0x20/255, alpha: 1)
  private static let wSumiSoft = SKColor(red: 0x5C/255, green: 0x52/255, blue: 0x48/255, alpha: 1)
  private static let wWoodMid  = SKColor(red: 0xC8/255, green: 0xA9/255, blue: 0x76/255, alpha: 1)
  private static let wWoodDark = SKColor(red: 0x8B/255, green: 0x6A/255, blue: 0x3C/255, alpha: 1)
  private static let wWoodDeep = SKColor(red: 0x5C/255, green: 0x42/255, blue: 0x25/255, alpha: 1)
  private static let wWoodSumi = SKColor(red: 0x2B/255, green: 0x1A/255, blue: 0x0E/255, alpha: 1)
  private static let wSkin     = SKColor(red: 0xF5/255, green: 0xED/255, blue: 0xD8/255, alpha: 1)
  private static let wMoss     = SKColor(red: 0x4D/255, green: 0x6C/255, blue: 0x3E/255, alpha: 1)

  // MARK: - Scene lifecycle
  private var didLayout = false
  private(set) var isCapturing = false

  override func didMove(to view: SKView) {
    view.isMultipleTouchEnabled = true
    view.ignoresSiblingOrder = true
    view.allowsTransparency = true
    backgroundColor = .clear
    scaleMode = .resizeFill

    guard !didLayout else { return }
    layoutStatic()
    didLayout = true
  }

  func beginCapture() {
    guard !isCapturing else { return }
    startedAt = CACurrentMediaTime()
    isCapturing = true
  }

  override func willMove(from view: SKView) {
    pendingTouches.removeAll()
    partnerMap.removeAll()
    consumedPartners.removeAll()
  }

  // MARK: - Layout

  private func layoutStatic() {
    layoutKaZones()
    layoutDrumSplit()
    layoutTatamiEdge()
  }

  private func layoutKaZones() {
    let width = size.width
    // 太鼓外側のカッゾーン(左右)にうっすら青の背景を敷く
    // 高さは太鼓中心付近まで
    let bandHeight: CGFloat = drumRadius * 1.8
    let bandY: CGFloat = drumCenterY - drumRadius * 0.6

    let leftZone = SKShapeNode(
      rect: CGRect(x: 0, y: bandY, width: width * 0.22, height: bandHeight)
    )
    leftZone.fillColor = Self.wKa.withAlphaComponent(0.06)
    leftZone.strokeColor = .clear
    leftZone.zPosition = -5
    addChild(leftZone)

    let rightZone = SKShapeNode(
      rect: CGRect(x: width * 0.78, y: bandY, width: width * 0.22, height: bandHeight)
    )
    rightZone.fillColor = Self.wKa.withAlphaComponent(0.06)
    rightZone.strokeColor = .clear
    rightZone.zPosition = -5
    addChild(rightZone)

    // ラベル(小さく控えめに)
    let ll = SKLabelNode(fontNamed: "HiraMinProN-W6")
    ll.text = "左カ"
    ll.fontSize = 12
    ll.fontColor = Self.wKaDim
    ll.position = CGPoint(x: width * 0.11, y: drumCenterY + drumRadius * 0.3)
    ll.zPosition = 1
    addChild(ll)

    let rl = SKLabelNode(fontNamed: "HiraMinProN-W6")
    rl.text = "右カ"
    rl.fontSize = 12
    rl.fontColor = Self.wKaDim
    rl.position = CGPoint(x: width * 0.89, y: drumCenterY + drumRadius * 0.3)
    rl.zPosition = 1
    addChild(rl)
  }

  private func layoutDrumSplit() {
    let center = CGPoint(x: size.width / 2, y: drumCenterY)

    // 太鼓の達人風フラットデザインを踏襲
    // 外側の縁(タン色)
    let outerRim = SKShapeNode(circleOfRadius: drumRadius)
    outerRim.fillColor = Self.wWoodMid
    outerRim.strokeColor = .clear
    outerRim.position = center
    outerRim.zPosition = 1
    addChild(outerRim)

    // 縁と皮の境界(細い濃色線)
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

    // 鋲(40 個)
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

    // 中央の分割線(縦棒、木の柱)
    let dividerHeight = drumRadius * 1.68  // 皮の高さに合わせる
    let divider = SKShapeNode(
      rect: CGRect(
        x: center.x - 1,
        y: center.y - dividerHeight / 2,
        width: 2,
        height: dividerHeight
      )
    )
    divider.fillColor = Self.wWoodDeep
    divider.strokeColor = .clear
    divider.zPosition = 5
    addChild(divider)

    // ラベル: 左ド / 右ド(太鼓の皮の上、うっすら)
    let ldl = SKLabelNode(fontNamed: "HiraMinProN-W6")
    ldl.text = "左ド"
    ldl.fontSize = 16
    ldl.fontColor = Self.wSumi.withAlphaComponent(0.35)
    ldl.position = CGPoint(x: center.x - drumRadius * 0.4, y: center.y + drumRadius * 0.1)
    ldl.zPosition = 6
    addChild(ldl)

    let rdl = SKLabelNode(fontNamed: "HiraMinProN-W6")
    rdl.text = "右ド"
    rdl.fontSize = 16
    rdl.fontColor = Self.wSumi.withAlphaComponent(0.35)
    rdl.position = CGPoint(x: center.x + drumRadius * 0.4, y: center.y + drumRadius * 0.1)
    rdl.zPosition = 6
    addChild(rdl)
  }

  private func layoutTatamiEdge() {
    let edge = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: 8))
    edge.fillColor = Self.wMoss
    edge.strokeColor = .clear
    edge.zPosition = 10
    addChild(edge)
  }

  // MARK: - Touch handling(既存ロジック維持)

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard isCapturing else { return }
    var newlyRegistered: [ObjectIdentifier] = []
    for touch in touches {
      let touchNow = touch.timestamp - startedAt
      let position = touch.location(in: self)
      let zone = tapZone(at: position)
      let half: CenterHalf?
      if zone == .center {
        half = position.x < size.width / 2 ? .left : .right
      } else {
        half = nil
      }
      let id = ObjectIdentifier(touch)
      pendingTouches[id] = PendingTouch(
        id: id,
        startTime: touchNow,
        position: position,
        zone: zone,
        centerHalf: half
      )
      newlyRegistered.append(id)

      let tentative = tentativeType(zone: zone, half: half)
      AudioEngine.shared.play(for: tentative)
      Haptics.shared.fire(for: tentative)

      spawnRipple(at: position, isDon: zone == .center)
    }

    for id in newlyRegistered {
      guard let pending = pendingTouches[id] else { continue }
      guard pending.zone == .center, let myHalf = pending.centerHalf else { continue }
      guard partnerMap[id] == nil else { continue }
      let partnerId = pendingTouches
        .filter { (otherId, other) in
          otherId != id &&
          partnerMap[otherId] == nil &&
          other.zone == .center &&
          other.centerHalf != nil &&
          other.centerHalf != myHalf &&
          abs(pending.startTime - other.startTime) <= Self.bothPairWindowSec
        }
        .keys
        .first
      if let partnerId = partnerId {
        partnerMap[id] = partnerId
        partnerMap[partnerId] = id
      }
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard isCapturing else { return }
    finalizeTouches(touches, cancelled: false)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard isCapturing else { return }
    finalizeTouches(touches, cancelled: true)
  }

  private func finalizeTouches(_ touches: Set<UITouch>, cancelled: Bool) {
    for touch in touches {
      let id = ObjectIdentifier(touch)
      if consumedPartners.remove(id) != nil {
        pendingTouches.removeValue(forKey: id)
        partnerMap.removeValue(forKey: id)
        continue
      }
      guard let pending = pendingTouches.removeValue(forKey: id) else { continue }
      if cancelled {
        partnerMap.removeValue(forKey: id)
        continue
      }

      let releaseNow = touch.timestamp - startedAt
      let durationSec = releaseNow - pending.startTime
      let durationMs = Int(durationSec * 1000)

      let noteType: NoteType
      if let partnerId = partnerMap.removeValue(forKey: id) {
        noteType = .don_both
        consumedPartners.insert(partnerId)
        partnerMap.removeValue(forKey: partnerId)
      } else {
        noteType = singleNoteType(pending: pending)
      }

      let startMs = Int(pending.startTime * 1000)
      let duration: Int? = (durationMs >= Self.holdThresholdMs) ? durationMs : nil
      let note = Note(t: startMs, type: noteType, duration: duration)
      recordedNotes.append(note)
      onNoteRecorded?(note)
    }
  }

  private func tapZone(at point: CGPoint) -> NoteType.Zone {
    let cx = size.width / 2
    let dx = point.x - cx
    let dy = point.y - drumCenterY
    if dx * dx + dy * dy <= drumRadius * drumRadius {
      return .center
    }
    let width = size.width
    if point.x < width * 0.3 {
      return .leftKa
    } else if point.x <= width * 0.7 {
      return .center
    } else {
      return .rightKa
    }
  }

  private func tentativeType(zone: NoteType.Zone, half: CenterHalf?) -> NoteType {
    switch zone {
    case .leftKa: return .ka_l
    case .rightKa: return .ka_r
    case .center: return (half == .left) ? .don_l : .don_r
    case .centerBoth: return .don_both
    }
  }

  private func singleNoteType(pending: PendingTouch) -> NoteType {
    switch pending.zone {
    case .leftKa: return .ka_l
    case .rightKa: return .ka_r
    case .center: return (pending.centerHalf == .left) ? .don_l : .don_r
    case .centerBoth: return .don_both
    }
  }

  // MARK: - Visual

  private func spawnRipple(at position: CGPoint, isDon: Bool) {
    let radius: CGFloat = isDon ? 24 : 18
    let color: SKColor = isDon ? Self.wDon : Self.wKa
    let ripple = SKShapeNode(circleOfRadius: radius)
    ripple.strokeColor = color
    ripple.fillColor = .clear
    ripple.lineWidth = 2
    ripple.position = position
    ripple.zPosition = 20
    ripple.alpha = 0.8
    addChild(ripple)
    ripple.run(SKAction.sequence([
      SKAction.group([
        SKAction.scale(to: 2.0, duration: 0.35),
        SKAction.fadeOut(withDuration: 0.35),
      ]),
      SKAction.removeFromParent(),
    ]))
  }

  // MARK: - Snapshot for handoff

  func makeChartDraft() -> Chart {
    let elapsedMs: Int = isCapturing
      ? Int((CACurrentMediaTime() - startedAt) * 1000)
      : 0
    let now = Date()
    return Chart(
      id: "draft-\(UUID().uuidString.prefix(8))",
      name: "",
      region: "",
      createdAt: now,
      durationMs: elapsedMs,
      notes: recordedNotes.sorted { $0.t < $1.t }
    )
  }
}
