/**
 * MoonSight browser boot: load wasm-gc host, wire input, rAF game loop.
 *
 * Expects:
 *   - ./webgpu_bridge.js (ES module)
 *   - ./host_web.wasm (or ?wasm= path) built from host_web package
 *   - optional ./manifest.json  { "resources": { "id": "url", ... } }
 *   - optional ./game.msb or ./demo.yuki (source via load_source)
 */

import * as Gpu from "./webgpu_bridge.js";

const PACK_HEADER = 4;
const SPRITE_STRIDE = 7;
const GLYPH_STRIDE = 10;

const SAVE_KEY = (slot) => `moonsight/save/${slot}`;

/** @type {WebAssembly.Exports | null} */
let exports_ = null;

/** pending intent for next frame */
let pendingIntent = 0;
let lastTs = 0;
let saveSlot = 0;

/**
 * Copy last packed frame into a Float32Array via frame_at.
 * Wasm-GC arrays are opaque to JS.
 */
function copyFrame(exports) {
  const n = exports.frame_len() | 0;
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) out[i] = exports.frame_at(i);
  return out;
}

function resolveRes(resId) {
  if (!exports_) return resId;
  try {
    const name = exports_.resource_name(resId | 0);
    if (name && name.length) return name;
  } catch (_) {
    /* ignore */
  }
  return resId;
}

/**
 * Rasterize pending glyphs reported by MoonBit atlas bookkeeping.
 */
function flushPendingGlyphs(exports) {
  const n = exports.pending_glyph_count() | 0;
  if (n <= 0) return;
  for (let i = 0; i < n; i++) {
    const cp = exports.pending_glyph_cp(i) | 0;
    const size = exports.pending_glyph_size(i) | 0;
    const atlasX = exports.pending_glyph_atlas_x(i) | 0;
    const atlasY = exports.pending_glyph_atlas_y(i) | 0;
    const atlasW = exports.pending_glyph_atlas_w(i) | 0;
    const atlasH = exports.pending_glyph_atlas_h(i) | 0;
    if (size <= 0 || atlasW <= 0 || atlasH <= 0) continue;
    const ch = String.fromCodePoint(cp);
    try {
      // Stamp pixels into the UV rect MoonBit already packed into the draw list.
      Gpu.rasterizeGlyphToAtlas(
        ch,
        size,
        atlasX,
        atlasY,
        atlasW,
        atlasH,
        1024,
      );
      exports.mark_glyph_ready(cp, size, atlasX, atlasY, atlasW, atlasH);
    } catch (e) {
      console.warn("glyph rasterize failed", ch, e);
    }
  }
  exports.clear_pending_glyphs();
}

function drawPack(pack) {
  if (pack.length < PACK_HEADER) return;
  const sc = pack[1] | 0;
  const gc = pack[2] | 0;
  const veil = pack[3];
  const spriteStart = PACK_HEADER;
  const spriteEnd = spriteStart + sc * SPRITE_STRIDE;
  const glyphEnd = spriteEnd + gc * GLYPH_STRIDE;
  const sprites = pack.subarray(spriteStart, spriteEnd);
  const glyphs = pack.subarray(spriteEnd, Math.min(glyphEnd, pack.length));

  Gpu.beginFrame();
  Gpu.drawSprites(sprites, resolveRes);
  Gpu.drawGlyphs(glyphs, "atlas");
  Gpu.drawVeil(veil);
  Gpu.endFrame();
}

function frame(ts) {
  requestAnimationFrame(frame);
  if (!exports_) return;
  const dt = lastTs ? Math.min(100, ts - lastTs) : 16.6;
  lastTs = ts;
  const intent = pendingIntent;
  pendingIntent = 0;
  try {
    exports_.export_frame(intent, dt);
    flushPendingGlyphs(exports_);
    // Re-pack after glyph marks so UVs stay consistent (mark may update rects)
    if ((exports_.pending_glyph_count() | 0) === 0) {
      // second export with None keeps stage; only rebuilds draw list
      // Actually export_frame always ticks — use intent 0 only once per frame.
      // Glyphs marked ready will appear next frame; acceptable for Phase 1.
    }
    const pack = copyFrame(exports_);
    drawPack(pack);
  } catch (e) {
    console.error("frame error", e);
  }
}

function bindInput(canvas) {
  window.addEventListener("keydown", (ev) => {
    switch (ev.key) {
      case "Enter":
      case " ":
      case "z":
      case "Z":
        pendingIntent = 1; // Advance
        ev.preventDefault();
        break;
      case "Control":
        pendingIntent = 2; // SkipTyping
        break;
      case "a":
      case "A":
        pendingIntent = 4; // ToggleAuto
        break;
      case "s":
      case "S":
        if (ev.ctrlKey || ev.metaKey) {
          doSave();
          ev.preventDefault();
        }
        break;
      case "l":
      case "L":
        if (ev.ctrlKey || ev.metaKey) {
          doLoad();
          ev.preventDefault();
        }
        break;
      case "1":
      case "2":
      case "3":
      case "4":
      case "5":
      case "6":
      case "7":
      case "8":
      case "9":
        pendingIntent = 10 + (ev.key.charCodeAt(0) - 49); // Select(0..8)
        break;
      default:
        break;
    }
  });

  canvas.addEventListener("pointerdown", () => {
    pendingIntent = 1; // Advance
  });
}

function doSave() {
  if (!exports_) return;
  const json = exports_.save_json(saveSlot);
  if (json && json.length) {
    localStorage.setItem(SAVE_KEY(saveSlot), json);
    console.info("saved", SAVE_KEY(saveSlot), json.length, "bytes");
  }
}

function doLoad() {
  if (!exports_) return;
  const json = localStorage.getItem(SAVE_KEY(saveSlot));
  if (!json) {
    console.warn("no save at", SAVE_KEY(saveSlot));
    return;
  }
  const rc = exports_.load_json(json);
  console.info("load", SAVE_KEY(saveSlot), "rc=", rc);
}

/**
 * MoonBit wasm-gc import object.
 *
 * With `use-js-builtin-string`, current host_web only imports `console.log`.
 * Keep spectest / ffi helpers for older/other artifacts.
 */
function moonbitImports() {
  const spectest = {
    _buf: "",
    print_char: (c) => {
      if (c === 10) {
        console.log(spectest._buf || "");
        spectest._buf = "";
      } else {
        spectest._buf = (spectest._buf || "") + String.fromCharCode(c);
      }
    },
  };
  return {
    console: {
      log: (...args) => console.log("[moonbit]", ...args),
    },
    spectest,
    "moonbit:ffi": {
      make_closure: (funcref, closure) => funcref.bind(null, closure),
    },
  };
}

async function loadWasm(url) {
  const imports = moonbitImports();
  const result = await WebAssembly.instantiateStreaming(fetch(url), imports, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  return result.instance.exports;
}

async function loadManifest(url) {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

/**
 * Upload textures listed in manifest.resources: { "resId": "path.png", ... }
 */
async function applyManifest(manifest) {
  if (!manifest || !manifest.resources) return;
  for (const [id, path] of Object.entries(manifest.resources)) {
    try {
      await Gpu.uploadPngUrl(id, path);
      console.info("texture", id, "←", path);
    } catch (e) {
      console.warn("texture failed", id, path, e);
    }
  }
}

async function maybeLoadSource() {
  // Prefer demo.yuki if present; else rely on init_demo inside wasm.
  try {
    const res = await fetch("./demo.yuki");
    if (res.ok) {
      const src = await res.text();
      const rc = exports_.load_source(src);
      console.info("load_source demo.yuki rc=", rc);
      return;
    }
  } catch {
    /* fall through */
  }
  exports_.init_demo();
  console.info("init_demo()");
}

function fitCanvas(canvas) {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const w = Math.max(1, Math.floor(window.innerWidth * dpr));
  const h = Math.max(1, Math.floor(window.innerHeight * dpr));
  canvas.width = w;
  canvas.height = h;
  canvas.style.width = "100%";
  canvas.style.height = "100%";
  Gpu.resize(w, h);
}

export async function boot(options = {}) {
  const canvas =
    options.canvas ||
    document.querySelector("#game") ||
    document.querySelector("canvas");
  if (!canvas) throw new Error("no canvas");

  const status = document.querySelector("#status");
  const setStatus = (m) => {
    if (status) status.textContent = m;
    console.info("[moonsight]", m);
  };

  try {
    setStatus("init WebGPU…");
    await Gpu.init(canvas);
    fitCanvas(canvas);
    window.addEventListener("resize", () => fitCanvas(canvas));
    bindInput(canvas);

    const params = new URLSearchParams(location.search);
    const wasmUrl =
      options.wasmUrl || params.get("wasm") || "./host_web.wasm";

    setStatus(`load wasm ${wasmUrl}…`);
    exports_ = await loadWasm(wasmUrl);
    // _start may have run (println). Explicit demo init:
    setStatus("init engine…");
    await maybeLoadSource();

    const manifestUrl =
      options.manifestUrl || params.get("manifest") || "./manifest.json";
    const manifest = await loadManifest(manifestUrl);
    await applyManifest(manifest);

    // Map numeric resource ids that already exist after init
    const rc = exports_.resource_count() | 0;
    for (let id = 0; id < rc; id++) {
      const name = exports_.resource_name(id);
      if (name && !Gpu._textures.has(name) && name.length) {
        // keep placeholder until manifest provides file
      }
    }

    setStatus("running (click / Enter to advance)");
    requestAnimationFrame(frame);
  } catch (e) {
    setStatus(String(e && e.message ? e.message : e));
    console.error(e);
    throw e;
  }

  return {
    exports: () => exports_,
    save: doSave,
    load: doLoad,
    setIntent: (code) => {
      pendingIntent = code | 0;
    },
  };
}

// Auto-boot when loaded as module on the page
if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => {
      boot().catch(() => {});
    });
  } else {
    boot().catch(() => {});
  }
}
