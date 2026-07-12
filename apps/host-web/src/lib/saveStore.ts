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

export type SaveWriteEvent = {
  operation: "save-prefs" | "save-slot";
  slot?: number;
  state: "pending" | "committed" | "failed";
  error?: unknown;
};

export type SaveWriteObserver = (event: SaveWriteEvent) => void;

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

/** Serialize writes and expose their pending/committed/failed lifecycle. */
export class TrackedSaveStore implements SaveStore {
  private readonly inner: SaveStore;
  private readonly observe: SaveWriteObserver;
  private tail: Promise<void> = Promise.resolve();
  private failures = new Map<string, unknown>();

  constructor(inner: SaveStore, observe: SaveWriteObserver = () => {}) {
    this.inner = inner;
    this.observe = observe;
  }

  loadPrefs(): string | null {
    return this.inner.loadPrefs();
  }

  savePrefs(json: string): Promise<void> {
    return this.enqueue("save-prefs", undefined, () =>
      this.inner.savePrefs(json),
    );
  }

  loadSlot(slot: number): string | null {
    return this.inner.loadSlot(slot);
  }

  saveSlot(slot: number, json: string): Promise<void> {
    return this.enqueue("save-slot", slot, () =>
      this.inner.saveSlot(slot, json),
    );
  }

  async flush(): Promise<void> {
    await this.tail;
    await this.inner.flush();
    if (this.failures.size > 0) {
      throw new AggregateError(
        Array.from(this.failures.values()),
        "One or more save writes failed",
      );
    }
  }

  private enqueue(
    operation: "save-prefs" | "save-slot",
    slot: number | undefined,
    write: () => Promise<void>,
  ): Promise<void> {
    const eventBase = slot == null ? { operation } : { operation, slot };
    const key = `${operation}:${slot ?? "prefs"}`;
    this.observe({ ...eventBase, state: "pending" });
    const run = this.tail.then(write, write);
    const observed = run.then(
      () => {
        this.failures.delete(key);
        this.observe({ ...eventBase, state: "committed" });
      },
      (error: unknown) => {
        this.failures.set(key, error);
        this.observe({ ...eventBase, state: "failed", error });
        throw error;
      },
    );
    this.tail = observed.catch(() => {});
    return observed;
  }
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
    } catch (cause) {
      throw new SaveStoreError("save-prefs", "Unable to save preferences", {
        cause,
      });
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
    } catch (cause) {
      throw new SaveStoreError("save-slot", `Unable to save slot ${slot}`, {
        slot,
        cause,
      });
    }
  }

  /** localStorage.setItem is synchronous; returning marks the durable boundary. */
  async flush(): Promise<void> {}
}
