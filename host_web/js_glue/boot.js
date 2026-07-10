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
import * as Slug from "./slug/index.js";
import * as SlugGpu from "./slug/slug_gpu.js";

const PACK_HEADER = 4;
const SPRITE_STRIDE = 7;
/** atlas_x,y,w,h, x,y, screen_w,screen_h, r,g,b,a */
const GLYPH_STRIDE = 12;

/** Audio event kinds from host_web exports */
const AUDIO_PLAY_BGM = 0;
const AUDIO_STOP_BGM = 1;
const AUDIO_PLAY_SE = 2;
const AUDIO_SET_BGM_VOLUME = 3;

const SAVE_KEY = (slot) => `moonsight/save/${slot}`;
const PREFS_KEY = "moonsight/prefs";

/** Intent codes (docs/draw-list-pack.md + MenuUp/Down) */
const INTENT_NONE = 0;
const INTENT_ADVANCE = 1;
const INTENT_SKIP = 2;
const INTENT_OPEN_MENU = 3;
const INTENT_TOGGLE_AUTO = 4;
const INTENT_MENU_UP = 5;
const INTENT_MENU_DOWN = 6;

/** @type {WebAssembly.Exports | null} */
let exports_ = null;

/** pending intent for next frame */
let pendingIntent = 0;
let lastTs = 0;
let saveSlot = 0;

/** @type {{ text_speed: number, auto_mode: boolean, master_volume: number, bgm_volume: number, se_volume: number }} */
let prefs = {
  text_speed: 1.0,
  auto_mode: false,
  master_volume: 1.0,
  bgm_volume: 1.0,
  se_volume: 1.0,
};

/** Last logical BGM volume from mixer events (before prefs multiply). */
let lastLogicalBgmVol = 1.0;

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
 * Rasterize pending glyphs. Only mark ready when stamp has real ink
 * (or is whitespace). Empty stamps stay pending so the next frame retries —
 * fixes first typewriter char ("W" in Welcome) when the font was not ready.
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
    if (size <= 0 || atlasW <= 0 || atlasH <= 0) {
      anyFailed = true;
      continue;
    }
    const ch = String.fromCodePoint(cp);
    try {
      const ok = Gpu.rasterizeGlyphToAtlas(
        ch,
        size,
        atlasX,
        atlasY,
        atlasW,
        atlasH,
        1024,
      );
      if (ok) {
        exports.mark_glyph_ready(cp, size, atlasX, atlasY, atlasW, atlasH);
      } else {
        anyFailed = true;
      }
    } catch (e) {
      anyFailed = true;
      console.warn("glyph rasterize failed", ch, e);
    }
  }
  // mark_ready already dequeued successes. clear_pending only when all done;
  // if any failed, leave them in the queue for the next frame.
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

/** True if path already has a known audio extension (optional query). */
function hasAudioExt(path) {
  return /\.(ogg|mp3|wav|m4a)(\?.*)?$/i.test(path);
}

/**
 * Dual-format alt list for extensionless paths: OGG first, then MP3.
 * @param {string} base path without extension
 * @returns {{ogg:string, mp3:string}}
 */
function dualFormat(base) {
  return { ogg: `${base}.ogg`, mp3: `${base}.mp3` };
}

/**
 * Resolve a logical audio id to a playable URL or dual-format alt.
 * Prefer explicit manifest.audio entry; else try id.ogg then id.mp3.
 */
function resolveAudioUrl(id) {
  if (!id) return null;
  if (audioUrls[id] != null) return audioUrls[id];
  // If the id already looks like a path with extension, use as-is.
  if (hasAudioExt(id)) return id;
  // Prefer OGG, fallback MP3 (browser picks via dual <source>).
  return dualFormat(id);
}

/**
 * Clamp volume to [0, 1]; treat non-finite as 1 (keeps volume 0 valid).
 * @param {unknown} v
 */
function clampVolume(v) {
  const n = Number(v);
  return Math.max(0, Math.min(1, Number.isFinite(n) ? n : 1));
}

/**
 * Output BGM gain = logical × master × bgm prefs.
 * @param {number} logical
 */
function effectiveBgmVolume(logical) {
  return clampVolume(
    Number(logical) * prefs.master_volume * prefs.bgm_volume,
  );
}

/**
 * Output SE gain = logical × master × se prefs.
 * @param {number} logical
 */
function effectiveSeVolume(logical) {
  return clampVolume(Number(logical) * prefs.master_volume * prefs.se_volume);
}

/**
 * Load prefs from localStorage into JS + wasm engine.
 */
function loadPrefsFromStorage() {
  try {
    const raw = localStorage.getItem(PREFS_KEY);
    if (raw && typeof exports_?.set_prefs_json === "function") {
      const rc = exports_.set_prefs_json(raw);
      if (rc === 0 && typeof exports_.prefs_json === "function") {
        const applied = exports_.prefs_json();
        if (applied) {
          try {
            const p = JSON.parse(applied);
            prefs = {
              text_speed: Number(p.text_speed ?? 1),
              auto_mode: !!p.auto_mode,
              master_volume: clampVolume(p.master_volume ?? 1),
              bgm_volume: clampVolume(p.bgm_volume ?? 1),
              se_volume: clampVolume(p.se_volume ?? 1),
            };
          } catch (_) {
            /* keep defaults */
          }
        }
      }
    } else if (raw) {
      try {
        const p = JSON.parse(raw);
        prefs = {
          text_speed: Number(p.text_speed ?? 1),
          auto_mode: !!p.auto_mode,
          master_volume: clampVolume(p.master_volume ?? 1),
          bgm_volume: clampVolume(p.bgm_volume ?? 1),
          se_volume: clampVolume(p.se_volume ?? 1),
        };
      } catch (_) {
        /* keep defaults */
      }
    }
  } catch (_) {
    /* private mode / blocked storage */
  }
  applyPrefsToAudio();
}

/**
 * Persist engine prefs to localStorage when present.
 */
function savePrefsToStorage() {
  try {
    if (typeof exports_?.prefs_json === "function") {
      const json = exports_.prefs_json();
      if (json && json.length) {
        localStorage.setItem(PREFS_KEY, json);
        try {
          const p = JSON.parse(json);
          prefs = {
            text_speed: Number(p.text_speed ?? prefs.text_speed),
            auto_mode: !!p.auto_mode,
            master_volume: clampVolume(p.master_volume ?? prefs.master_volume),
            bgm_volume: clampVolume(p.bgm_volume ?? prefs.bgm_volume),
            se_volume: clampVolume(p.se_volume ?? prefs.se_volume),
          };
        } catch (_) {
          /* ignore parse */
        }
      }
    }
  } catch (_) {
    /* ignore */
  }
  applyPrefsToAudio();
}

/** Re-apply prefs gains to the current BGM element. */
function applyPrefsToAudio() {
  if (bgmEl) {
    bgmEl.volume = effectiveBgmVolume(lastLogicalBgmVol);
  }
}

/**
 * Seed engine slot_blobs from localStorage multi-slot keys.
 */
function hydrateSlotsFromStorage() {
  if (!exports_ || typeof exports_.set_slot_json !== "function") return;
  const n =
    typeof exports_.save_slot_count === "function"
      ? exports_.save_slot_count() | 0
      : 6;
  for (let i = 0; i < Math.max(n, 1); i++) {
    try {
      const json = localStorage.getItem(SAVE_KEY(i));
      if (json && json.length) {
        exports_.set_slot_json(i, json);
      }
    } catch (_) {
      /* ignore */
    }
  }
}

/**
 * Mirror engine slot_blobs back to localStorage (menu save path).
 */
function syncSlotsToStorage() {
  if (!exports_ || typeof exports_.get_slot_json !== "function") return;
  const n =
    typeof exports_.save_slot_count === "function"
      ? exports_.save_slot_count() | 0
      : 6;
  for (let i = 0; i < Math.max(n, 1); i++) {
    try {
      const json = exports_.get_slot_json(i);
      if (json && json.length) {
        localStorage.setItem(SAVE_KEY(i), json);
      }
    } catch (_) {
      /* ignore */
    }
  }
}

/**
 * Hard-fail audio load — same surface as texture hard-fail in applyManifest:
 * log `audio load failed: {id}`, optional #status DOM message, then throw.
 * Does not pretend playback succeeded.
 *
 * @param {string} id logical audio id
 * @param {unknown} [detail] optional reason (no URL, media error, play fail)
 */
function audioLoadFailed(id, detail) {
  console.error("audio load failed:", id, detail != null ? detail : "");
  const msg =
    detail != null && String(detail).length
      ? `MoonSight: failed to load audio '${id}': ${detail}`
      : `MoonSight: failed to load audio '${id}'`;
  try {
    const status =
      typeof document !== "undefined" ? document.querySelector("#status") : null;
    if (status) status.textContent = msg;
  } catch (_) {
    /* ignore */
  }
  throw new Error(msg);
}

/**
 * Autoplay policy and interrupted play() — not a missing/broken asset load.
 * NotAllowedError: browser blocked autoplay. AbortError: pause/replace/stop
 * aborted a pending play() promise.
 */
function isBenignPlayReject(e) {
  return !!(e && (e.name === "NotAllowedError" || e.name === "AbortError"));
}

/**
 * Arm HTMLAudioElement error → hard-fail (async path after makeAudio).
 * @param {HTMLAudioElement} el
 * @param {string} id
 * @param {() => boolean} [isActive] if set, only hard-fail while it returns true
 *   (so intentional stop/replace that clears src does not false-trigger)
 */
function armAudioLoadHardFail(el, id, isActive) {
  el.addEventListener(
    "error",
    () => {
      if (typeof isActive === "function" && !isActive()) return;
      try {
        const code = el.error && el.error.code;
        audioLoadFailed(
          id,
          code != null ? `media error code ${code}` : "media error",
        );
      } catch (_) {
        /* already surfaced via #status / console */
      }
    },
    { once: true },
  );
}

/**
 * @param {string | {ogg:string, mp3:string}} urlOrAlt
 * @param {{loop?: boolean, volume?: number}} opts
 */
function makeAudio(urlOrAlt, opts = {}) {
  const el = new Audio();
  el.preload = "auto";
  el.loop = !!opts.loop;
  el.volume = clampVolume(opts.volume ?? 1);
  if (typeof urlOrAlt === "string") {
    el.src = urlOrAlt;
  } else {
    // Prefer OGG via <source>, then MP3. Do not set el.src — that would
    // force the primary only and break browser fallback selection.
    const sOgg = document.createElement("source");
    sOgg.src = urlOrAlt.ogg;
    sOgg.type = "audio/ogg";
    const sMp3 = document.createElement("source");
    sMp3.src = urlOrAlt.mp3;
    sMp3.type = "audio/mpeg";
    el.appendChild(sOgg);
    el.appendChild(sMp3);
  }
  return el;
}

function stopBgm() {
  if (bgmEl) {
    const el = bgmEl;
    // Drop ownership before teardown so armed error handlers ignore
    // the error event from removeAttribute("src") + load().
    bgmEl = null;
    bgmId = null;
    try {
      el.pause();
      el.removeAttribute("src");
      el.load();
    } catch (_) {
      /* ignore */
    }
  } else {
    bgmId = null;
  }
}

/**
 * Apply mid-fade / volume-only BGM change without restarting the track.
 * `volume` is logical mixer volume; prefs multiply on output.
 * @param {number} volume
 */
function setBgmVolume(volume) {
  lastLogicalBgmVol = clampVolume(volume);
  if (bgmEl) {
    bgmEl.volume = effectiveBgmVolume(lastLogicalBgmVol);
  }
}

/**
 * Play BGM by logical id. Missing URL or media load failure hard-fails
 * (see audioLoadFailed); autoplay / AbortError only warn.
 */
function playBgm(id, looped, volume) {
  const url = resolveAudioUrl(id);
  if (!url) {
    audioLoadFailed(id, "no URL for BGM");
  }
  lastLogicalBgmVol = clampVolume(volume);
  const vol = effectiveBgmVolume(lastLogicalBgmVol);
  if (bgmId === id && bgmEl && !bgmEl.paused) {
    bgmEl.volume = vol;
    bgmEl.loop = !!looped;
    return;
  }
  stopBgm();
  ensureAudioUnlocked();
  const el = makeAudio(url, { loop: looped, volume: vol });
  bgmEl = el;
  bgmId = id;
  armAudioLoadHardFail(el, id, () => bgmEl === el);
  const p = el.play();
  if (p && typeof p.catch === "function") {
    p.catch((e) => {
      if (isBenignPlayReject(e)) {
        console.warn("bgm play blocked/failed", id, e);
        return;
      }
      if (bgmEl !== el) return;
      try {
        audioLoadFailed(id, e);
      } catch (_) {
        /* surfaced */
      }
    });
  }
}

/**
 * Play SE by logical id. Missing URL or media load failure hard-fails
 * (see audioLoadFailed); autoplay / AbortError only warn.
 */
function playSe(id, volume) {
  const url = resolveAudioUrl(id);
  if (!url) {
    audioLoadFailed(id, "no URL for SE");
  }
  ensureAudioUnlocked();
  const el = makeAudio(url, {
    loop: false,
    volume: effectiveSeVolume(volume),
  });
  armAudioLoadHardFail(el, id);
  const p = el.play();
  if (p && typeof p.catch === "function") {
    p.catch((e) => {
      if (isBenignPlayReject(e)) {
        console.warn("se play blocked/failed", id, e);
        return;
      }
      try {
        audioLoadFailed(id, e);
      } catch (_) {
        /* surfaced */
      }
    });
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
      const volume = clampVolume(exports.audio_event_volume(i));
      playBgm(id, looped, volume);
    } else if (kind === AUDIO_STOP_BGM) {
      stopBgm();
    } else if (kind === AUDIO_PLAY_SE) {
      const id = exports.audio_event_resource(i) || "";
      const volume = clampVolume(exports.audio_event_volume(i));
      playSe(id, volume);
    } else if (kind === AUDIO_SET_BGM_VOLUME) {
      setBgmVolume(exports.audio_event_volume(i));
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
    // After UI actions: prefs + multi-slot may have changed in-engine.
    if (intent !== INTENT_NONE) {
      savePrefsToStorage();
      syncSlotsToStorage();
    }
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
        pendingIntent = INTENT_ADVANCE;
        ev.preventDefault();
        break;
      case "Escape":
        pendingIntent = INTENT_OPEN_MENU;
        ev.preventDefault();
        break;
      case "ArrowUp":
      case "w":
      case "W":
        pendingIntent = INTENT_MENU_UP;
        ev.preventDefault();
        break;
      case "ArrowDown":
      case "s":
      case "S":
        // Plain S is MenuDown; Ctrl/Cmd+S is quick-save.
        if (ev.ctrlKey || ev.metaKey) {
          doSave();
          ev.preventDefault();
        } else {
          pendingIntent = INTENT_MENU_DOWN;
          ev.preventDefault();
        }
        break;
      case "Control":
        pendingIntent = INTENT_SKIP;
        break;
      case "a":
      case "A":
        pendingIntent = INTENT_TOGGLE_AUTO;
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
    pendingIntent = INTENT_ADVANCE;
  });
}

function doSave() {
  if (!exports_) return;
  let json = exports_.save_json(saveSlot);
  if (json && json.length) {
    // Runtime leaves saved_at empty (no wall-clock FFI); stamp ISO time here.
    try {
      const obj = JSON.parse(json);
      if (!obj.saved_at) {
        obj.saved_at = new Date().toISOString();
        json = JSON.stringify(obj);
      }
    } catch (_) {
      /* keep raw json */
    }
    localStorage.setItem(SAVE_KEY(saveSlot), json);
    if (typeof exports_.set_slot_json === "function") {
      exports_.set_slot_json(saveSlot, json);
    }
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
  if (typeof exports_.set_slot_json === "function") {
    exports_.set_slot_json(saveSlot, json);
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
        console.error("texture failed", id, path, e);
        throw new Error(`MoonSight: failed to load texture '${id}' from '${path}': ${e}`);
      }
    }
  }
  if (manifest.audio && typeof manifest.audio === "object") {
    audioUrls = Object.create(null);
    for (const [id, path] of Object.entries(manifest.audio)) {
      if (typeof path === "string" && path.length) {
        // Extensionless manifest paths → dual OGG/MP3 for browser fallback.
        audioUrls[id] = hasAudioExt(path) ? path : dualFormat(path);
        console.info("audio", id, "←", path);
      }
    }
  }
}

/**
 * Build a binary Latin-1 string from Uint8Array (one code unit per byte).
 * Used to pass MSB bytes into MoonBit `load_msb` under js-builtin-string.
 */
function bytesToBinaryString(buf) {
  const chunk = 0x8000;
  let raw = "";
  for (let i = 0; i < buf.length; i += chunk) {
    raw += String.fromCharCode.apply(null, buf.subarray(i, i + chunk));
  }
  return raw;
}

/**
 * Load screens.json into engine defs. Returns true when screens were installed.
 */
async function maybeLoadScreens() {
  if (!exports_ || typeof exports_.load_screens_json !== "function") {
    return false;
  }
  try {
    const res = await fetch("./screens.json");
    if (!res.ok) return false;
    const text = await res.text();
    if (!text || !text.length) return false;
    const rc = exports_.load_screens_json(text);
    console.info("load_screens_json rc=", rc, "bytes=", text.length);
    return rc === 0;
  } catch (e) {
    console.warn("screens.json load error", e);
    return false;
  }
}

/**
 * After narrative + screens load: hydrate storage, prefs, optional cold-start title.
 * @param {boolean} hasScreens
 */
function afterEngineReady(hasScreens) {
  hydrateSlotsFromStorage();
  loadPrefsFromStorage();
  if (hasScreens && typeof exports_?.boot_title === "function") {
    const rc = exports_.boot_title();
    console.info("boot_title rc=", rc);
  }
}

async function maybeLoadSource() {
  // Prefer compiled multi-file game.msb when present; fallback demo.yuki / init_demo.
  // Replacing mixer/source state: stop any JS-side BGM so it cannot desync.
  let loaded = false;
  try {
    const msbRes = await fetch("./game.msb");
    if (
      msbRes.ok &&
      exports_ &&
      typeof exports_.load_msb === "function"
    ) {
      const buf = new Uint8Array(await msbRes.arrayBuffer());
      if (buf.length > 0) {
        const rc = exports_.load_msb(bytesToBinaryString(buf));
        console.info("load_msb game.msb rc=", rc, "bytes=", buf.length);
        stopBgm();
        if (rc === 0) {
          loaded = true;
        } else {
          console.warn("load_msb failed; falling back to demo.yuki");
        }
      }
    }
  } catch (e) {
    console.warn("game.msb load error", e);
  }
  if (!loaded) {
    try {
      const res = await fetch("./demo.yuki");
      if (res.ok) {
        const src = await res.text();
        const rc = exports_.load_source(src);
        console.info("load_source demo.yuki rc=", rc);
        stopBgm();
        loaded = rc === 0;
      }
    } catch {
      /* fall through */
    }
  }
  if (!loaded) {
    exports_.init_demo();
    console.info("init_demo()");
    stopBgm();
  }
  const hasScreens = await maybeLoadScreens();
  afterEngineReady(hasScreens);
}

/** Fixed logical resolution; MoonBit packs all draw coords in FHD pixels. */
const LOGICAL_W = 1920;
const LOGICAL_H = 1080;

/**
 * Fixed 1920×1080 WebGPU backbuffer with **letterboxed** CSS presentation.
 * Stretching via 100vw×100vh made glyphs look unnaturally wide.
 */
function fitCanvas(canvas) {
  canvas.width = LOGICAL_W;
  canvas.height = LOGICAL_H;
  const vw = window.innerWidth || LOGICAL_W;
  const vh = window.innerHeight || LOGICAL_H;
  const scale = Math.min(vw / LOGICAL_W, vh / LOGICAL_H);
  const dw = Math.max(1, Math.round(LOGICAL_W * scale));
  const dh = Math.max(1, Math.round(LOGICAL_H * scale));
  canvas.style.width = `${dw}px`;
  canvas.style.height = `${dh}px`;
  canvas.style.marginLeft = `${Math.floor((vw - dw) / 2)}px`;
  canvas.style.marginTop = `${Math.floor((vh - dh) / 2)}px`;
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
    // Font + Slug GPU (https://github.com/diffusionstudio/slug-webgpu).
    // Modes: ?glyph=slug (default) | canvas | cpu-outline
    const fontUrl =
      options.fontUrl || params.get("font") || "./fonts/NotoSans-Regular.ttf";
    // Default to canvas fillText (reliable). GPU Slug: ?glyph=slug
    const glyphMode = options.glyphMode || params.get("glyph") || "canvas";
    try {
      setStatus("load font…");
      const fontRes = await fetch(fontUrl);
      if (!fontRes.ok) throw new Error(`font HTTP ${fontRes.status}`);
      const fontBuf = await fontRes.arrayBuffer();

      if (typeof FontFace !== "undefined") {
        const face = new FontFace("Noto Sans", fontBuf.slice(0));
        await face.load();
        document.fonts.add(face);
        await document.fonts.ready;
        await document.fonts.load('32px "Noto Sans"');
      }

      // Warm up canvas fillText so the first typewriter glyph is not blank.
      {
        const warm = document.createElement("canvas");
        warm.width = 64;
        warm.height = 64;
        const wctx = warm.getContext("2d");
        wctx.font = '32px "Noto Sans", "NotoSans", sans-serif';
        wctx.fillStyle = "#ffffff";
        wctx.fillText("WABCMygj", 2, 40);
      }

      const dev = Gpu.getDevice();
      if (dev) {
        await SlugGpu.initSlugGpu(dev, "rgba8unorm");
        SlugGpu.loadFontBuffer(fontBuf);
        Gpu.setSlugGpu(SlugGpu);
      }
      await Slug.loadFont(fontUrl).catch(() => {});
      Gpu.setOutlineRasterizer(Slug);
      Gpu.setGlyphRasterMode(glyphMode);
      setStatus(`font ready (${glyphMode})`);
    } catch (e) {
      console.warn("font/slug init failed; canvas glyphs", e);
      Gpu.setGlyphRasterMode("canvas");
    }

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

    // Delay first frame one rAF so font/GPU state settles before typewriter.
    setStatus("running (click / Enter to advance)");
    requestAnimationFrame(() => requestAnimationFrame(frame));
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
