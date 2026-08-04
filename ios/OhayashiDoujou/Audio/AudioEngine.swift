import AVFoundation
import Foundation

/// ドン / カッ の効果音を低遅延で再生する。
///
/// 実装方針(`implementation_notes/ios_pitfalls.md` §1-3 参照):
/// - `AVAudioEngine` + `AVAudioPCMBuffer` プリロード。
/// - `AVAudioSession` は `.playback` + `.mixWithOthers`(マナーモードでも鳴る、他アプリの音を止めない)。
/// - 連打対応で、同じ type について複数の `AVAudioPlayerNode` を round-robin で使う。
///
/// Phase 1 段階では最小構成。Phase 6 で音源差し替え、Phase 6 でエフェクト追加。
@MainActor
public final class AudioEngine {
  public static let shared = AudioEngine()

  private let engine = AVAudioEngine()
  private var buffers: [SoundKey: AVAudioPCMBuffer] = [:]
  private var players: [SoundKey: [AVAudioPlayerNode]] = [:]
  private var roundRobinIndex: [SoundKey: Int] = [:]
  private var isStarted = false

  private static let playersPerSound = 4

  public enum SoundKey: Hashable, Sendable {
    case don
    case ka

    fileprivate var resourceName: String {
      switch self {
      case .don: return "don"
      case .ka: return "ka"
      }
    }
  }

  private init() {}

  /// 起動時に一度呼ぶ。
  public func start() {
    guard !isStarted else { return }
    configureAudioSession()
    preloadBuffers()
    attachPlayers()
    do {
      try engine.start()
      isStarted = true
    } catch {
      // Phase 1: ログのみ、Phase 6 でエラーハンドリング強化
      print("[AudioEngine] engine.start() failed: \(error)")
    }
    observeInterruptions()
  }

  /// 効果音を即時再生する。
  public func play(_ key: SoundKey) {
    // 事前チェック: engine が止まっていたら再起動を試みる。
    // 音声セッションの中断や、SwiftUI/SpriteKit の状態遷移中に
    // engine が silently 停止するケースへの防御(silent fail 対策)。
    if !engine.isRunning {
      isStarted = false
      start()
    }
    guard let buffer = buffers[key] else { return }
    guard let node = nextPlayer(for: key) else { return }
    // すでに再生中の場合は止めて、頭から鳴らし直す(連打時の反応性優先)。
    if node.isPlaying {
      node.stop()
    }
    node.scheduleBuffer(buffer, at: nil, options: [.interrupts])
    node.play()
  }

  /// NoteType から SoundKey を得る。ドン系はドン、カッ系はカッ、両手打はドンを鳴らす。
  public func play(for noteType: NoteType) {
    switch noteType {
    case .don_l, .don_r, .don_both:
      play(.don)
    case .ka_l, .ka_r:
      play(.ka)
    }
  }

  // MARK: - Private

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true, options: [])
    } catch {
      print("[AudioEngine] audio session config failed: \(error)")
    }
  }

  private func preloadBuffers() {
    for key in [SoundKey.don, .ka] {
      guard let url = Bundle.main.url(forResource: key.resourceName, withExtension: "wav") else {
        assertionFailure("Missing audio resource: \(key.resourceName).wav")
        continue
      }
      do {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
          pcmFormat: file.processingFormat,
          frameCapacity: AVAudioFrameCount(file.length)
        ) else {
          assertionFailure("Failed to allocate PCM buffer for \(key.resourceName)")
          continue
        }
        try file.read(into: buffer)
        buffers[key] = buffer
      } catch {
        print("[AudioEngine] failed to load \(key.resourceName): \(error)")
      }
    }
  }

  private func attachPlayers() {
    let format = buffers.values.first?.format
    for key in [SoundKey.don, .ka] {
      var nodes: [AVAudioPlayerNode] = []
      for _ in 0..<Self.playersPerSound {
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        nodes.append(node)
      }
      players[key] = nodes
      roundRobinIndex[key] = 0
    }
  }

  private func nextPlayer(for key: SoundKey) -> AVAudioPlayerNode? {
    guard let nodes = players[key], !nodes.isEmpty else { return nil }
    let idx = roundRobinIndex[key] ?? 0
    let node = nodes[idx % nodes.count]
    roundRobinIndex[key] = (idx + 1) % nodes.count
    return node
  }

  private func observeInterruptions() {
    let nc = NotificationCenter.default
    nc.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self else { return }
      guard let info = notification.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
      Task { @MainActor in
        switch type {
        case .began:
          self.isStarted = false
        case .ended:
          self.start()
        @unknown default:
          break
        }
      }
    }
    nc.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.isStarted = false
        self?.start()
      }
    }
  }
}
