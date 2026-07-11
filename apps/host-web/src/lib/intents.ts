/**
 * Intent codes — must match docs/draw-list-pack.md and export_frame contract.
 * Do not invent new codes.
 */

export const INTENT_NONE = 0;
export const INTENT_ADVANCE = 1;
export const INTENT_SKIP = 2;
export const INTENT_OPEN_MENU = 3;
export const INTENT_TOGGLE_AUTO = 4;
export const INTENT_MENU_UP = 5;
export const INTENT_MENU_DOWN = 6;
export const INTENT_MENU_LEFT = 7;
export const INTENT_MENU_RIGHT = 8;
export const INTENT_OPEN_BACKLOG = 9;

/** Select(row) base: intent = 10 + row for row 0..8 (keys 1–9 / choice hit). */
export const INTENT_SELECT_BASE = 10;
