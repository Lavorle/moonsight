import assert from "node:assert/strict";
import test from "node:test";

import { DesktopSaveStore } from "../src/lib/desktopSaveStore.ts";

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

async function createStore(invoke) {
  return DesktopSaveStore.create(async (cmd, args) => {
    if (cmd === "read_prefs") return null;
    return invoke(cmd, args);
  }, 0);
}

test("desktop writes return promises and execute serially", async () => {
  const first = deferred();
  const second = deferred();
  const calls = [];
  const store = await createStore((cmd, args) => {
    calls.push([cmd, args]);
    return calls.length === 1 ? first.promise : second.promise;
  });

  const firstWrite = store.saveSlot(1, "one");
  const secondWrite = store.saveSlot(1, "two");
  assert.equal(firstWrite instanceof Promise, true);
  assert.equal(secondWrite instanceof Promise, true);
  await Promise.resolve();
  assert.deepEqual(calls.map(([cmd]) => cmd), ["write_save_slot"]);

  first.resolve();
  await firstWrite;
  await Promise.resolve();
  assert.deepEqual(calls.map(([cmd]) => cmd), [
    "write_save_slot",
    "write_save_slot",
  ]);

  second.resolve();
  await secondWrite;
  assert.equal(store.loadSlot(1), "two");
});

test("flush waits for queued writes then invokes the Rust durability barrier", async () => {
  const write = deferred();
  const calls = [];
  const store = await createStore((cmd, args) => {
    calls.push([cmd, args]);
    if (cmd === "write_prefs") return write.promise;
    if (cmd === "flush_persistence") return Promise.resolve();
    throw new Error(`unexpected command: ${cmd}`);
  });

  const pendingWrite = store.savePrefs("prefs");
  const flush = store.flush();
  await Promise.resolve();
  assert.deepEqual(calls.map(([cmd]) => cmd), ["write_prefs"]);

  write.resolve();
  await pendingWrite;
  await flush;
  assert.deepEqual(calls.map(([cmd]) => cmd), [
    "write_prefs",
    "flush_persistence",
  ]);
});

test("write failures reject both the write and the next flush", async () => {
  const failure = new Error("invoke failed");
  const store = await createStore((cmd) => {
    if (cmd === "write_save_slot") return Promise.reject(failure);
    if (cmd === "flush_persistence") return Promise.resolve();
    throw new Error(`unexpected command: ${cmd}`);
  });

  await assert.rejects(store.saveSlot(2, "broken"), failure);
  await assert.rejects(store.flush(), failure);
});
