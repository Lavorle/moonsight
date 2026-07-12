import assert from "node:assert/strict";
import test from "node:test";

test("grapheme progress never splits combining or emoji clusters", async () => {
  const { remapGraphemeProgress } = await import("./graphemeProgress.ts");
  const oldText = "A👨‍👩‍👧‍👦B";
  const familyEnd = "A👨‍👩‍👧‍👦".length;
  assert.equal(remapGraphemeProgress(oldText, familyEnd, "é好Z", false), 3);
  assert.equal(remapGraphemeProgress(oldText, 2, "é好Z", false), 2);
  assert.equal(remapGraphemeProgress(oldText, 0, "é好Z", true), 4);
});

test("warm grapheme handoff p95 stays within the 16ms locale-switch gate", async () => {
  const { remapGraphemeProgress } = await import("./graphemeProgress.ts");
  const samples = [];
  for (let i = 0; i < 1000; i += 1) {
    const start = performance.now();
    remapGraphemeProgress("A👨‍👩‍👧‍👦B", 12, "é好Z", false);
    samples.push(performance.now() - start);
  }
  samples.sort((a, b) => a - b);
  const p95 = samples[Math.floor(samples.length * 0.95)];
  assert.ok(p95 <= 16, `warm grapheme handoff p95 ${p95}ms exceeds 16ms`);
});

test("cold grapheme segmenter p95 stays within the 100ms locale-switch gate", () => {
  const samples = [];
  for (let i = 0; i < 100; i += 1) {
    const start = performance.now();
    const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
    Array.from(segmenter.segment("A👨‍👩‍👧‍👦é好Z"));
    samples.push(performance.now() - start);
  }
  samples.sort((a, b) => a - b);
  const p95 = samples[Math.floor(samples.length * 0.95)];
  assert.ok(p95 <= 100, `cold grapheme segmenter p95 ${p95}ms exceeds 100ms`);
});
