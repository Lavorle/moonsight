/**
 * MoonSight browser boot: load wasm-gc host, wire input, rAF game loop.
 *
 * Expects:
 *   - ./webgpu_bridge.js (ES module)
 *   - ./host_web.wasm (or ?wasm= path) built from host_web package
 *   - optional ./manifest.json
 *       { "resources": { "id": "url.png", ... },
 *         "audio": { "id": "url.ogg", ... } }
 *   - optional ./game.msb or ./demo.yuki (source via load_source)
 *
 * Audio: prefer OGG, fallback MP3. Thin HTMLAudioElement glue (Web Audio API
 * unlock on first user gesture).
 */

import * as Gpu from "./webgpu_bridge.js";

const PACK_HEADER = 4;
const SPRITE_STRIDE = 7;
const GLYPH_STRIDE = 10;

/** Audio event kinds from host_web exports */
const AUDIO_PLAY_BGM = 0;
const AUDIO_STOP_BGM = 1;
const AUDIO_PLAY_SE = 2;

const SAVE_KEY = (slot) => `moonsight/save/${slot}`;

/** @type {WebAssembly.Exports | null} */
let exports_ = null;

/** pending intent for next frame */
let pendingIntent = 0;
let lastTs = 0;
let saveSlot = 0;

/** @type {Record<string, string>} logical audio id → primary URL */
let audioUrls = Object.create(null);

/** @type {HTMLAudioElement | null} */
let bgmEl = null;
/** @type {string | null} */
let bgmId = null;
/** @type {AudioContext | null} */
let audioCtx = null;

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
 * On partial failure, skip clear_pending so failed entries retry next frame.
 */
function flushPendingGlyphs(exports) {
  const n = exports.pending_glyph_count() | 0;
  if (n <= 0) return;
  let anyFailed = false;
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
      anyFailed = true;
      console.warn("glyph rasterize failed", ch, e);
    }
  }
  // Do not permanently drop failed glyphs: only clear when every stamp succeeded.
  // Successes re-stamped on a later retry are harmless (idempotent atlas write).
  if (!anyFailed) {
    exports.clear_pending_glyphs();
  }
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

/**
 * Ensure AudioContext is running after a user gesture (autoplay policy).
 */
function ensureAudioUnlocked() {
  try {
    if (!audioCtx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (AC) audioCtx = new AC();
    }
    if (audioCtx && audioCtx.state === "suspended") {
      audioCtx.resume().catch(() => {});
    }
  } catch (_) {
    /* ignore */
  }
}

/**
 * Resolve a logical audio id to a playable URL.
 * Prefer explicit manifest.audio entry; else try id.ogg then id.mp3.
 */
function resolveAudioUrl(id) {
  if (!id) return null;
  if (audioUrls[id]) return audioUrls[id];
  // If the id already looks like a path with extension, use as-is.
  if (/\.(ogg|mp3|wav|m4a)(\?.*)?$/i.test(id)) return id;
  // Prefer OGG, fallback MP3 (browser picks via <source> or sequential try).
  return { ogg: `${id}.ogg`, mp3: `${id}.mp3`, primary: `${id}.ogg` };
}

/**
 * @param {string | {ogg:string, mp3:string, primary:string}} urlOrAlt
 * @param {{loop?: boolean, volume?: number}} opts
 */
function makeAudio(urlOrAlt, opts = {}) {
  const el = new Audio();
  el.preload = "auto";
  el.loop = !!opts.loop;
  el.volume = Math.max(0, Math.min(1, opts.volume ?? 1));
  if (typeof urlOrAlt === "string") {
    el.src = urlOrAlt;
  } else {
    // Prefer OGG via <source>, then MP3.
    const sOgg = document.createElement("source");
    sOgg.src = urlOrAlt.ogg;
    sOgg.type = "audio/ogg";
    const sMp3 = document.createElement("source");
    sMp3.src = urlOrAlt.mp3;
    sMp3.type = "audio/mpeg";
    el.appendChild(sOgg);
    el.appendChild(sMp3);
    // Some engines need .src even with sources.
    el.src = urlOrAlt.primary;
  }
  return el;
}

function stopBgm() {
  if (bgmEl) {
    try {
      bgmEl.pause();
      bgmEl.removeAttribute("src");
      bgmEl.load();
    } catch (_) {
      /* ignore */
    }
    bgmEl = null;
  }
  bgmId = null;
}

function playBgm(id, looped, volume) {
  const url = resolveAudioUrl(id);
  if (!url) {
    console.warn("audio: no URL for BGM", id);
    return;
  }
  if (bgmId === id && bgmEl && !bgmEl.paused) {
    bgmEl.volume = Math.max(0, Math.min(1, volume));
    bgmEl.loop = !!looped;
    return;
  }
  stopBgm();
  ensureAudioUnlocked();
  const el = makeAudio(url, { loop: looped, volume });
  bgmEl = el;
  bgmId = id;
  const p = el.play();
  if (p && typeof p.catch === "function") {
    p.catch((e) => console.warn("bgm play blocked/failed", id, e));
  }
}

function playSe(id, volume) {
  const url = resolveAudioUrl(id);
  if (!url) {
    console.warn("audio: no URL for SE", id);
    return;
  }
  ensureAudioUnlocked();
  const el = makeAudio(url, { loop: false, volume });
  const p = el.play();
  if (p && typeof p.catch === "function") {
    p.catch((e) => console.warn("se play blocked/failed", id, e));
  }
}

/**
 * Drain mixer events exported by MoonBit and apply via HTMLAudioElement.
 */
function flushAudio(exports) {
  if (typeof exports.audio_event_count !== "function") return;
  const n = exports.audio_event_count() | 0;
  if (n <= 0) return;
  for (let i = 0; i < n; i++) {
    const kind = exports.audio_event_kind(i) | 0;
    if (kind === AUDIO_PLAY_BGM) {
      const id = exports.audio_event_resource(i) || "";
      const looped = (exports.audio_event_looped(i) | 0) !== 0;
      const volume = +exports.audio_event_volume(i) || 1;
      playBgm(id, looped, volume);
    } else if (kind === AUDIO_STOP_BGM) {
      stopBgm();
    } else if (kind === AUDIO_PLAY_SE) {
      const id = exports.audio_event_resource(i) || "";
      const volume = +exports.audio_event_volume(i) || 1;
      playSe(id, volume);
    }
  }
  if (typeof exports.audio_clear_events === "function") {
    exports.audio_clear_events();
  }
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
    flushAudio(exports_);
    // Glyphs marked ready appear next frame (Phase 1; no second export/tick).
    const pack = copyFrame(exports_);
    drawPack(pack);
  } catch (e) {
    console.error("frame error", e);
  }
}

function bindInput(canvas) {
  // First pointer/key unlocks autoplay policy for BGM/SE.
  const unlock = () => ensureAudioUnlocked();
  window.addEventListener("pointerdown", unlock, { once: true });
  window.addEventListener("keydown", unlock, { once: true });

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
 * Upload textures listed in manifest.resources and register audio URLs.
 *
 * manifest shape:
 *   {
 *     "resources": { "resId": "path.png", ... },
 *     "audio": { "bgm_soft": "assets/bgm_soft.ogg", "click": "assets/click.mp3" }
 *   }
 *
 * Audio entries may omit extension; resolve prefers .ogg then .mp3 at play time.
 */
async function applyManifest(manifest) {
  if (!manifest) return;
  if (manifest.resources) {
    for (const [id, path] of Object.entries(manifest.resources)) {
      try {
        await Gpu.uploadPngUrl(id, path);
        console.info("texture", id, "←", path);
      } catch (e) {
        console.warn("texture failed", id, path, e);
      }
    }
  }
  if (manifest.audio && typeof manifest.audio === "object") {
    audioUrls = Object.create(null);
    for (const [id, path] of Object.entries(manifest.audio)) {
      if (typeof path === "string" && path.length) {
        audioUrls[id] = path;
        console.info("audio", id, "←", path);
      }
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

/** Fixed logical resolution; MoonBit packs all draw coords in FHD pixels. */
const LOGICAL_W = 1920;
const LOGICAL_H = 1080;

/**
 * Keep a fixed 1920×1080 WebGPU backbuffer. CSS scales the canvas element to
 * the viewport — never set canvas.width/height from window×DPR (that would
 * desync NDC mapping from the logical pack coords).
 */
function fitCanvas(canvas) {
  canvas.width = LOGICAL_W;
  canvas.height = LOGICAL_H;
  canvas.style.width = "100%";
  canvas.style.height = "100%";
  Gpu.resize(LOGICAL_W, LOGICAL_H);
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
