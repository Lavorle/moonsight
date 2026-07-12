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

test("hydration enumerates the configured slot count without seeding bad data", async () => {
  const slots = await import("./saveSlots.ts");
  assert.equal(typeof slots.hydrateStoredSlots, "function");
  const loads: number[] = [];
  const seeded: Array<[number, string]> = [];
  const bodies = new Map<number, string>([
    [0, '{"format_version":4,"scene":"start","ip":0}'],
    [1, "broken"],
    [19, '{"format_version":99}'],
  ]);
  const store = {
    loadPrefs: () => null,
    savePrefs: async () => {},
    loadSlot: (slot: number) => {
      loads.push(slot);
      return bodies.get(slot) ?? null;
    },
    saveSlot: async () => {},
    flush: async () => {},
  };

  const states = slots.hydrateStoredSlots(store, 20, (slot, json) => {
    seeded.push([slot, json]);
  });

  assert.deepEqual(loads, Array.from({ length: 20 }, (_, i) => i));
  assert.deepEqual(seeded, [[0, bodies.get(0)!]]);
  assert.equal(states.length, 20);
  assert.equal(states[1].state, "occupied-corrupt");
  assert.equal(states[19].state, "occupied-incompatible");
});
