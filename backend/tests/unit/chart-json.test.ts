import { describe, it, expect } from "vitest";
import { validateChartJson } from "../../src/validators/chart-json.js";

const validBase = {
  id: "test-2026",
  name: "テスト譜面",
  region: "テスト町",
  created_at: "2026-01-01T00:00:00Z",
  duration_ms: 5000,
  notes: [
    { t: 0, type: "don_l" },
    { t: 500, type: "ka_r" },
    { t: 1000, type: "don_both" },
    { t: 1500, type: "don_r", duration: 800 },
  ],
};

describe("chart-json validator", () => {
  it("accepts a valid chart", () => {
    expect(validateChartJson(validBase).ok).toBe(true);
  });

  it("rejects invalid id", () => {
    expect(validateChartJson({ ...validBase, id: "AB" }).ok).toBe(false);
  });

  it("rejects invalid duration_ms", () => {
    expect(validateChartJson({ ...validBase, duration_ms: 0 }).ok).toBe(false);
    expect(validateChartJson({ ...validBase, duration_ms: -1 }).ok).toBe(false);
    expect(validateChartJson({ ...validBase, duration_ms: 700_000 }).ok).toBe(false);
  });

  it("rejects unknown note type", () => {
    expect(
      validateChartJson({
        ...validBase,
        notes: [{ t: 0, type: "unknown_type" }],
      }).ok,
    ).toBe(false);
  });

  it("rejects negative t", () => {
    expect(
      validateChartJson({ ...validBase, notes: [{ t: -1, type: "don_l" }] }).ok,
    ).toBe(false);
  });

  it("rejects duration exceeding duration_ms", () => {
    expect(
      validateChartJson({
        ...validBase,
        duration_ms: 1000,
        notes: [{ t: 0, type: "don_l", duration: 2000 }],
      }).ok,
    ).toBe(false);
  });

  it("rejects too many notes", () => {
    const notes = Array.from({ length: 20_000 }, (_, i) => ({
      t: i,
      type: "don_l" as const,
    }));
    expect(validateChartJson({ ...validBase, notes }).ok).toBe(false);
  });
});
