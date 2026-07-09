/**
 * 譜面 JSON の型定義。
 * iOS 側の Chart.swift / Note.swift と一致させる。
 */

export type NoteType =
  | "don_l"
  | "don_r"
  | "ka_l"
  | "ka_r"
  | "don_both";

export const VALID_NOTE_TYPES: readonly NoteType[] = [
  "don_l",
  "don_r",
  "ka_l",
  "ka_r",
  "don_both",
];

export interface Note {
  t: number;             // 経過ミリ秒 (非負整数)
  type: NoteType;
  duration?: number;     // ホールドの継続 ms (Optional、省略 or 0 は単発)
}

export interface Chart {
  id: string;            // 公開 ID (小英字・数字・ハイフン、3-64文字)
  name: string;
  region: string;
  created_at: string;    // ISO8601 (サーバー側で上書き)
  duration_ms: number;
  notes: Note[];
}
