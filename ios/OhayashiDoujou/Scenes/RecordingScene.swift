import SpriteKit
import Foundation

/// 録音画面の SpriteKit シーン。
///
/// Phase 3:
/// - 太鼓を中央で左右分割表示(録音中のみ)
/// - 外側のカッゾーン(左外・右外)
/// - タップ位置から type を判別(`ka_l` / `don_l` / `don_r` / `ka_r`)
/// - 中央左右半分に 50ms 以内の 2 タッチで `don_both` として合成
/// - 500ms 以上押し続けたタッチはホールドノート(`duration` 付き)として記録
/// - 打点ごとに効果音 + 触覚 + タップ位置の波紋
///
/// 落とし穴対策は `implementation_notes/ios_pitfalls.md` §21-22 を参照。
@MainActor
final class RecordingScene: SKScene {
  // MARK: - Constants
  /// 両手同時打の 2 タッチ同時判定ウィンドウ。
  private static let bothPairWindowSec: TimeInterval = 0.05
  /// これ以上押し続けたらホールドとして記録する閾値。
  private static let holdThresholdMs: Int = 500
  /// 太鼓の描画パラメータ(タップ判定でも同じ値を参照するため定数化)。
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
  /// 両手同時打として組んだペアの相方 ID。双方向に登録する。
  private var partnerMap: [ObjectIdentifier: ObjectIdentifier] = [:]
  /// 相方の release が来たときに二重ノート追加を防ぐためのマーク。
  private var consumedPartners: Set<ObjectIdentifier> = []

  // MARK: - Scene lifecycle
  private var didLayout = false
  private(set) var isCapturing = false

  override func didMove(to view: SKView) {
    view.isMultipleTouchEnabled = true
    view.ignoresSiblingOrder = true
    view.allowsTransparency = true
    // 和風 UI: 背景は SwiftUI 側の WafuuBackground を透過して表示する
    backgroundColor = .clear
    scaleMode = .resizeFill

    // レイアウトは初回のみ(SwiftUI 側の再描画で didMove が
    // 複数回呼ばれてもノードが重複しないようにする)
    guard !didLayout else { return }
    layoutStatic()
    didLayout = true
  }

  /// カウントダウン終了後に SwiftUI 側から呼び出す。
  /// この呼び出しから録音開始 (打点の記録・効果音・触覚が有効化) される。
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
    layoutInstruction()
  }

  private func layoutKaZones() {
    let width = size.width
    let height = size.height * 0.6

    // 左外ゾーン
    let leftZone = SKShapeNode(rect: CGRect(x: 0, y: 0, width: width * 0.3, height: height))
    leftZone.fillColor = SKColor(red: 0x4e / 255.0, green: 0xa7 / 255.0, blue: 0xd9 / 255.0, alpha: 0.1)
    leftZone.strokeColor = SKColor(red: 0x4e / 255.0, green: 0xa7 / 255.0, blue: 0xd9 / 255.0, alpha: 0.3)
    leftZone.lineWidth = 1
    leftZone.zPosition = -5
    addChild(leftZone)

    // 右外ゾーン
    let rightZone = SKShapeNode(
      rect: CGRect(x: width * 0.7, y: 0, width: width * 0.3, height: height)
    )
    rightZone.fillColor = leftZone.fillColor
    rightZone.strokeColor = leftZone.strokeColor
    rightZone.lineWidth = 1
    rightZone.zPosition = -5
    addChild(rightZone)

    let kaColor = SKColor(red: 0xcb / 255.0, green: 0xe9 / 255.0, blue: 0xf6 / 255.0, alpha: 1)

    let leftLabel = SKLabelNode(fontNamed: "HiraginoSans-W6")
    leftLabel.text = "左カッ"
    leftLabel.fontSize = 12
    leftLabel.fontColor = kaColor
    leftLabel.position = CGPoint(x: width * 0.15, y: height / 2)
    leftLabel.zPosition = 1
    addChild(leftLabel)

    let leftCode = SKLabelNode(fontNamed: "Menlo")
    leftCode.text = "ka_l"
    leftCode.fontSize = 9
    leftCode.fontColor = kaColor.withAlphaComponent(0.6)
    leftCode.position = CGPoint(x: width * 0.15, y: height / 2 - 20)
    leftCode.zPosition = 1
    addChild(leftCode)

    let rightLabel = SKLabelNode(fontNamed: "HiraginoSans-W6")
    rightLabel.text = "右カッ"
    rightLabel.fontSize = 12
    rightLabel.fontColor = kaColor
    rightLabel.position = CGPoint(x: width * 0.85, y: height / 2)
    rightLabel.zPosition = 1
    addChild(rightLabel)

    let rightCode = SKLabelNode(fontNamed: "Menlo")
    rightCode.text = "ka_r"
    rightCode.fontSize = 9
    rightCode.fontColor = kaColor.withAlphaComponent(0.6)
    rightCode.position = CGPoint(x: width * 0.85, y: height / 2 - 20)
    rightCode.zPosition = 1
    addChild(rightCode)
  }

  private func layoutDrumSplit() {
    let width = size.width
    let cx = width / 2
    let cy: CGFloat = drumCenterY

    // 太鼓本体
    let drum = SKShapeNode(circleOfRadius: drumRadius)
    drum.fillColor = SKColor(red: 0xc8 / 255.0, green: 0x21 / 255.0, blue: 0x1d / 255.0, alpha: 1)
    drum.strokeColor = SKColor(red: 0x4a / 255.0, green: 0x26 / 255.0, blue: 0x18 / 255.0, alpha: 1)
    drum.lineWidth = 4
    drum.position = CGPoint(x: cx, y: cy)
    drum.zPosition = 1
    addChild(drum)

    // 中央の分割線(黄色破線)
    let dividerPath = CGMutablePath()
    dividerPath.move(to: CGPoint(x: cx, y: cy - drumRadius + 20))
    dividerPath.addLine(to: CGPoint(x: cx, y: cy + drumRadius - 20))
    let divider = SKShapeNode(path: dividerPath)
    divider.strokeColor = SKColor(red: 0xf4 / 255.0, green: 0xc9 / 255.0, blue: 0x5d / 255.0, alpha: 0.6)
    divider.lineWidth = 2
    // 破線
    divider.strokeShader = nil
    divider.zPosition = 3
    addChild(divider)

    // ラベル: 左ドン / 右ドン
    let don = SKColor.white
    let dot = SKColor(red: 1, green: 1, blue: 1, alpha: 0.55)

    let ll = SKLabelNode(fontNamed: "HiraginoSans-W6")
    ll.text = "左ドン"
    ll.fontSize = 13
    ll.fontColor = don
    ll.position = CGPoint(x: cx - 60, y: cy + 30)
    ll.zPosition = 4
    addChild(ll)

    let lc = SKLabelNode(fontNamed: "Menlo")
    lc.text = "don_l"
    lc.fontSize = 9
    lc.fontColor = dot
    lc.position = CGPoint(x: cx - 60, y: cy + 12)
    lc.zPosition = 4
    addChild(lc)

    let rl = SKLabelNode(fontNamed: "HiraginoSans-W6")
    rl.text = "右ドン"
    rl.fontSize = 13
    rl.fontColor = don
    rl.position = CGPoint(x: cx + 60, y: cy + 30)
    rl.zPosition = 4
    addChild(rl)

    let rc = SKLabelNode(fontNamed: "Menlo")
    rc.text = "don_r"
    rc.fontSize = 9
    rc.fontColor = dot
    rc.position = CGPoint(x: cx + 60, y: cy + 12)
    rc.zPosition = 4
    addChild(rc)
  }

  private func layoutInstruction() {
    let label = SKLabelNode(fontNamed: "HiraginoSans-W3")
    label.text = "左右を意識して太鼓を叩いてください"
    label.fontSize = 11
    label.fontColor = SKColor(red: 0xf5 / 255.0, green: 0xea / 255.0, blue: 0xd0 / 255.0, alpha: 0.5)
    label.position = CGPoint(x: size.width / 2, y: size.height - 40)
    label.zPosition = 10
    addChild(label)
  }

  // MARK: - Touch handling

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    // カウントダウン中 (isCapturing = false) は完全に無視。
    // 効果音 / 触覚 / ripple / 記録すべて発火しない。
    guard isCapturing else { return }
    var newlyRegistered: [ObjectIdentifier] = []
    for touch in touches {
      // touch.timestamp は iOS がタッチ発生を実際に検出した時刻。
      // CACurrentMediaTime() と同じ「システム起動からの秒数」基準なので
      // startedAt との差分がそのまま経過秒になり、コールバック遅延に強い。
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

      // 効果音 + 触覚(暫定的な type で発火)
      let tentative = tentativeType(zone: zone, half: half)
      AudioEngine.shared.play(for: tentative)
      Haptics.shared.fire(for: tentative)

      // 視覚エフェクト
      spawnRipple(at: position, isDon: zone == .center)
    }

    // 両手同時打の相方を探す(newlyRegistered した各タッチの startTime を基準に判定)
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
      // 相方によって既に処理済みなら、この release ではノート追加しない
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

      // release 時刻も touch.timestamp を使う(コールバック遅延の影響を除外)
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
    // 太鼓の円の内部なら中央(ドン)扱い。カッのゾーンにわずかにはみ出す
    // 太鼓の円弧を実物の判定境界として尊重する。
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
    let radius: CGFloat = isDon ? 26 : 18
    let color: SKColor = isDon
      ? SKColor(red: 0xff / 255.0, green: 0x6b / 255.0, blue: 0x6b / 255.0, alpha: 1)
      : SKColor(red: 0x8f / 255.0, green: 0xd1 / 255.0, blue: 0xf4 / 255.0, alpha: 1)
    let ripple = SKShapeNode(circleOfRadius: radius)
    ripple.strokeColor = color
    ripple.fillColor = .clear
    ripple.lineWidth = 2
    ripple.glowWidth = 4
    ripple.position = position
    ripple.zPosition = 20
    ripple.alpha = 0.8
    addChild(ripple)
    ripple.run(SKAction.sequence([
      SKAction.group([
        SKAction.scale(to: 2.2, duration: 0.35),
        SKAction.fadeOut(withDuration: 0.35),
      ]),
      SKAction.removeFromParent(),
    ]))
  }

  // MARK: - Snapshot for handoff

  /// 現在の録音状態から Chart を組み立てる。停止ボタン押下時に呼び出す。
  func makeChartDraft() -> Chart {
    let elapsedMs: Int = isCapturing
      ? Int((CACurrentMediaTime() - startedAt) * 1000)
      : 0
    let now = Date()
    // 空メタデータのドラフト(編集画面で入力する)
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
