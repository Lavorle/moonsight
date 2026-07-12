/**
 * Player preferences — key moonsight/prefs (same shape as boot.js).
 * Persistence goes through SaveStore (WebSaveStore is the browser backend).
 */

import { PREFS_KEY, type SaveStore } from "./saveStore";

export { PREFS_KEY };

export type Prefs = {
  text_speed: number;
  auto_mode: boolean;
  master_volume: number;
  bgm_volume: number;
  se_volume: number;
};

export const DEFAULT_PREFS: Prefs = {
  text_speed: 1.0,
  auto_mode: false,
  master_volume: 1.0,
  bgm_volume: 1.0,
  se_volume: 1.0,
};

/** Clamp volume to [0, 1]; treat non-finite as 1 (keeps volume 0 valid). */
export function clampVolume(v: unknown): number {
  const n = Number(v);
  return Math.max(0, Math.min(1, Number.isFinite(n) ? n : 1));
}

export function parsePrefsJson(raw: string, fallback: Prefs = DEFAULT_PREFS): Prefs {
  try {
    const p = JSON.parse(raw) as Record<string, unknown>;
    return {
      text_speed: Number(p.text_speed ?? fallback.text_speed),
      auto_mode: !!p.auto_mode,
      master_volume: clampVolume(p.master_volume ?? fallback.master_volume),
      bgm_volume: clampVolume(p.bgm_volume ?? fallback.bgm_volume),
      se_volume: clampVolume(p.se_volume ?? fallback.se_volume),
    };
  } catch {
    return { ...fallback };
  }
}

/**
 * Read prefs from SaveStore (JSON only; does not touch wasm).
 */
export function readPrefsFromStorage(store: SaveStore): Prefs | null {
  try {
    const raw = store.loadPrefs();
    if (!raw) return null;
    return parsePrefsJson(raw);
  } catch {
    /* private mode / blocked storage */
    return null;
  }
}

/**
 * Write a prefs JSON string via SaveStore.
 */
export async function writePrefsToStorage(
  store: SaveStore,
  json: string,
): Promise<void> {
  if (json && json.length) {
    await store.savePrefs(json);
  }
}

export type PrefsWasmExports = {
  set_prefs_json?: (json: string) => number;
  prefs_json?: () => string;
};

/**
 * Load prefs from SaveStore into JS + optional wasm engine (boot.js parity).
 * Returns the effective JS prefs object.
 */
export function loadPrefsFromStorage(
  store: SaveStore,
  exports_: PrefsWasmExports | null,
  current: Prefs,
): Prefs {
  let prefs = { ...current };
  try {
    const raw = store.loadPrefs();
    if (raw && typeof exports_?.set_prefs_json === "function") {
      const rc = exports_.set_prefs_json(raw);
      if (rc === 0 && typeof exports_.prefs_json === "function") {
        const applied = exports_.prefs_json();
        if (applied) prefs = parsePrefsJson(applied, prefs);
      }
    } else if (raw) {
      prefs = parsePrefsJson(raw, prefs);
    }
  } catch {
    /* blocked storage */
  }
  return prefs;
}

/**
 * Persist engine prefs via SaveStore when present; return updated JS prefs.
 */
export async function savePrefsToStorage(
  store: SaveStore,
  exports_: PrefsWasmExports | null,
  current: Prefs,
): Promise<Prefs> {
  let prefs = { ...current };
  if (typeof exports_?.prefs_json === "function") {
    const json = exports_.prefs_json();
    if (json && json.length) {
      await store.savePrefs(json);
      prefs = parsePrefsJson(json, prefs);
    }
  }
  return prefs;
}
