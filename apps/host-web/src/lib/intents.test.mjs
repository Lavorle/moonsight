import assert from "node:assert/strict";
import test from "node:test";

test("rollback uses the reserved code after selectable rows", async () => {
  const intents = await import("./intents.ts");
  assert.equal(intents.INTENT_SELECT_BASE, 10);
  assert.equal(intents.INTENT_ROLLBACK, 19);
});
