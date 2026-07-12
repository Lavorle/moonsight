import assert from "node:assert/strict";
import test from "node:test";

import { SaveStoreError, WebSaveStore } from "./saveStore.ts";

test("WebSaveStore exposes an awaitable durable write completion point", async () => {
  const writes = [];
  const storage = {
    getItem: () => null,
    setItem: (key, value) => {
      writes.push([key, value]);
    },
  };
  const store = new WebSaveStore(storage);

  const write = store.saveSlot(3, '{"format_version":4}');

  assert.ok(write instanceof Promise);
  await write;
  await store.flush();
  assert.deepEqual(writes, [
    ["moonsight/save/3", '{"format_version":4}'],
  ]);
});

test("WebSaveStore rejects a failed slot write with typed context", async () => {
  const quotaError = new Error("quota exceeded");
  const storage = {
    getItem: () => null,
    setItem: () => {
      throw quotaError;
    },
  };
  const store = new WebSaveStore(storage);

  await assert.rejects(store.saveSlot(2, "{}"), (error) => {
    assert.ok(error instanceof SaveStoreError);
    assert.equal(error.operation, "save-slot");
    assert.equal(error.slot, 2);
    assert.equal(error.cause, quotaError);
    return true;
  });
});

test("TrackedSaveStore reports pending until write and flush complete", async () => {
  const stores = await import("./saveStore.ts");
  assert.equal(typeof stores.TrackedSaveStore, "function");
  let releaseWrite = null;
  const calls = [];
  const events = [];
  const inner = {
    loadPrefs: () => null,
    savePrefs: async () => {},
    loadSlot: () => null,
    saveSlot: async () => {
      calls.push("write");
      await new Promise((resolve) => {
        releaseWrite = resolve;
      });
    },
    flush: async () => {
      calls.push("flush");
    },
  };
  const store = new stores.TrackedSaveStore(inner, (event) => {
    events.push(event);
  });

  const write = store.saveSlot(4, "{}");
  assert.deepEqual(events, [
    { operation: "save-slot", slot: 4, state: "pending" },
  ]);
  let flushed = false;
  const flush = store.flush().then(() => {
    flushed = true;
  });
  await Promise.resolve();
  assert.equal(flushed, false);

  assert.ok(releaseWrite);
  releaseWrite();
  await write;
  await flush;

  assert.deepEqual(calls, ["write", "flush"]);
  assert.deepEqual(events, [
    { operation: "save-slot", slot: 4, state: "pending" },
    { operation: "save-slot", slot: 4, state: "committed" },
  ]);
});

test("TrackedSaveStore serializes concurrent saves and keeps the newest value", async () => {
  const stores = await import("./saveStore.ts");
  const first = Promise.withResolvers();
  const writes = [];
  let calls = 0;
  const inner = {
    loadPrefs: () => null,
    savePrefs: async () => {},
    loadSlot: () => null,
    saveSlot: async (_slot, json) => {
      writes.push(json);
      calls += 1;
      if (calls === 1) await first.promise;
    },
    flush: async () => {},
  };
  const store = new stores.TrackedSaveStore(inner);

  const older = store.saveSlot(0, "older");
  const newer = store.saveSlot(0, "newer");
  await Promise.resolve();
  assert.deepEqual(writes, ["older"]);

  first.resolve();
  await Promise.all([older, newer]);
  await store.flush();
  assert.deepEqual(writes, ["older", "newer"]);
});

test("TrackedSaveStore exposes failed writes and a later retry clears the failure", async () => {
  const stores = await import("./saveStore.ts");
  const failure = new Error("quota exceeded");
  const events = [];
  let fail = true;
  const store = new stores.TrackedSaveStore(
    {
      loadPrefs: () => null,
      savePrefs: async () => {},
      loadSlot: () => null,
      saveSlot: async () => {
        if (fail) throw failure;
      },
      flush: async () => {},
    },
    (event) => events.push(event),
  );

  await assert.rejects(store.saveSlot(2, "first"), failure);
  await assert.rejects(store.flush(), AggregateError);
  fail = false;
  await store.saveSlot(2, "retry");
  await store.flush();

  assert.deepEqual(events, [
    { operation: "save-slot", slot: 2, state: "pending" },
    { operation: "save-slot", slot: 2, state: "failed", error: failure },
    { operation: "save-slot", slot: 2, state: "pending" },
    { operation: "save-slot", slot: 2, state: "committed" },
  ]);
});
