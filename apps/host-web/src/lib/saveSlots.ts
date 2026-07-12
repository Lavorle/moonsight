export const MIN_SAVE_FORMAT_VERSION = 2;
export const MAX_SAVE_FORMAT_VERSION = 4;

export type SaveSlotState =
  | { slot: number; state: "empty" }
  | {
      slot: number;
      state: "occupied-valid";
      formatVersion: number;
      json: string;
    }
  | { slot: number; state: "occupied-corrupt"; message: string }
  | {
      slot: number;
      state: "occupied-incompatible";
      formatVersion: number;
      message: string;
    }
  | { slot: number; state: "read-failed"; message: string }
  | { slot: number; state: "write-pending" }
  | { slot: number; state: "write-failed"; message: string };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Classify only the JSON/version envelope; runtime performs semantic validation. */
export function classifyStoredSlot(
  slot: number,
  raw: string | null,
): SaveSlotState {
  if (!raw) return { slot, state: "empty" };
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return { slot, state: "occupied-corrupt", message: "Invalid save JSON" };
  }
  if (!isRecord(value) || !Number.isInteger(value.format_version)) {
    return {
      slot,
      state: "occupied-corrupt",
      message: "Missing numeric format_version",
    };
  }
  const formatVersion = value.format_version as number;
  if (
    formatVersion < MIN_SAVE_FORMAT_VERSION ||
    formatVersion > MAX_SAVE_FORMAT_VERSION
  ) {
    return {
      slot,
      state: "occupied-incompatible",
      formatVersion,
      message: `Unsupported save format ${formatVersion}`,
    };
  }
  return {
    slot,
    state: "occupied-valid",
    formatVersion,
    json: raw,
  };
}

export function hydrateStoredSlots(
  store: SaveStore,
  slotCount: number,
  seed: (slot: number, json: string) => void,
): SaveSlotState[] {
  const states: SaveSlotState[] = [];
  for (let slot = 0; slot < slotCount; slot++) {
    let state: SaveSlotState;
    try {
      state = classifyStoredSlot(slot, store.loadSlot(slot));
    } catch (error) {
      state = {
        slot,
        state: "read-failed",
        message: error instanceof Error ? error.message : String(error),
      };
    }
    states.push(state);
    if (state.state === "occupied-valid") {
      seed(slot, state.json);
    }
  }
  return states;
}
import type { SaveStore } from "./saveStore";
