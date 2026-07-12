/** Host persistence boundary (spec Q4 §3.3). Engine save JSON stays v4. */

export interface SaveStore {
  loadPrefs(): string | null;
  savePrefs(json: string): Promise<void>;
  loadSlot(slot: number): string | null;
  saveSlot(slot: number, json: string): Promise<void>;
  flush(): Promise<void>;
}

export type SaveStoreOperation =
  | "load-prefs"
  | "save-prefs"
  | "load-slot"
  | "save-slot"
  | "flush";

export class SaveStoreError extends Error {
  readonly operation: SaveStoreOperation;
  readonly slot: number | null;

  constructor(
    operation: SaveStoreOperation,
    message: string,
    options: { slot?: number; cause?: unknown } = {},
  ) {
    super(message, { cause: options.cause });
    this.name = "SaveStoreError";
    this.operation = operation;
    this.slot = options.slot ?? null;
  }
}

export type StorageLike = Pick<Storage, "getItem" | "setItem">;

export const PREFS_KEY = "moonsight/prefs";
export const SAVE_KEY = (slot: number) => `moonsight/save/${slot}`;

/** In-memory store for unit tests. */
export class MemorySaveStore implements SaveStore {
  prefs: string | null = null;
  slots = new Map<number, string>();
  loadPrefs(): string | null {
    return this.prefs;
  }
  async savePrefs(json: string): Promise<void> {
    this.prefs = json;
  }
  loadSlot(slot: number): string | null {
    return this.slots.get(slot) ?? null;
  }
  async saveSlot(slot: number, json: string): Promise<void> {
    this.slots.set(slot, json);
  }

  async flush(): Promise<void> {}
}

export class WebSaveStore implements SaveStore {
  private readonly storage: StorageLike;

  constructor(storage: StorageLike = localStorage) {
    this.storage = storage;
  }

  loadPrefs(): string | null {
    try {
      return this.storage.getItem(PREFS_KEY);
    } catch (cause) {
      throw new SaveStoreError("load-prefs", "Unable to read preferences", {
        cause,
      });
    }
  }

  async savePrefs(json: string): Promise<void> {
    try {
      if (json && json.length) this.storage.setItem(PREFS_KEY, json);
    } catch {
      console.error("[moonsight] savePrefs failed");
    }
  }

  loadSlot(slot: number): string | null {
    try {
      return this.storage.getItem(SAVE_KEY(slot));
    } catch (cause) {
      throw new SaveStoreError("load-slot", `Unable to read save slot ${slot}`, {
        slot,
        cause,
      });
    }
  }

  async saveSlot(slot: number, json: string): Promise<void> {
    try {
      if (json && json.length) this.storage.setItem(SAVE_KEY(slot), json);
    } catch {
      console.error("[moonsight] saveSlot failed", slot);
    }
  }

  /** localStorage.setItem is synchronous; returning marks the durable boundary. */
  async flush(): Promise<void> {}
}
