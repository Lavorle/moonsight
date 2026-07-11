/**
 * Desktop SaveStore: Tauri appData via invoke, with preload + write-through cache.
 * Sync SaveStore API; disk IO is async (fire-and-forget writes after cache update).
 */

import type { SaveStore } from "./saveStore";

export type Invoke = <T>(
  cmd: string,
  args?: Record<string, unknown>,
) => Promise<T>;

/** Resolve Tauri invoke without bundling @tauri-apps/api (web build stays pure). */
export function getTauriInvoke(): Invoke | null {
  const w = window as unknown as {
    __TAURI__?: { core?: { invoke?: Invoke } };
    __TAURI_INTERNALS__?: { invoke?: Invoke };
  };
  return w.__TAURI_INTERNALS__?.invoke ?? w.__TAURI__?.core?.invoke ?? null;
}

export function isTauriRuntime(): boolean {
  return !!(window as unknown as { __TAURI_INTERNALS__?: unknown })
    .__TAURI_INTERNALS__;
}

export class DesktopSaveStore implements SaveStore {
  private prefs: string | null = null;
  private slots = new Map<number, string>();
  private invoke: Invoke;

  private constructor(invoke: Invoke) {
    this.invoke = invoke;
  }

  /**
   * Preload prefs + slots into memory so GameSession can use the sync SaveStore API.
   */
  static async create(
    invoke: Invoke,
    slotCount = 6,
  ): Promise<DesktopSaveStore> {
    const s = new DesktopSaveStore(invoke);
    s.prefs = (await invoke<string | null>("read_prefs")) ?? null;
    for (let i = 0; i < slotCount; i++) {
      const body = await invoke<string | null>("read_save_slot", { slot: i });
      if (body) s.slots.set(i, body);
    }
    return s;
  }

  loadPrefs(): string | null {
    return this.prefs;
  }

  savePrefs(json: string): void {
    this.prefs = json;
    void this.invoke("write_prefs", { body: json }).catch((e) =>
      console.error("[moonsight] write_prefs", e),
    );
  }

  loadSlot(slot: number): string | null {
    return this.slots.get(slot) ?? null;
  }

  saveSlot(slot: number, json: string): void {
    this.slots.set(slot, json);
    void this.invoke("write_save_slot", { slot, body: json }).catch((e) =>
      console.error("[moonsight] write_save_slot", e),
    );
  }
}
