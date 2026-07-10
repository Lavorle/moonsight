/**
 * BGM/SE HTMLAudioElement glue — extracted from host_web/js_glue/boot.js.
 * Prefer OGG, fallback MP3. Web Audio unlock on first user gesture.
 */

import { clampVolume } from "./prefs";

/** Audio event kinds from host_web exports */
export const AUDIO_PLAY_BGM = 0;
export const AUDIO_STOP_BGM = 1;
export const AUDIO_PLAY_SE = 2;
export const AUDIO_SET_BGM_VOLUME = 3;

export type AudioUrlAlt = { ogg: string; mp3: string };
export type AudioUrlOrAlt = string | AudioUrlAlt;

export type AudioWasmExports = {
  audio_event_count?: () => number;
  audio_event_kind?: (i: number) => number;
  audio_event_resource?: (i: number) => string;
  audio_event_looped?: (i: number) => number;
  audio_event_volume?: (i: number) => number;
  audio_clear_events?: () => void;
};

export type AudioHost = {
  /** logical audio id → primary URL or dual-format alt */
  audioUrls: Record<string, AudioUrlOrAlt>;
  bgmEl: HTMLAudioElement | null;
  bgmId: string | null;
  /** Last logical BGM volume from mixer events (before prefs multiply). */
  lastLogicalBgmVol: number;
  audioCtx: AudioContext | null;
  /** Optional status surface for hard-fail messages (boot.js #status). */
  setStatus?: (msg: string) => void;
};

export function createAudioHost(): AudioHost {
  return {
    audioUrls: Object.create(null) as Record<string, AudioUrlOrAlt>,
    bgmEl: null,
    bgmId: null,
    lastLogicalBgmVol: 1.0,
    audioCtx: null,
  };
}

/** True if path already has a known audio extension (optional query). */
export function hasAudioExt(path: string): boolean {
  return /\.(ogg|mp3|wav|m4a)(\?.*)?$/i.test(path);
}

/**
 * Dual-format alt list for extensionless paths: OGG first, then MP3.
 */
export function dualFormat(base: string): AudioUrlAlt {
  return { ogg: `${base}.ogg`, mp3: `${base}.mp3` };
}

/**
 * Resolve a logical audio id to a playable URL or dual-format alt.
 */
export function resolveAudioUrl(
  host: AudioHost,
  id: string | null | undefined,
): AudioUrlOrAlt | null {
  if (!id) return null;
  if (host.audioUrls[id] != null) return host.audioUrls[id];
  if (hasAudioExt(id)) return id;
  return dualFormat(id);
}

/**
 * Output BGM gain = logical only (mixer already applied master × bgm prefs).
 */
export function effectiveBgmVolume(logical: number): number {
  return clampVolume(logical);
}

/**
 * Output SE gain = logical only (mixer already applied master × se prefs).
 */
export function effectiveSeVolume(logical: number): number {
  return clampVolume(logical);
}

/**
 * Ensure AudioContext is running after a user gesture (autoplay policy).
 */
export function ensureAudioUnlocked(host: AudioHost): void {
  try {
    if (!host.audioCtx) {
      const AC =
        window.AudioContext ||
        (window as unknown as { webkitAudioContext?: typeof AudioContext })
          .webkitAudioContext;
      if (AC) host.audioCtx = new AC();
    }
    if (host.audioCtx && host.audioCtx.state === "suspended") {
      host.audioCtx.resume().catch(() => {});
    }
  } catch {
    /* ignore */
  }
}

/**
 * Hard-fail audio load — same surface as texture hard-fail.
 */
export function audioLoadFailed(
  host: AudioHost,
  id: string,
  detail?: unknown,
): never {
  console.error("audio load failed:", id, detail != null ? detail : "");
  const msg =
    detail != null && String(detail).length
      ? `MoonSight: failed to load audio '${id}': ${detail}`
      : `MoonSight: failed to load audio '${id}'`;
  try {
    if (host.setStatus) {
      host.setStatus(msg);
    } else {
      const status =
        typeof document !== "undefined"
          ? document.querySelector("#status")
          : null;
      if (status) status.textContent = msg;
    }
  } catch {
    /* ignore */
  }
  throw new Error(msg);
}

/**
 * Autoplay policy and interrupted play() — not a missing/broken asset load.
 */
export function isBenignPlayReject(e: unknown): boolean {
  return !!(
    e &&
    typeof e === "object" &&
    "name" in e &&
    (e.name === "NotAllowedError" || e.name === "AbortError")
  );
}

/**
 * Arm HTMLAudioElement error → hard-fail (async path after makeAudio).
 */
export function armAudioLoadHardFail(
  host: AudioHost,
  el: HTMLAudioElement,
  id: string,
  isActive?: () => boolean,
): void {
  el.addEventListener(
    "error",
    () => {
      if (typeof isActive === "function" && !isActive()) return;
      try {
        const code = el.error && el.error.code;
        audioLoadFailed(
          host,
          id,
          code != null ? `media error code ${code}` : "media error",
        );
      } catch {
        /* already surfaced via #status / console */
      }
    },
    { once: true },
  );
}

export function makeAudio(
  urlOrAlt: AudioUrlOrAlt,
  opts: { loop?: boolean; volume?: number } = {},
): HTMLAudioElement {
  const el = new Audio();
  el.preload = "auto";
  el.loop = !!opts.loop;
  el.volume = clampVolume(opts.volume ?? 1);
  if (typeof urlOrAlt === "string") {
    el.src = urlOrAlt;
  } else {
    // Prefer OGG via <source>, then MP3. Do not set el.src.
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

export function stopBgm(host: AudioHost): void {
  if (host.bgmEl) {
    const el = host.bgmEl;
    // Drop ownership before teardown so armed error handlers ignore
    // the error event from removeAttribute("src") + load().
    host.bgmEl = null;
    host.bgmId = null;
    try {
      el.pause();
      el.removeAttribute("src");
      el.load();
    } catch {
      /* ignore */
    }
  } else {
    host.bgmId = null;
  }
}

/**
 * Apply mid-fade / volume-only BGM change without restarting the track.
 */
export function setBgmVolume(host: AudioHost, volume: number): void {
  host.lastLogicalBgmVol = clampVolume(volume);
  if (host.bgmEl) {
    host.bgmEl.volume = effectiveBgmVolume(host.lastLogicalBgmVol);
  }
}

/** Re-apply prefs gains to the current BGM element. */
export function applyPrefsToAudio(host: AudioHost): void {
  if (host.bgmEl) {
    host.bgmEl.volume = effectiveBgmVolume(host.lastLogicalBgmVol);
  }
}

/**
 * Play BGM by logical id. Missing URL or media load failure hard-fails;
 * autoplay / AbortError only warn.
 */
export function playBgm(
  host: AudioHost,
  id: string,
  looped: boolean,
  volume: number,
): void {
  const url = resolveAudioUrl(host, id);
  if (!url) {
    audioLoadFailed(host, id, "no URL for BGM");
  }
  host.lastLogicalBgmVol = clampVolume(volume);
  const vol = effectiveBgmVolume(host.lastLogicalBgmVol);
  if (host.bgmId === id && host.bgmEl && !host.bgmEl.paused) {
    host.bgmEl.volume = vol;
    host.bgmEl.loop = !!looped;
    return;
  }
  stopBgm(host);
  ensureAudioUnlocked(host);
  const el = makeAudio(url, { loop: looped, volume: vol });
  host.bgmEl = el;
  host.bgmId = id;
  armAudioLoadHardFail(host, el, id, () => host.bgmEl === el);
  const p = el.play();
  if (p && typeof p.catch === "function") {
    p.catch((e) => {
      if (isBenignPlayReject(e)) {
        console.warn("bgm play blocked/failed", id, e);
        return;
      }
      if (host.bgmEl !== el) return;
      try {
        audioLoadFailed(host, id, e);
      } catch {
        /* surfaced */
      }
    });
  }
}

/**
 * Play SE by logical id. Missing URL or media load failure hard-fails;
 * autoplay / AbortError only warn.
 */
export function playSe(host: AudioHost, id: string, volume: number): void {
  const url = resolveAudioUrl(host, id);
  if (!url) {
    audioLoadFailed(host, id, "no URL for SE");
  }
  ensureAudioUnlocked(host);
  const el = makeAudio(url, {
    loop: false,
    volume: effectiveSeVolume(volume),
  });
  armAudioLoadHardFail(host, el, id);
  const p = el.play();
  if (p && typeof p.catch === "function") {
    p.catch((e) => {
      if (isBenignPlayReject(e)) {
        console.warn("se play blocked/failed", id, e);
        return;
      }
      try {
        audioLoadFailed(host, id, e);
      } catch {
        /* surfaced */
      }
    });
  }
}

/**
 * Drain mixer events exported by MoonBit and apply via HTMLAudioElement.
 */
export function flushAudio(host: AudioHost, exports_: AudioWasmExports): void {
  if (typeof exports_.audio_event_count !== "function") return;
  const n = exports_.audio_event_count() | 0;
  if (n <= 0) return;
  for (let i = 0; i < n; i++) {
    const kind = (exports_.audio_event_kind?.(i) ?? 0) | 0;
    if (kind === AUDIO_PLAY_BGM) {
      const id = exports_.audio_event_resource?.(i) || "";
      const looped = ((exports_.audio_event_looped?.(i) ?? 0) | 0) !== 0;
      const volume = clampVolume(exports_.audio_event_volume?.(i));
      playBgm(host, id, looped, volume);
    } else if (kind === AUDIO_STOP_BGM) {
      stopBgm(host);
    } else if (kind === AUDIO_PLAY_SE) {
      const id = exports_.audio_event_resource?.(i) || "";
      const volume = clampVolume(exports_.audio_event_volume?.(i));
      playSe(host, id, volume);
    } else if (kind === AUDIO_SET_BGM_VOLUME) {
      setBgmVolume(host, exports_.audio_event_volume?.(i) ?? 1);
    }
  }
  if (typeof exports_.audio_clear_events === "function") {
    exports_.audio_clear_events();
  }
}

/**
 * Register audio URLs from manifest.audio (boot.js applyManifest audio branch).
 */
export function registerManifestAudio(
  host: AudioHost,
  audio: Record<string, unknown> | undefined | null,
): void {
  if (!audio || typeof audio !== "object") return;
  host.audioUrls = Object.create(null) as Record<string, AudioUrlOrAlt>;
  for (const [id, path] of Object.entries(audio)) {
    if (typeof path === "string" && path.length) {
      host.audioUrls[id] = hasAudioExt(path) ? path : dualFormat(path);
      console.info("audio", id, "←", path);
    }
  }
}
