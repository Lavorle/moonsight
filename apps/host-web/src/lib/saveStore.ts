/** Host persistence boundary (spec Q4 §3.3). Engine save JSON stays v4. */

export interface SaveStore {
  loadPrefs(): string | null;
  savePrefs(json: string): void;
  loadSlot(slot: number): string | null;
  saveSlot(slot: number, json: string): void;
}

export const PREFS_KEY = "moonsight/prefs";
export const SAVE_KEY = (slot: number) => `moonsight/save/${slot}`;

/** In-memory store for unit tests. */
export class MemorySaveStore implements SaveStore {
  prefs: string | null = null;
  slots = new Map<number, string>();
  loadPrefs(): string | null {
    return this.prefs;
  }
  savePrefs(json: string): void {
    this.prefs = json;
  }
  loadSlot(slot: number): string | null {
    return this.slots.get(slot) ?? null;
  }
  saveSlot(slot: number, json: string): void {
    this.slots.set(slot, json);
  }
}

export class WebSaveStore implements SaveStore {
  loadPrefs(): string | null {
    try {
      return localStorage.getItem(PREFS_KEY);
    } catch {
      return null;
    }
  }
  savePrefs(json: string): void {
    try {
      if (json && json.length) localStorage.setItem(PREFS_KEY, json);
    } catch {
      console.error("[moonsight] savePrefs failed");
    }
  }
  loadSlot(slot: number): string | null {
    try {
      return localStorage.getItem(SAVE_KEY(slot));
    } catch {
      return null;
    }
  }
  saveSlot(slot: number, json: string): void {
    try {
      if (json && json.length) localStorage.setItem(SAVE_KEY(slot), json);
    } catch {
      console.error("[moonsight] saveSlot failed", slot);
    }
  }
}
