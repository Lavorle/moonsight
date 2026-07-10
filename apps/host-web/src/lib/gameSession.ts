/**
 * Game session: owns wasm exports, intent, ctrlHeld, rAF loop, input.
 * Behavior ported from host_web/js_glue/boot.js.
 */

import * as Gpu from "../adapters/webgpu_bridge.js";
import * as Slug from "../adapters/slug/index.js";
import * as SlugGpu from "../adapters/slug/slug_gpu.js";

import {
  INTENT_ADVANCE,
  INTENT_MENU_DOWN,
  INTENT_MENU_LEFT,
  INTENT_MENU_RIGHT,
  INTENT_MENU_UP,
  INTENT_NONE,
  INTENT_OPEN_BACKLOG,
  INTENT_OPEN_MENU,
  INTENT_SELECT_BASE,
  INTENT_TOGGLE_AUTO,
} from "./intents";
import {
  applyPrefsToAudio,
  createAudioHost,
  ensureAudioUnlocked,
  flushAudio,
  registerManifestAudio,
  stopBgm,
  type AudioHost,
} from "./audio";
import {
  DEFAULT_PREFS,
  loadPrefsFromStorage,
  savePrefsToStorage,
  type Prefs,
} from "./prefs";
import { bytesToBinaryString, loadManifest, loadWasm } from "./wasm";

const PACK_HEADER = 4;
const SPRITE_STRIDE = 7;
/** atlas_x,y,w,h, x,y, screen_w,screen_h, r,g,b,a */
const GLYPH_STRIDE = 12;

const SAVE_KEY = (slot: number) => `moonsight/save/${slot}`;

/** Fixed logical resolution; MoonBit packs all draw coords in FHD pixels. */
export const LOGICAL_W = 1920;
export const LOGICAL_H = 1080;

/**
 * FHD choice strip geometry — must match `UiLayout::default_fhd` in render/types.mbt.
 * Used only for pointer hit-tests (engine owns focus / commit).
 */
const CHOICE_LAYOUT = (() => {
  const canvas_w = 1920;
  const canvas_h = 1080;
  const dialogue_h = canvas_h * 0.3;
  const dialogue_y = canvas_h - dialogue_h;
  const margin = 48;
  const pad = 32;
  return {
    x: margin + pad,
    y: dialogue_y - 200,
    w: canvas_w - margin * 2 - pad * 2,
    lineH: 48,
    maxRows: 9,
  };
})();

/** Flexible host_web wasm export surface used by the boot loop. */
export type HostExports = WebAssembly.Exports & {
  frame_len: () => number;
  frame_at: (i: number) => number;
  export_frame: (intent: number, dt: number, skipHeld: number) => void;
  resource_name?: (id: number) => string;
  pending_glyph_count?: () => number;
  pending_glyph_cp?: (i: number) => number;
  pending_glyph_size?: (i: number) => number;
  pending_glyph_atlas_x?: (i: number) => number;
  pending_glyph_atlas_y?: (i: number) => number;
  pending_glyph_atlas_w?: (i: number) => number;
  pending_glyph_atlas_h?: (i: number) => number;
  mark_glyph_ready?: (
    cp: number,
    size: number,
    ax: number,
    ay: number,
    aw: number,
    ah: number,
  ) => void;
  clear_pending_glyphs?: () => void;
  set_prefs_json?: (json: string) => number;
  prefs_json?: () => string;
  set_slot_json?: (slot: number, json: string) => void;
  get_slot_json?: (slot: number) => string;
  save_slot_count?: () => number;
  set_save_slots?: (n: number) => number;
  boot_title?: () => number;
  load_msb?: (raw: string) => number;
  load_source?: (src: string) => number;
  init_demo?: () => void;
  save_json?: (slot: number) => string;
  load_json?: (json: string) => number;
  audio_event_count?: () => number;
  audio_event_kind?: (i: number) => number;
  audio_event_resource?: (i: number) => string;
  audio_event_looped?: (i: number) => number;
  audio_event_volume?: (i: number) => number;
  audio_clear_events?: () => void;
};

export type GameSessionOptions = {
  canvas?: HTMLCanvasElement;
  wasmUrl?: string;
  manifestUrl?: string;
  fontUrl?: string;
  glyphMode?: string;
  onStatus?: (msg: string) => void;
};

export type GameSessionHandle = {
  exports: () => HostExports | null;
  save: () => void;
  load: () => void;
  setIntent: (code: number) => void;
  stop: () => void;
};

type Manifest = {
  resources?: Record<string, string>;
  audio?: Record<string, string>;
  save_slots?: number;
  [k: string]: unknown;
};

/**
 * Copy last packed frame into a Float32Array via frame_at.
 * Wasm-GC arrays are opaque to JS.
 */
function copyFrame(exports_: HostExports): Float32Array {
  const n = exports_.frame_len() | 0;
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) out[i] = exports_.frame_at(i);
  return out;
}

/**
 * Rasterize pending glyphs. Only mark ready when stamp has real ink
 * (or is whitespace). Empty stamps stay pending so the next frame retries.
 */
function flushPendingGlyphs(exports_: HostExports): void {
  if (typeof exports_.pending_glyph_count !== "function") return;
  const n = exports_.pending_glyph_count() | 0;
  if (n <= 0) return;
  let anyFailed = false;
  for (let i = 0; i < n; i++) {
    const cp = (exports_.pending_glyph_cp?.(i) ?? 0) | 0;
    const size = (exports_.pending_glyph_size?.(i) ?? 0) | 0;
    const atlasX = (exports_.pending_glyph_atlas_x?.(i) ?? 0) | 0;
    const atlasY = (exports_.pending_glyph_atlas_y?.(i) ?? 0) | 0;
    const atlasW = (exports_.pending_glyph_atlas_w?.(i) ?? 0) | 0;
    const atlasH = (exports_.pending_glyph_atlas_h?.(i) ?? 0) | 0;
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
        exports_.mark_glyph_ready?.(cp, size, atlasX, atlasY, atlasW, atlasH);
      } else {
        anyFailed = true;
      }
    } catch (e) {
      anyFailed = true;
      console.warn("glyph rasterize failed", ch, e);
    }
  }
  if (!anyFailed) {
    exports_.clear_pending_glyphs?.();
  }
}

function drawPack(
  pack: Float32Array,
  resolveRes: (id: number | string) => string | number,
): void {
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
 * Map canvas client coords → logical 1920×1080 pixels.
 */
function pointerToLogical(
  canvas: HTMLCanvasElement,
  ev: PointerEvent,
): { x: number; y: number } {
  const rect = canvas.getBoundingClientRect();
  const rw = rect.width || 1;
  const rh = rect.height || 1;
  return {
    x: ((ev.clientX - rect.left) / rw) * LOGICAL_W,
    y: ((ev.clientY - rect.top) / rh) * LOGICAL_H,
  };
}

/**
 * If pointer is over a choice row, return index 0..maxRows-1; else -1.
 */
function choiceRowAt(lx: number, ly: number): number {
  const L = CHOICE_LAYOUT;
  if (lx < L.x || lx > L.x + L.w || ly < L.y) return -1;
  const i = Math.floor((ly - L.y) / L.lineH);
  if (i < 0 || i >= L.maxRows) return -1;
  // Only the painted bar height counts (lineH - 8 in snapshot).
  const rowTop = L.y + i * L.lineH;
  if (ly > rowTop + L.lineH - 8) return -1;
  return i;
}

/**
 * Fixed 1920×1080 WebGPU backbuffer with **letterboxed** CSS presentation.
 */
function fitCanvas(canvas: HTMLCanvasElement): void {
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

export class GameSession {
  exports_: HostExports | null = null;
  pendingIntent = 0;
  /** Ctrl held → skip_held flag each frame (not one-shot SkipTyping). */
  ctrlHeld = false;
  lastTs = 0;
  saveSlot = 0;
  prefs: Prefs = { ...DEFAULT_PREFS };
  audio: AudioHost = createAudioHost();

  private onStatus: ((msg: string) => void) | null = null;
  private rafId = 0;
  private running = false;
  private unbindInput: (() => void) | null = null;
  private unbindResize: (() => void) | null = null;

  setStatus(m: string): void {
    if (this.onStatus) this.onStatus(m);
    else {
      const el =
        typeof document !== "undefined"
          ? document.querySelector("#status")
          : null;
      if (el) el.textContent = m;
    }
    console.info("[moonsight]", m);
  }

  private resolveRes = (resId: number | string): string | number => {
    if (!this.exports_) return resId;
    try {
      const name = this.exports_.resource_name?.(resId as number);
      if (name && name.length) return name;
    } catch {
      /* ignore */
    }
    return resId;
  };

  /**
   * Seed engine slot_blobs from localStorage multi-slot keys.
   */
  private hydrateSlotsFromStorage(): void {
    const exports_ = this.exports_;
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
      } catch {
        /* ignore */
      }
    }
  }

  /**
   * Mirror engine slot_blobs back to localStorage (menu save path).
   */
  private syncSlotsToStorage(): void {
    const exports_ = this.exports_;
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
      } catch {
        /* ignore */
      }
    }
  }

  private applySaveSlotsFromManifest(manifest: Manifest | null | undefined): void {
    if (
      !manifest ||
      manifest.save_slots == null ||
      typeof this.exports_?.set_save_slots !== "function"
    ) {
      return;
    }
    const n = Number(manifest.save_slots);
    if (!Number.isFinite(n)) return;
    const rc = this.exports_.set_save_slots(n | 0);
    console.info("set_save_slots", n | 0, "rc=", rc);
  }

  private afterEngineReady(manifest: Manifest | null | undefined): void {
    this.applySaveSlotsFromManifest(manifest);
    this.hydrateSlotsFromStorage();
    this.prefs = loadPrefsFromStorage(this.exports_, this.prefs);
    applyPrefsToAudio(this.audio);
    if (typeof this.exports_?.boot_title === "function") {
      const rc = this.exports_.boot_title();
      console.info("boot_title rc=", rc);
    }
  }

  /**
   * Prefer compiled multi-file game.msb when present; fallback demo.yuki / init_demo.
   */
  private async maybeLoadSource(
    manifest: Manifest | null | undefined,
  ): Promise<void> {
    let loaded = false;
    try {
      const msbRes = await fetch("./game.msb");
      if (
        msbRes.ok &&
        this.exports_ &&
        typeof this.exports_.load_msb === "function"
      ) {
        const buf = new Uint8Array(await msbRes.arrayBuffer());
        if (buf.length > 0) {
          const rc = this.exports_.load_msb(bytesToBinaryString(buf));
          console.info("load_msb game.msb rc=", rc, "bytes=", buf.length);
          stopBgm(this.audio);
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
        if (res.ok && this.exports_) {
          const src = await res.text();
          const rc = this.exports_.load_source?.(src) ?? -1;
          console.info("load_source demo.yuki rc=", rc);
          stopBgm(this.audio);
          loaded = rc === 0;
        }
      } catch {
        /* fall through */
      }
    }
    if (!loaded && this.exports_) {
      this.exports_.init_demo?.();
      console.info("init_demo()");
      stopBgm(this.audio);
    }
    this.afterEngineReady(manifest);
  }

  /**
   * Upload textures listed in manifest.resources and register audio URLs.
   */
  private async applyManifest(
    manifest: Manifest | null | undefined,
  ): Promise<void> {
    if (!manifest) return;
    if (manifest.resources) {
      for (const [id, path] of Object.entries(manifest.resources)) {
        try {
          await Gpu.uploadPngUrl(id, path);
          console.info("texture", id, "←", path);
        } catch (e) {
          console.error("texture failed", id, path, e);
          throw new Error(
            `MoonSight: failed to load texture '${id}' from '${path}': ${e}`,
          );
        }
      }
    }
    if (manifest.audio && typeof manifest.audio === "object") {
      registerManifestAudio(this.audio, manifest.audio);
    }
  }

  doSave = (): void => {
    if (!this.exports_ || typeof this.exports_.save_json !== "function") return;
    let json = this.exports_.save_json(this.saveSlot);
    if (json && json.length) {
      // Runtime leaves saved_at empty (no wall-clock FFI); stamp ISO time here.
      try {
        const obj = JSON.parse(json) as Record<string, unknown>;
        if (!obj.saved_at) {
          obj.saved_at = new Date().toISOString();
          json = JSON.stringify(obj);
        }
      } catch {
        /* keep raw json */
      }
      localStorage.setItem(SAVE_KEY(this.saveSlot), json);
      if (typeof this.exports_.set_slot_json === "function") {
        this.exports_.set_slot_json(this.saveSlot, json);
      }
      console.info("saved", SAVE_KEY(this.saveSlot), json.length, "bytes");
    }
  };

  doLoad = (): void => {
    if (!this.exports_) return;
    const json = localStorage.getItem(SAVE_KEY(this.saveSlot));
    if (!json) {
      console.warn("no save at", SAVE_KEY(this.saveSlot));
      return;
    }
    if (typeof this.exports_.set_slot_json === "function") {
      this.exports_.set_slot_json(this.saveSlot, json);
    }
    const rc = this.exports_.load_json?.(json);
    console.info("load", SAVE_KEY(this.saveSlot), "rc=", rc);
  };

  private bindInput(canvas: HTMLCanvasElement): void {
    // First pointer/key unlocks autoplay policy for BGM/SE.
    const unlock = () => ensureAudioUnlocked(this.audio);
    window.addEventListener("pointerdown", unlock, { once: true });
    window.addEventListener("keydown", unlock, { once: true });

    const onKeyDown = (ev: KeyboardEvent) => {
      if (ev.key === "Control") {
        this.ctrlHeld = true;
        ev.preventDefault();
        return;
      }
      switch (ev.key) {
        case "Enter":
        case " ":
        case "z":
        case "Z":
          // Advance: during Choose, engine commits the focused row.
          this.pendingIntent = INTENT_ADVANCE;
          ev.preventDefault();
          break;
        case "Escape":
          this.pendingIntent = INTENT_OPEN_MENU;
          ev.preventDefault();
          break;
        case "ArrowUp":
        case "w":
        case "W":
          this.pendingIntent = INTENT_MENU_UP;
          ev.preventDefault();
          break;
        case "ArrowDown":
        case "s":
        case "S":
          // Plain S is MenuDown; Ctrl/Cmd+S is quick-save.
          if (ev.ctrlKey || ev.metaKey) {
            this.doSave();
            ev.preventDefault();
          } else {
            this.pendingIntent = INTENT_MENU_DOWN;
            ev.preventDefault();
          }
          break;
        case "ArrowLeft":
          this.pendingIntent = INTENT_MENU_LEFT;
          ev.preventDefault();
          break;
        case "ArrowRight":
          this.pendingIntent = INTENT_MENU_RIGHT;
          ev.preventDefault();
          break;
        case "h":
        case "H":
          // OpenBacklog (Playing); ignore when used as part of a chord.
          if (!ev.ctrlKey) {
            this.pendingIntent = INTENT_OPEN_BACKLOG;
            ev.preventDefault();
          }
          break;
        case "a":
        case "A":
          this.pendingIntent = INTENT_TOGGLE_AUTO;
          break;
        case "l":
        case "L":
          if (ev.ctrlKey || ev.metaKey) {
            this.doLoad();
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
          this.pendingIntent =
            INTENT_SELECT_BASE + (ev.key.charCodeAt(0) - 49); // Select(0..8)
          break;
        default:
          break;
      }
    };

    const onKeyUp = (ev: KeyboardEvent) => {
      if (ev.key === "Control") {
        this.ctrlHeld = false;
      }
    };

    const onPointerDown = (ev: PointerEvent) => {
      const { x, y } = pointerToLogical(canvas, ev);
      const row = choiceRowAt(x, y);
      if (row >= 0) {
        // Select(row) — engine ignores when not in Choose; commits when it is.
        this.pendingIntent = INTENT_SELECT_BASE + row;
      } else {
        this.pendingIntent = INTENT_ADVANCE;
      }
    };

    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    canvas.addEventListener("pointerdown", onPointerDown);

    this.unbindInput = () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      canvas.removeEventListener("pointerdown", onPointerDown);
    };
  }

  /** rAF body from boot.js */
  frame = (ts: number): void => {
    if (!this.running) return;
    this.rafId = requestAnimationFrame(this.frame);
    if (!this.exports_) return;
    const dt = this.lastTs ? Math.min(100, ts - this.lastTs) : 16.6;
    this.lastTs = ts;
    const intent = this.pendingIntent;
    this.pendingIntent = 0;
    try {
      this.exports_.export_frame(intent, dt, this.ctrlHeld ? 1 : 0);
      flushPendingGlyphs(this.exports_);
      flushAudio(this.audio, this.exports_);
      // After UI actions: prefs + multi-slot may have changed in-engine.
      if (intent !== INTENT_NONE) {
        this.prefs = savePrefsToStorage(this.exports_, this.prefs);
        applyPrefsToAudio(this.audio);
        this.syncSlotsToStorage();
      }
      // Glyphs marked ready appear next frame (Phase 1; no second export/tick).
      const pack = copyFrame(this.exports_);
      drawPack(pack, this.resolveRes);
    } catch (e) {
      console.error("frame error", e);
    }
  };

  /**
   * Start session on canvas: WebGPU → font → wasm → manifest → loop.
   * Preserves WebGPU missing error message from Gpu.init.
   */
  async start(
    canvas: HTMLCanvasElement,
    options: GameSessionOptions = {},
  ): Promise<GameSessionHandle> {
    this.onStatus = options.onStatus ?? null;
    this.audio.setStatus = (m) => this.setStatus(m);
    this.running = true;

    try {
      this.setStatus("init WebGPU…");
      await Gpu.init(canvas);
      fitCanvas(canvas);
      const onResize = () => fitCanvas(canvas);
      window.addEventListener("resize", onResize);
      this.unbindResize = () => window.removeEventListener("resize", onResize);
      this.bindInput(canvas);

      const params = new URLSearchParams(location.search);
      // Font + Slug GPU. Modes: ?glyph=slug (default path in boot was canvas) | canvas | cpu-outline
      const fontUrl =
        options.fontUrl ||
        params.get("font") ||
        "./fonts/NotoSans-Regular.ttf";
      // Default to canvas fillText (reliable). GPU Slug: ?glyph=slug
      const glyphMode = options.glyphMode || params.get("glyph") || "canvas";
      try {
        this.setStatus("load font…");
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
          if (wctx) {
            wctx.font = '32px "Noto Sans", "NotoSans", sans-serif';
            wctx.fillStyle = "#ffffff";
            wctx.fillText("WABCMygj", 2, 40);
          }
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
        this.setStatus(`font ready (${glyphMode})`);
      } catch (e) {
        console.warn("font/slug init failed; canvas glyphs", e);
        Gpu.setGlyphRasterMode("canvas");
      }

      const wasmUrl =
        options.wasmUrl || params.get("wasm") || "./host_web.wasm";

      this.setStatus(`load wasm ${wasmUrl}…`);
      this.exports_ = (await loadWasm(wasmUrl)) as HostExports;

      const manifestUrl =
        options.manifestUrl || params.get("manifest") || "./manifest.json";
      const manifest = (await loadManifest(manifestUrl)) as Manifest | null;

      // Pass manifest so save_slots applies before slot hydration / boot_title.
      this.setStatus("init engine…");
      await this.maybeLoadSource(manifest);
      await this.applyManifest(manifest);

      // Delay first frame one rAF so font/GPU state settles before typewriter.
      this.setStatus("running (click / Enter to advance)");
      requestAnimationFrame(() => {
        if (this.running) {
          this.rafId = requestAnimationFrame(this.frame);
        }
      });
    } catch (e) {
      const msg = String(
        e && typeof e === "object" && "message" in e
          ? (e as Error).message
          : e,
      );
      this.setStatus(msg);
      console.error(e);
      throw e;
    }

    return {
      exports: () => this.exports_,
      save: this.doSave,
      load: this.doLoad,
      setIntent: (code: number) => {
        this.pendingIntent = code | 0;
      },
      stop: () => this.stop(),
    };
  }

  stop(): void {
    this.running = false;
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = 0;
    }
    this.unbindInput?.();
    this.unbindInput = null;
    this.unbindResize?.();
    this.unbindResize = null;
    stopBgm(this.audio);
  }
}

/** Singleton helper for App.svelte */
let defaultSession: GameSession | null = null;

export async function startGameSession(
  canvas: HTMLCanvasElement,
  options: GameSessionOptions = {},
): Promise<GameSessionHandle> {
  if (defaultSession) {
    defaultSession.stop();
  }
  defaultSession = new GameSession();
  return defaultSession.start(canvas, options);
}
