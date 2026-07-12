/**
 * Desktop SaveStore: Tauri appData via invoke, with preload + write-through cache.
 * Writes are serialized and resolve only after Rust confirms durable replacement.
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
  private writeTail: Promise<void> = Promise.resolve();
  private firstWriteFailure: unknown = null;

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

  private enqueue(operation: () => Promise<unknown>): Promise<void> {
    const result = this.writeTail.then(operation).then(() => undefined);
    this.writeTail = result.catch((error: unknown) => {
      if (this.firstWriteFailure === null) this.firstWriteFailure = error;
    });
    return result;
  }

  savePrefs(json: string): Promise<void> {
    return this.enqueue(() => this.invoke("write_prefs", { body: json })).then(
      () => {
        this.prefs = json;
      },
    );
  }

  loadSlot(slot: number): string | null {
    return this.slots.get(slot) ?? null;
  }

  saveSlot(slot: number, json: string): Promise<void> {
    return this.enqueue(() =>
      this.invoke("write_save_slot", { slot, body: json }),
    ).then(() => {
      this.slots.set(slot, json);
    });
  }

  /**
   * Wait for all writes queued before this call, then cross a Rust-side lock
   * and directory-sync barrier. Rejects with the first write/barrier failure.
   */
  async flush(): Promise<void> {
    const barrier = this.enqueue(() => this.invoke("flush_persistence"));
    await barrier.catch(() => undefined);

    const failure = this.firstWriteFailure;
    this.firstWriteFailure = null;
    if (failure !== null) throw failure;
  }
}
