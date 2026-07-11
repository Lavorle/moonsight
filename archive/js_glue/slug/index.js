/**
 * MoonSight Slug-inspired outline text pipeline (JS side).
 *
 * Credits: Slug algorithm by Eric Lengyel — reference shaders under
 * third_party/slug/ (MIT / Apache-2.0). Patent dedicated to the public domain.
 * https://github.com/EricLengyel/Slug
 *
 * Phase 1: parse TrueType outlines → CPU multi-sample winding raster → atlas.
 * Full band-texture GPU path can replace rasterizeBeziers later using the
 * reference HLSL as a guide for WGSL.
 */

import { parseTrueType, contoursToBeziers } from "./ttf.js";
import { rasterizeBeziers } from "./raster.js";

/** @type {ReturnType<typeof parseTrueType> | null} */
let font = null;
/** @type {Promise<void> | null} */
let loading = null;

/**
 * @param {string} url
 */
export async function loadFont(url) {
  if (font) return;
  if (loading) return loading;
  loading = (async () => {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`font load failed: ${url} (${res.status})`);
    const buf = await res.arrayBuffer();
    font = parseTrueType(buf);
    console.info(
      "[slug] loaded font",
      url,
      "upem",
      font.unitsPerEm,
      "ascent",
      font.ascent,
    );
  })();
  try {
    await loading;
  } catch (e) {
    loading = null;
    throw e;
  }
}

export function hasFont() {
  return !!font;
}

/**
 * Rasterize one codepoint into a straight-alpha white RGBA buffer.
 * @param {number} codepoint
 * @param {number} pixelW
 * @param {number} pixelH
 * @returns {Uint8ClampedArray | null}
 */
export function rasterizeCodepoint(codepoint, pixelW, pixelH) {
  if (!font) return null;
  const g = font.glyphForCodepoint(codepoint);
  if (!g || !g.contours.length) {
    // space / empty — fully transparent
    return new Uint8ClampedArray(Math.max(1, pixelW) * Math.max(1, pixelH) * 4);
  }
  const curves = contoursToBeziers(g.contours);
  return rasterizeBeziers(curves, font.unitsPerEm, pixelW, pixelH, 1);
}

/**
 * Advance width in pixels for layout (optional host-side use).
 * @param {number} codepoint
 * @param {number} fontSizePx
 */
export function advancePx(codepoint, fontSizePx) {
  if (!font) return fontSizePx * 0.55;
  const adv = font.advanceOf(codepoint);
  return (adv / font.unitsPerEm) * fontSizePx;
}
