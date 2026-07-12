import assert from "node:assert/strict";
import test from "node:test";

test("stored slots distinguish empty, corrupt, incompatible, and valid data", async () => {
  const slots = await import("./saveSlots.ts").catch(() => null);
  assert.ok(slots, "saveSlots module should exist");

  assert.equal(slots.classifyStoredSlot(0, null).state, "empty");
  assert.equal(
    slots.classifyStoredSlot(1, "not json").state,
    "occupied-corrupt",
  );
  assert.deepEqual(
    slots.classifyStoredSlot(2, '{"format_version":99}'),
    {
      slot: 2,
      state: "occupied-incompatible",
      formatVersion: 99,
      message: "Unsupported save format 99",
    },
  );
  assert.equal(
    slots.classifyStoredSlot(
      3,
      '{"format_version":4,"module_id":"demo","scene":"start","ip":0}',
    ).state,
    "occupied-valid",
  );
});
