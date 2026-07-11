/**
 * Thin ambient types for webgpu_bridge.js (copied as-is from host_web/js_glue).
 */

export function init(canvas: HTMLCanvasElement): Promise<void>;
export function resize(w: number, h: number): void;
export function beginFrame(): void;
export function endFrame(): void;
export function drawSprites(
  sprites: Float32Array,
  resolveRes: (id: number | string) => string | number,
): void;
export function drawGlyphs(glyphs: Float32Array, mode?: string): void;
export function drawVeil(veil: number): void;
export function uploadPngUrl(id: string, url: string): Promise<void>;
export function registerSolid(id: string, rgba: number[]): void;
export function registerImage(id: string, url: string): Promise<void>;
export function rasterizeGlyphToAtlas(
  ch: string,
  size: number,
  atlasX: number,
  atlasY: number,
  atlasW: number,
  atlasH: number,
  atlasSize: number,
): boolean;
export function getDevice(): GPUDevice | null;
export function setSlugGpu(mod: unknown): void;
export function setOutlineRasterizer(mod: unknown): void;
export function setGlyphRasterMode(mode: string): void;
