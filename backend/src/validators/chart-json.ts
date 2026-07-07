/**
 * 譜面 JSON 全体のバリデーション。
 *
 * 仕様 (CLAUDE.md §3.7、implementation_plan/backend.md §6):
 *  - id: chart-id バリデーションを通る
 *  - name / region: 文字列
 *  - duration_ms: 0 < x < 600000
 *  - notes: 配列、各要素の type と duration を検証、上限 10,000 件
 */

import { isValidChartId } from "./chart-id.js";
import type { Chart, Note } from "../types/chart.js";
import { VALID_NOTE_TYPES } from "../types/chart.js";

const MAX_NOTES = 10_000;
const MAX_DURATION_MS = 600_000; // 10 分

export interface ChartValidationResult {
  ok: boolean;
  reason?: string;
}

export function validateChartJson(input: unknown): ChartValidationResult {
  if (typeof input !== "object" || input === null) {
    return { ok: false, reason: "chart_json must be object" };
  }
  const chart = input as Partial<Chart>;

  if (!isValidChartId(chart.id)) {
    return { ok: false, reason: "invalid id" };
  }
  if (typeof chart.name !== "string") {
    return { ok: false, reason: "name must be string" };
  }
  if (typeof chart.region !== "string") {
    return { ok: false, reason: "region must be string" };
  }
  if (
    typeof chart.duration_ms !== "number" ||
    !Number.isFinite(chart.duration_ms) ||
    chart.duration_ms <= 0 ||
    chart.duration_ms > MAX_DURATION_MS
  ) {
    return { ok: false, reason: "invalid duration_ms" };
  }
  if (!Array.isArray(chart.notes)) {
    return { ok: false, reason: "notes must be array" };
  }
  if (chart.notes.length > MAX_NOTES) {
    return { ok: false, reason: "too many notes" };
  }
  for (const note of chart.notes) {
    const noteError = validateNote(note, chart.duration_ms);
    if (noteError) {
      return { ok: false, reason: noteError };
    }
  }
  return { ok: true };
}

function validateNote(input: unknown, durationMs: number): string | null {
  if (typeof input !== "object" || input === null) {
    return "note must be object";
  }
  const note = input as Partial<Note>;
  if (
    typeof note.t !== "number" ||
    !Number.isFinite(note.t) ||
    note.t < 0 ||
    !Number.isInteger(note.t)
  ) {
    return "invalid note.t";
  }
  if (typeof note.type !== "string") {
    return "note.type must be string";
  }
  if (!VALID_NOTE_TYPES.includes(note.type as (typeof VALID_NOTE_TYPES)[number])) {
    return `unknown note.type: ${note.type}`;
  }
  if (note.duration !== undefined) {
    if (
      typeof note.duration !== "number" ||
      !Number.isFinite(note.duration) ||
      note.duration < 0 ||
      !Number.isInteger(note.duration) ||
      note.duration > durationMs
    ) {
      return "invalid note.duration";
    }
  }
  return null;
}
