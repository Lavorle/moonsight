import assert from "node:assert/strict";
import test from "node:test";

import {
  loadGameBundle,
  loadGameContent,
  validateContentManifest,
} from "./wasm.ts";

function response({ ok = true, status = 200, bytes = [], text = "" } = {}) {
  return {
    ok,
    status,
    arrayBuffer: async () => Uint8Array.from(bytes).buffer,
    text: async () => text,
  };
}

test("production requires a valid manifest while demo mode permits its absence", () => {
  assert.throws(
    () => validateContentManifest(null, "production", "./manifest.json"),
    /manifest\.json.*missing or invalid/,
  );
  assert.throws(
    () => validateContentManifest([], "production", "custom.json"),
    /custom\.json.*missing or invalid/,
  );
  assert.deepEqual(
    validateContentManifest({ name: "game" }, "production", "custom.json"),
    { name: "game" },
  );
  assert.equal(validateContentManifest(null, "demo", "custom.json"), null);
});

test("whole-bundle digest mismatch is rejected before runtime mutation", async () => {
  let mutations = 0;
  await assert.rejects(
    loadGameBundle(
      { load_msb: () => (mutations += 1) },
      { digests: { "game.msb": "0".repeat(64) } },
      "production",
      async () => response({ bytes: [1, 2, 3] }),
      async () => "f".repeat(64),
    ),
    /digest mismatch.*game\.msb/,
  );
  assert.equal(mutations, 0);
});

test("whole-bundle preflight validates every artifact before installing MSB2", async () => {
  const calls = [];
  let mutations = 0;
  const digest = "a".repeat(64);
  const result = await loadGameBundle(
    { load_msb: () => (mutations += 1, 0) },
    { digests: { "game.msb": digest, "assets/bg.png": digest } },
    "production",
    async (url) => {
      calls.push(url);
      return response({ bytes: [1, 2, 3] });
    },
    async () => digest,
  );
  assert.equal(result, "game.msb");
  assert.equal(mutations, 1);
  assert.deepEqual(calls, ["./game.msb", "./assets/bg.png"]);
});

test("production content boot rejects a missing game.msb without demo fallback", async () => {
  const calls = [];
  const runtime = {
    load_msb: () => assert.fail("missing content must not reach the runtime"),
    load_source: () => assert.fail("production must not load demo.yuki"),
    init_demo: () => assert.fail("production must not initialize the demo"),
  };

  await assert.rejects(
    loadGameContent(runtime, undefined, async (url) => {
      calls.push(url);
      return response({ ok: false, status: 404 });
    }),
    /game\.msb.*HTTP 404/,
  );
  assert.deepEqual(calls, ["./game.msb"]);
});

test("production content boot rejects fetch failures, empty content, and a missing loader", async (t) => {
  await t.test("fetch failure", async () => {
    await assert.rejects(
      loadGameContent({ load_msb: () => 0 }, "production", async () => {
        throw new Error("network offline");
      }),
      /game\.msb.*network offline/,
    );
  });

  await t.test("empty content", async () => {
    await assert.rejects(
      loadGameContent(
        { load_msb: () => assert.fail("empty content must not be loaded") },
        "production",
        async () => response(),
      ),
      /game\.msb.*empty/,
    );
  });

  await t.test("missing runtime export", async () => {
    await assert.rejects(
      loadGameContent({}, "production", async () =>
        response({ bytes: [1, 2, 3] }),
      ),
      /load_msb.*unavailable/,
    );
  });
});

test("production content boot rejects runtime errors and non-zero return codes", async (t) => {
  await t.test("runtime throws while decoding corrupt content", async () => {
    await assert.rejects(
      loadGameContent(
        {
          load_msb: () => {
            throw new Error("decoder trapped");
          },
        },
        "production",
        async () => response({ bytes: [1, 2, 3] }),
      ),
      /game\.msb.*decoder trapped/,
    );
  });

  await t.test("runtime rejects content", async () => {
    await assert.rejects(
      loadGameContent(
        { load_msb: () => 7 },
        "production",
        async () => response({ bytes: [1, 2, 3] }),
      ),
      /game\.msb.*return code 7/,
    );
  });
});

test("production content boot accepts a non-empty game.msb", async () => {
  let raw = "";
  const result = await loadGameContent(
    {
      load_msb: (value) => {
        raw = value;
        return 0;
      },
    },
    "production",
    async () => response({ bytes: [0, 127, 255] }),
  );

  assert.equal(result, "game.msb");
  assert.deepEqual(
    Array.from(raw, (char) => char.charCodeAt(0)),
    [0, 127, 255],
  );
});

test("only explicit demo mode falls back to demo.yuki and init_demo", async (t) => {
  await t.test("demo.yuki fallback", async () => {
    const calls = [];
    let source = "";
    const result = await loadGameContent(
      {
        load_msb: () => 9,
        load_source: (value) => {
          source = value;
          return 0;
        },
        init_demo: () => assert.fail("source fallback should be sufficient"),
      },
      "demo",
      async (url) => {
        calls.push(url);
        return url === "./game.msb"
          ? response({ bytes: [1] })
          : response({ text: "scene start" });
      },
    );

    assert.equal(result, "demo.yuki");
    assert.equal(source, "scene start");
    assert.deepEqual(calls, ["./game.msb", "./demo.yuki"]);
  });

  await t.test("built-in demo fallback", async () => {
    let initialized = 0;
    const result = await loadGameContent(
      {
        load_msb: () => 1,
        load_source: () => 1,
        init_demo: () => {
          initialized += 1;
        },
      },
      "demo",
      async (url) =>
        url === "./game.msb"
          ? response({ bytes: [1] })
          : response({ text: "bad source" }),
    );

    assert.equal(result, "init_demo");
    assert.equal(initialized, 1);
  });
});
