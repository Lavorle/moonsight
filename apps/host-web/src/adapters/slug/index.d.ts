/** Thin ambient types for slug/index.js */

export function loadFont(url: string): Promise<void>;
export function hasFont(): boolean;
export function rasterizeGlyph(
  ch: string,
  size: number,
  w: number,
  h: number,
): ImageData | null;
