/**
 * 譜面公開 ID のバリデーション。
 *
 * 仕様 (CLAUDE.md §3.7):
 *  - 小英字・数字・ハイフンのみ
 *  - 長さ 3〜64 文字
 *  - URL パスとして安全な範囲
 */

const CHART_ID_PATTERN = /^[a-z0-9-]{3,64}$/;

export function isValidChartId(id: unknown): id is string {
  return typeof id === "string" && CHART_ID_PATTERN.test(id);
}
