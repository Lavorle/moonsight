/**
 * Game session: owns wasm exports, intent, ctrlHeld, rAF loop, input.
 * Behavior ported from archived vanilla boot.js (archive/js_glue).
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
  INTENT_ROLLBACK,
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
  parsePrefsJson,
  savePrefsToStorage,
  withLocalePreference,
  type Prefs,
} from "./prefs";
import {
  SAVE_KEY,
  TrackedSaveStore,
  WebSaveStore,
  type SaveStore,
  type SaveWriteEvent,
} from "./saveStore";
import {
  clampSaveSlotCount,
  classifyRuntimeLoadFailure,
  classifyStoredSlot,
  hydrateStoredSlots,
  type SaveSlotState,
} from "./saveSlots";
import { loadTheme } from "./theme";
import {
  loadGameBundle,
  loadManifest,
  loadWasm,
  upgradeLegacySave,
  validateContentManifest,
  type ContentMode,
} from "./wasm";

const PACK_HEADER = 4;
const SPRITE_STRIDE = 7;
/** atlas_x,y,w,h, x,y, screen_w,screen_h, r,g,b,a */
const GLYPH_STRIDE = 12;

/** Fixed logical resolution; MoonBit packs all draw coords in FHD pixels. */
export const LOGICAL_W = 1920;
export const LOGICAL_H = 1080;

/** Flexible host_web wasm export surface used by the boot loop. */
export type HostExports = WebAssembly.Exports & {
  frame_len: () => number;
  frame_at: (i: number) => number;
  export_frame: (intent: number, dt: number, skipHeld: number) => void;
  /** phase: 0=move, 1=down, 2=up, 3=leave; returns hover_kind for cursor. */
  export_pointer?: (x: number, y: number, phase: number) => number;
  /** Vertical wheel; dy>0 → reveal older (host maps -event.deltaY). */
  export_wheel?: (x: number, y: number, dy: number) => number;
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
  /** H4: dynamic atlas edge after grow/repack. */
  atlas_width?: () => number;
  atlas_height?: () => number;
  atlas_generation?: () => number;
  set_prefs_json?: (json: string) => number;
  prefs_json?: () => string;
  set_slot_json?: (slot: number, json: string) => void;
  get_slot_json?: (slot: number) => string;
  save_slot_count?: () => number;
  set_save_slots?: (n: number) => number;
  set_module_id?: (moduleId: string) => number;
  boot_title?: () => number;
  load_msb?: (raw: string) => number;
  load_source?: (src: string) => number;
  init_demo?: () => void;
  save_json?: (slot: number) => string;
  load_json?: (json: string) => number;
  load_error?: () => string;
  slot_load_error_slot?: () => number;
  consume_slot_load_error?: () => string;
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
  /** Persistence backend; defaults to WebSaveStore. */
  store?: SaveStore;
  /** Preloaded manifest, used so desktop slot preload matches save_slots. */
  manifest?: Manifest | null;
  /** Production fails closed; demo explicitly permits development fallback. */
  contentMode?: ContentMode;
  onSaveSlotState?: (state: SaveSlotState) => void;
};

export type GameSessionHandle = {
  exports: () => HostExports | null;
  save: () => Promise<void>;
  load: () => Promise<void>;
  setIntent: (code: number) => void;
  slotStates: () => SaveSlotState[];
  stop: () => Promise<void>;
};

export type Manifest = {
  name?: string;
  resources?: Record<string, string>;
  audio?: Record<string, string>;
  save_slots?: number;
  digests?: Record<string, string>;
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

/** Cached atlas edge/generation so GPU texture rebuilds on MoonBit grow (H4). */
let lastAtlasGeneration = -1;
let atlasEdge = 1024;

/**
 * Sync GPU atlas texture size with wasm atlas exports. Rebuilds when
 * `atlas_generation` bumps or the edge changes.
 */
function ensureAtlasTexture(exports_: HostExports): number {
  const gen = exports_.atlas_generation?.() ?? 0;
  const w = exports_.atlas_width?.() ?? 1024;
  const h = exports_.atlas_height?.() ?? 1024;
  const edge = Math.max(w | 0, h | 0, 1);
  if (gen !== lastAtlasGeneration || edge !== atlasEdge) {
    lastAtlasGeneration = gen;
    atlasEdge = edge;
    Gpu.resizeGlyphAtlas(edge);
  }
  return edge;
}

/**
 * Rasterize pending glyphs. Only mark ready when stamp has real ink
 * (or is whitespace). Empty stamps stay pending so the next frame retries.
 * Terminal 0×0 overflows are skipped (not a hard failure).
 *
 * Snapshot the full pending list before mark_glyph_ready mutates the queue
 * (post-grow bulk re-upload would otherwise skip entries under an index walk).
 */
function flushPendingGlyphs(exports_: HostExports): void {
  if (typeof exports_.pending_glyph_count !== "function") return;
  const n = exports_.pending_glyph_count() | 0;
  if (n <= 0) return;
  const edge = ensureAtlasTexture(exports_);
  // Snapshot all slots first; mark_ready removes from pending_queue.
  const pending: Array<{
    cp: number;
    size: number;
    atlasX: number;
    atlasY: number;
    atlasW: number;
    atlasH: number;
  }> = [];
  for (let i = 0; i < n; i++) {
    pending.push({
      cp: (exports_.pending_glyph_cp?.(i) ?? 0) | 0,
      size: (exports_.pending_glyph_size?.(i) ?? 0) | 0,
      atlasX: (exports_.pending_glyph_atlas_x?.(i) ?? 0) | 0,
      atlasY: (exports_.pending_glyph_atlas_y?.(i) ?? 0) | 0,
      atlasW: (exports_.pending_glyph_atlas_w?.(i) ?? 0) | 0,
      atlasH: (exports_.pending_glyph_atlas_h?.(i) ?? 0) | 0,
    });
  }
  let anyFailed = false;
  for (const g of pending) {
    const { cp, size, atlasX, atlasY, atlasW, atlasH } = g;
    // Terminal overflow / invalid slot: skip without retry storm.
    if (size <= 0 || atlasW <= 0 || atlasH <= 0) {
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
        edge,
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
 * Accepts PointerEvent / WheelEvent (any clientX/clientY source).
 */
function pointerToLogical(
  canvas: HTMLCanvasElement,
  ev: { clientX: number; clientY: number },
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
  /**
   * Set after successful export_pointer down so prefs/slots still sync even when
   * pendingIntent is cleared to NONE (avoid same-frame double Advance).
   */
  pointerDirty = false;
  /** Ctrl held → skip_held flag each frame (not one-shot SkipTyping). */
  ctrlHeld = false;
  lastTs = 0;
  saveSlot = 0;
  prefs: Prefs = { ...DEFAULT_PREFS };
  audio: AudioHost = createAudioHost();
  /** Host persistence boundary (SaveStore). */
  store: SaveStore;
  private slotStates_ = new Map<number, SaveSlotState>();
  private persistedSlots = new Map<number, string>();
  private activeManifest: Manifest | null = null;

  private onStatus: ((msg: string) => void) | null = null;
  private onSaveSlotState: ((state: SaveSlotState) => void) | null = null;
  private rafId = 0;
  private running = false;
  private unbindInput: (() => void) | null = null;
  private unbindResize: (() => void) | null = null;

  constructor(store: SaveStore = new WebSaveStore()) {
    this.store = this.trackStore(store);
  }

  /** Persist a validated locale through the shared Web/desktop SaveStore. */
  async setLocalePreference(locale: string): Promise<void> {
    const requested = withLocalePreference(this.prefs, locale);
    const json = JSON.stringify(requested);
    if (typeof this.exports_?.set_prefs_json === "function") {
      const rc = this.exports_.set_prefs_json(json);
      if (rc !== 0) throw new Error(`runtime rejected locale preference: ${rc}`);
      const applied = this.exports_.prefs_json?.();
      this.prefs = applied ? parsePrefsJson(applied, requested) : requested;
    } else {
      this.prefs = requested;
    }
    await this.store.savePrefs(JSON.stringify(this.prefs));
    applyPrefsToAudio(this.audio);
  }

  private trackStore(store: SaveStore): SaveStore {
    return new TrackedSaveStore(store, (event) => this.onSaveWrite(event));
  }

  private setSlotState(state: SaveSlotState): void {
    this.slotStates_.set(state.slot, state);
    this.onSaveSlotState?.(state);
  }

  private onSaveWrite(event: SaveWriteEvent): void {
    if (event.operation === "save-prefs") {
      if (event.state === "failed") {
        this.setStatus(`running · preferences save failed: ${this.errorMessage(event.error)}`);
      }
      return;
    }
    const slot = event.slot ?? 0;
    if (event.state === "pending") {
      this.setSlotState({ slot, state: "write-pending" });
      this.setStatus(`running · saving slot ${slot + 1}…`);
    } else if (event.state === "failed") {
      const message = this.errorMessage(event.error);
      this.setSlotState({ slot, state: "write-failed", message });
      this.setStatus(`running · save slot ${slot + 1} failed: ${message}`);
    } else {
      const state = classifyStoredSlot(slot, this.store.loadSlot(slot));
      this.setSlotState(state);
      this.setStatus(`running · saved slot ${slot + 1}`);
    }
  }

  private errorMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
  }

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
   * Seed engine slot_blobs from SaveStore multi-slot keys.
   */
  private hydrateSlotsFromStorage(): void {
    const exports_ = this.exports_;
    if (!exports_ || typeof exports_.set_slot_json !== "function") return;
    const slotCount =
      typeof exports_.save_slot_count === "function"
        ? exports_.save_slot_count() | 0
        : 6;
    const incompatibilities = new Map<number, string>();
    const states = hydrateStoredSlots(this.store, slotCount, (slot, json) => {
      const upgraded = upgradeLegacySave(
        json,
        this.activeManifest as Record<string, unknown> | null,
      );
      if (!upgraded.ok) {
        incompatibilities.set(slot, upgraded.message);
        return;
      }
      exports_.set_slot_json?.(slot, upgraded.json);
      this.persistedSlots.set(slot, json);
    });
    for (const original of states) {
      const message = incompatibilities.get(original.slot);
      const state: SaveSlotState = message && original.state === "occupied-valid"
        ? {
            slot: original.slot,
            state: "occupied-incompatible",
            formatVersion: original.formatVersion,
            message,
          }
        : original;
      this.setSlotState(state);
      if (
        state.state === "occupied-corrupt" ||
        state.state === "occupied-incompatible" ||
        state.state === "read-failed"
      ) {
        console.warn(
          `[moonsight] slot ${state.slot + 1} ${state.state}: ${state.message}`,
        );
      }
    }
  }

  /**
   * Runtime leaves `saved_at` empty (no wall-clock FFI). Stamp ISO time so
   * slot labels show a timestamp after menu save as well as quick-save.
   */
  private stampSavedAt(json: string): string {
    try {
      const obj = JSON.parse(json) as Record<string, unknown>;
      if (!obj.saved_at) {
        obj.saved_at = new Date().toISOString();
        return JSON.stringify(obj);
      }
    } catch {
      /* keep raw json */
    }
    return json;
  }

  /**
   * Mirror engine slot_blobs back to SaveStore (menu save path).
   * Stamps missing `saved_at` and writes the stamped blob back into the engine
   * so slot labels update immediately.
   */
  private async persistSlot(slot: number, json: string): Promise<void> {
    const previous = this.persistedSlots.get(slot);
    if (previous === json) return;
    this.persistedSlots.set(slot, json);
    try {
      await this.store.saveSlot(slot, json);
    } catch (error) {
      if (this.persistedSlots.get(slot) === json) {
        if (previous == null) this.persistedSlots.delete(slot);
        else this.persistedSlots.set(slot, previous);
      }
      throw error;
    }
  }

  private async syncSlotsToStorage(): Promise<void> {
    const exports_ = this.exports_;
    if (!exports_ || typeof exports_.get_slot_json !== "function") return;
    const n =
      typeof exports_.save_slot_count === "function"
        ? exports_.save_slot_count() | 0
        : 6;
    const writes: Promise<void>[] = [];
    for (let i = 0; i < Math.max(n, 1); i++) {
      try {
        const json = exports_.get_slot_json(i);
        if (json && json.length) {
          const stamped = this.stampSavedAt(json);
          if (stamped !== json && typeof exports_.set_slot_json === "function") {
            exports_.set_slot_json(i, stamped);
          }
          writes.push(this.persistSlot(i, stamped));
        }
      } catch (error) {
        console.error(`[moonsight] slot ${i + 1} sync failed`, error);
      }
    }
    await Promise.all(writes);
  }

  private applySaveSlotsFromManifest(manifest: Manifest | null | undefined): void {
    if (
      !manifest ||
      manifest.save_slots == null ||
      typeof this.exports_?.set_save_slots !== "function"
    ) {
      return;
    }
    const n = clampSaveSlotCount(manifest.save_slots);
    const rc = this.exports_.set_save_slots(n);
    console.info("set_save_slots", n, "rc=", rc);
  }

  private applyModuleIdFromManifest(manifest: Manifest | null | undefined): void {
    if (!manifest?.name || typeof this.exports_?.set_module_id !== "function") {
      return;
    }
    const rc = this.exports_.set_module_id(manifest.name);
    console.info("set_module_id", manifest.name, "rc=", rc);
  }

  private afterEngineReady(manifest: Manifest | null | undefined): void {
    this.applySaveSlotsFromManifest(manifest);
    this.applyModuleIdFromManifest(manifest);
    this.hydrateSlotsFromStorage();
    this.prefs = loadPrefsFromStorage(this.store, this.exports_, this.prefs);
    applyPrefsToAudio(this.audio);
    if (typeof this.exports_?.boot_title === "function") {
      const rc = this.exports_.boot_title();
      console.info("boot_title rc=", rc);
    }
  }

  private runningStatus(): string {
    const issues = Array.from(this.slotStates_.values()).filter(
      (state) =>
        state.state === "occupied-corrupt" ||
        state.state === "occupied-incompatible" ||
        state.state === "read-failed" ||
        state.state === "write-failed",
    );
    return issues.length === 0
      ? "running"
      : `running · ${issues.length} save slot issue${issues.length === 1 ? "" : "s"}`;
  }

  /** Load packaged content under the caller's explicit production/demo policy. */
  private async maybeLoadSource(
    manifest: Manifest | null | undefined,
    contentMode: ContentMode,
  ): Promise<void> {
    if (!this.exports_) throw new Error("MoonSight: runtime is unavailable");
    await loadGameBundle(
      this.exports_,
      (manifest as Record<string, unknown> | null | undefined) ?? null,
      contentMode,
    );
    this.activeManifest = manifest ?? null;
    stopBgm(this.audio);
    this.afterEngineReady(manifest);
  }

  private consumeRuntimeSlotLoadFailure(): void {
    const exports_ = this.exports_;
    if (
      typeof exports_?.slot_load_error_slot !== "function" ||
      typeof exports_.consume_slot_load_error !== "function"
    ) {
      return;
    }
    const slot = exports_.slot_load_error_slot() | 0;
    const message = exports_.consume_slot_load_error();
    if (slot < 0 || !message) return;

    const prior = this.slotStates_.get(slot);
    const formatVersion =
      prior && "formatVersion" in prior ? prior.formatVersion : 0;
    const failure = classifyRuntimeLoadFailure(slot, formatVersion, message);
    this.setSlotState(failure);
    this.setStatus(
      `running · cannot load slot ${slot + 1} (${failure.state}: ${message})`,
    );
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

  doSave = async (): Promise<void> => {
    if (!this.exports_ || typeof this.exports_.save_json !== "function") return;
    let json = this.exports_.save_json(this.saveSlot);
    if (json && json.length) {
      json = this.stampSavedAt(json);
      if (typeof this.exports_.set_slot_json === "function") {
        this.exports_.set_slot_json(this.saveSlot, json);
      }
      await this.persistSlot(this.saveSlot, json);
      console.info("saved", SAVE_KEY(this.saveSlot), json.length, "bytes");
    }
  };

  doLoad = async (): Promise<void> => {
    if (!this.exports_) return;
    let state: SaveSlotState;
    try {
      state = classifyStoredSlot(
        this.saveSlot,
        this.store.loadSlot(this.saveSlot),
      );
    } catch (error) {
      state = {
        slot: this.saveSlot,
        state: "read-failed",
        message: this.errorMessage(error),
      };
    }
    this.setSlotState(state);
    if (state.state !== "occupied-valid") {
      const detail = "message" in state ? `: ${state.message}` : "";
      this.setStatus(
        `running · cannot load slot ${this.saveSlot + 1} (${state.state}${detail})`,
      );
      return;
    }
    const upgraded = upgradeLegacySave(
      state.json,
      this.activeManifest as Record<string, unknown> | null,
    );
    if (!upgraded.ok) {
      const failure: SaveSlotState = {
        slot: this.saveSlot,
        state: "occupied-incompatible",
        formatVersion: state.formatVersion,
        message: upgraded.message,
      };
      this.setSlotState(failure);
      this.setStatus(
        `running · cannot load slot ${this.saveSlot + 1} (${failure.state}: ${failure.message})`,
      );
      return;
    }
    const json = upgraded.json;
    if (typeof this.exports_.set_slot_json === "function") {
      this.exports_.set_slot_json(this.saveSlot, json);
    }
    const rc = this.exports_.load_json?.(json) ?? 1;
    console.info("load", SAVE_KEY(this.saveSlot), "rc=", rc);
    if (rc !== 0) {
      const message = this.exports_.load_error?.() || "Runtime rejected save";
      const failure = classifyRuntimeLoadFailure(
        this.saveSlot,
        state.formatVersion,
        message,
      );
      this.setSlotState(failure);
      this.setStatus(
        `running · cannot load slot ${this.saveSlot + 1} (${failure.state}: ${message})`,
      );
      return;
    }
    this.setStatus(`running · loaded slot ${this.saveSlot + 1}`);
  };

  private async persistAfterAction(): Promise<void> {
    try {
      this.prefs = await savePrefsToStorage(
        this.store,
        this.exports_,
        this.prefs,
      );
      applyPrefsToAudio(this.audio);
      await this.syncSlotsToStorage();
    } catch (error) {
      console.error("[moonsight] persistence sync failed", error);
    }
  }

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
            void this.doSave().catch((error) => {
              console.error("[moonsight] quick save failed", error);
            });
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
        case "r":
        case "R":
          if (!ev.ctrlKey && !ev.metaKey) {
            this.pendingIntent = INTENT_ROLLBACK;
            ev.preventDefault();
          }
          break;
        case "l":
        case "L":
          if (ev.ctrlKey || ev.metaKey) {
            void this.doLoad().catch((error) => {
              console.error("[moonsight] quick load failed", error);
            });
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

    // Engine owns hit-test (Button / Choice / Slider / miss→Advance).
    // phase: 0=move, 1=down, 2=up, 3=leave.
    const onPointerMove = (ev: PointerEvent) => {
      if (!this.exports_?.export_pointer) return;
      const { x, y } = pointerToLogical(canvas, ev);
      const kind = this.exports_.export_pointer(x, y, 0) | 0;
      this.applyCursor(canvas, kind);
    };

    const onPointerDown = (ev: PointerEvent) => {
      // Pre-wasm / engine not ready: ignore (do not stash ADVANCE).
      if (!this.exports_) return;
      const { x, y } = pointerToLogical(canvas, ev);
      if (this.exports_.export_pointer) {
        const kind = this.exports_.export_pointer(x, y, 1) | 0;
        this.applyCursor(canvas, kind);
        // Pointer already consumed the interaction; avoid same-frame double Advance.
        this.pendingIntent = INTENT_NONE;
        // Still need prefs/slot sync after UI actions driven by pointer.
        this.pointerDirty = true;
      } else {
        // Fallback for older wasm without export_pointer.
        this.pendingIntent = INTENT_ADVANCE;
      }
    };

    const onPointerUp = (ev: PointerEvent) => {
      if (!this.exports_?.export_pointer) return;
      const { x, y } = pointerToLogical(canvas, ev);
      this.exports_.export_pointer(x, y, 2);
    };

    const onPointerLeave = () => {
      this.exports_?.export_pointer?.(0, 0, 3);
      canvas.style.cursor = "default";
    };

    // Spec: dy>0 => scroll_y decreases (older). Map browser deltaY so "wheel up"
    // reveals older: wheel up (deltaY < 0) → positive dy to engine.
    const onWheel = (ev: WheelEvent) => {
      if (!this.exports_?.export_wheel) return;
      ev.preventDefault();
      const { x, y } = pointerToLogical(canvas, ev);
      const dy = -ev.deltaY;
      this.exports_.export_wheel(x, y, dy);
      this.pointerDirty = true;
    };

    // D3: blur / tab-hidden must clear sticky Ctrl skip.
    const onBlur = () => {
      this.ctrlHeld = false;
    };
    const onVis = () => {
      if (document.visibilityState === "hidden") {
        this.ctrlHeld = false;
        void this.store.flush().catch((error) => {
          this.setStatus(`running · save flush failed: ${this.errorMessage(error)}`);
        });
      }
    };

    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    canvas.addEventListener("pointermove", onPointerMove);
    canvas.addEventListener("pointerdown", onPointerDown);
    canvas.addEventListener("pointerup", onPointerUp);
    canvas.addEventListener("pointerleave", onPointerLeave);
    canvas.addEventListener("wheel", onWheel, { passive: false });
    window.addEventListener("blur", onBlur);
    document.addEventListener("visibilitychange", onVis);

    this.unbindInput = () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      canvas.removeEventListener("pointermove", onPointerMove);
      canvas.removeEventListener("pointerdown", onPointerDown);
      canvas.removeEventListener("pointerup", onPointerUp);
      canvas.removeEventListener("pointerleave", onPointerLeave);
      canvas.removeEventListener("wheel", onWheel);
      window.removeEventListener("blur", onBlur);
      document.removeEventListener("visibilitychange", onVis);
    };
  }

  private applyCursor(canvas: HTMLCanvasElement, kind: number): void {
    canvas.style.cursor =
      kind === 1 || kind === 2 ? "pointer" : kind === 3 ? "ew-resize" : "default";
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
    const syncAfterAction = intent !== INTENT_NONE || this.pointerDirty;
    this.pointerDirty = false;
    try {
      this.exports_.export_frame(intent, dt, this.ctrlHeld ? 1 : 0);
      if (syncAfterAction) this.consumeRuntimeSlotLoadFailure();
      flushPendingGlyphs(this.exports_);
      flushAudio(this.audio, this.exports_);
      // After UI actions (keyboard intent or pointer down): prefs + multi-slot.
      if (syncAfterAction) {
        void this.persistAfterAction();
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
    if (options.store) this.store = this.trackStore(options.store);
    this.onStatus = options.onStatus ?? null;
    this.onSaveSlotState = options.onSaveSlotState ?? null;
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

      // Amber Soft theme: solids first, then optional role PNGs (before first frame).
      try {
        this.setStatus("load theme…");
        await loadTheme(
          "./themes/amber_soft",
          Gpu.registerSolid,
          Gpu.registerImage,
        );
      } catch (e) {
        console.warn("[theme] load failed; cold placeholders remain", e);
      }

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

      this.setStatus("loading wasm…");
      this.exports_ = (await loadWasm(wasmUrl)) as HostExports;

      const manifestUrl =
        options.manifestUrl || params.get("manifest") || "./manifest.json";
      const contentMode = options.contentMode ?? "production";
      this.setStatus("loading manifest…");
      const loadedManifest =
        options.manifest ??
        (await loadManifest(manifestUrl));
      const manifest = validateContentManifest(
        loadedManifest,
        contentMode,
        manifestUrl,
      ) as Manifest | null;

      this.setStatus("init engine…");
      await this.maybeLoadSource(manifest, contentMode);
      this.setStatus("loading assets…");
      await this.applyManifest(manifest);

      // Delay first frame one rAF so font/GPU state settles before typewriter.
      this.setStatus(this.runningStatus());
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
      const errText = msg.startsWith("error:") ? msg : `error: ${msg}`;
      this.setStatus(errText);
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
      slotStates: () => Array.from(this.slotStates_.values()),
      stop: () => this.stop(),
    };
  }

  async stop(): Promise<void> {
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
    try {
      await this.store.flush();
    } catch (error) {
      this.setStatus(`running · save flush failed: ${this.errorMessage(error)}`);
      throw error;
    }
  }
}

/** Singleton helper for App.svelte */
let defaultSession: GameSession | null = null;

export async function startGameSession(
  canvas: HTMLCanvasElement,
  options: GameSessionOptions = {},
): Promise<GameSessionHandle> {
  if (defaultSession) {
    await defaultSession.stop();
  }
  defaultSession = new GameSession(options.store ?? new WebSaveStore());
  return defaultSession.start(canvas, options);
}
