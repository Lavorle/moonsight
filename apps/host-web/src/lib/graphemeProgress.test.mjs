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
