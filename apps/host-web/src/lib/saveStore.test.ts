import assert from "node:assert/strict";
import test from "node:test";

import { WebSaveStore } from "./saveStore.ts";

test("WebSaveStore exposes an awaitable durable write completion point", async () => {
  const writes: Array<[string, string]> = [];
  const storage = {
    getItem: () => null,
    setItem: (key: string, value: string) => {
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
