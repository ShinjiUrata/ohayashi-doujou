import Foundation

/// Phase 2 の動作確認用ダミー譜面。
///
/// Phase 3-4 で ChartStorage から実譜面を読み込む形に置き換わる。
public enum DemoChart {
  public static let phase2Demo: Chart = {
    // 18 秒程度の練習譜面。両手同時打・ホールドの検証も含む。
    let notes: [Note] = [
      Note(t: 2000,  type: .don_l),
      Note(t: 2600,  type: .ka_r),
      Note(t: 3200,  type: .don_r),
      Note(t: 3800,  type: .ka_l),
      Note(t: 4400,  type: .don_l),
      Note(t: 5000,  type: .don_r),
      Note(t: 6000,  type: .don_both),
      Note(t: 6800,  type: .ka_l),
      Note(t: 7400,  type: .don_r),
      Note(t: 8000,  type: .don_l),
      Note(t: 8600,  type: .ka_r),
      Note(t: 9400,  type: .don_both),
      Note(t: 10200, type: .don_r, duration: 800),
      Note(t: 11400, type: .ka_l),
      Note(t: 12000, type: .don_l),
      Note(t: 12600, type: .don_r),
      Note(t: 13400, type: .ka_r),
      Note(t: 14000, type: .don_both),
      Note(t: 14800, type: .don_l, duration: 600),
      Note(t: 16000, type: .ka_l),
      Note(t: 16600, type: .don_r),
      Note(t: 17200, type: .don_l),
      Note(t: 17800, type: .don_both),
      // フィナーレ: 両手同時打ホールド(1200ms)
      Note(t: 19000, type: .don_both, duration: 1200),
    ]
    return Chart(
      id: "demo-phase2",
      name: "練習譜面",
      region: "デモ",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      durationMs: 21_000,
      notes: notes
    )
  }()
}
