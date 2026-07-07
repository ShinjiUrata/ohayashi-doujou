import { describe, it, expect } from "vitest";
import { isValidChartId } from "../../src/validators/chart-id.js";

describe("chart-id validator", () => {
  it("accepts valid ids", () => {
    expect(isValidChartId("shimoda-2026-irihayashi")).toBe(true);
    expect(isValidChartId("abc")).toBe(true);
    expect(isValidChartId("a".repeat(64))).toBe(true);
  });

  it("rejects too short", () => {
    expect(isValidChartId("ab")).toBe(false);
    expect(isValidChartId("")).toBe(false);
  });

  it("rejects too long", () => {
    expect(isValidChartId("a".repeat(65))).toBe(false);
  });

  it("rejects invalid characters", () => {
    expect(isValidChartId("Shimoda")).toBe(false);
    expect(isValidChartId("shimoda_2026")).toBe(false);
    expect(isValidChartId("shimoda 2026")).toBe(false);
    expect(isValidChartId("shimoda!")).toBe(false);
    expect(isValidChartId("こんにちは")).toBe(false);
  });

  it("rejects non-strings", () => {
    expect(isValidChartId(null)).toBe(false);
    expect(isValidChartId(undefined)).toBe(false);
    expect(isValidChartId(123)).toBe(false);
    expect(isValidChartId({})).toBe(false);
  });
});
