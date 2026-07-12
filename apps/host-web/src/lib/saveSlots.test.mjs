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

test("runtime load diagnostics distinguish cross-project from corrupt saves", async () => {
  const slots = await import("./saveSlots.ts");
  assert.deepEqual(
    slots.classifyRuntimeLoadFailure(
      2,
      4,
      "save module_id mismatch: expected current, found other",
    ),
    {
      slot: 2,
      state: "occupied-incompatible",
      formatVersion: 4,
      message: "save module_id mismatch: expected current, found other",
    },
  );
  assert.deepEqual(
    slots.classifyRuntimeLoadFailure(
      3,
      4,
      "save instruction pointer 99 is invalid for scene main",
    ),
    {
      slot: 3,
      state: "occupied-corrupt",
      message: "save instruction pointer 99 is invalid for scene main",
    },
  );
});

test("hydration enumerates the configured slot count without seeding bad data", async () => {
  const slots = await import("./saveSlots.ts");
  assert.equal(typeof slots.hydrateStoredSlots, "function");
  const loads = [];
  const seeded = [];
  const bodies = new Map([
    [0, '{"format_version":4,"scene":"start","ip":0}'],
    [1, "broken"],
    [19, '{"format_version":99}'],
  ]);
  const store = {
    loadPrefs: () => null,
    savePrefs: async () => {},
    loadSlot: (slot) => {
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
  assert.deepEqual(seeded, [[0, bodies.get(0)]]);
  assert.equal(states.length, 20);
  assert.equal(states[1].state, "occupied-corrupt");
  assert.equal(states[19].state, "occupied-incompatible");
});

test("manifest slot counts share the 1..20 clamp contract", async () => {
  const slots = await import("./saveSlots.ts");
  assert.equal(typeof slots.clampSaveSlotCount, "function");

  assert.equal(slots.clampSaveSlotCount(0), 1);
  assert.equal(slots.clampSaveSlotCount(1), 1);
  assert.equal(slots.clampSaveSlotCount(6), 6);
  assert.equal(slots.clampSaveSlotCount(20), 20);
  assert.equal(slots.clampSaveSlotCount(21), 20);
  assert.equal(slots.clampSaveSlotCount("not-a-number"), 6);
});

test("v2 through v5 remain compatible while older and future saves do not", async () => {
  const slots = await import("./saveSlots.ts");

  for (const formatVersion of [2, 3, 4, 5]) {
    assert.equal(
      slots.classifyStoredSlot(
        formatVersion,
        JSON.stringify({ format_version: formatVersion }),
      ).state,
      "occupied-valid",
    );
  }
  for (const formatVersion of [1, 6, 99]) {
    assert.equal(
      slots.classifyStoredSlot(
        formatVersion,
        JSON.stringify({ format_version: formatVersion }),
      ).state,
      "occupied-incompatible",
    );
  }
});

test("hydration clamps and enumerates exactly 1, 6, or 20 slots", async () => {
  const slots = await import("./saveSlots.ts");

  for (const slotCount of [1, 6, 20]) {
    const loads = [];
    const states = slots.hydrateStoredSlots(
      {
        loadPrefs: () => null,
        savePrefs: async () => {},
        loadSlot: (slot) => {
          loads.push(slot);
          return null;
        },
        saveSlot: async () => {},
        flush: async () => {},
      },
      slotCount,
      () => assert.fail("empty slots must not be seeded"),
    );

    assert.deepEqual(loads, Array.from({ length: slotCount }, (_, i) => i));
    assert.equal(states.length, slotCount);
  }
});

test("hydration reports read failures without treating them as empty", async () => {
  const slots = await import("./saveSlots.ts");
  const states = slots.hydrateStoredSlots(
    {
      loadPrefs: () => null,
      savePrefs: async () => {},
      loadSlot: () => {
        throw new Error("permission denied");
      },
      saveSlot: async () => {},
      flush: async () => {},
    },
    1,
    () => assert.fail("failed reads must not be seeded"),
  );

  assert.deepEqual(states, [
    { slot: 0, state: "read-failed", message: "permission denied" },
  ]);
});
