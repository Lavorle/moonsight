/**
 * Curve / band packing for the Slug algorithm.
 *
 * Adapted from https://github.com/diffusionstudio/slug-webgpu (MIT)
 * which ports Eric Lengyel's Slug algorithm to WebGPU.
 */

const TEX_WIDTH = 4096;
const LINE_EPSILON = 0.125;

/**
 * @typedef {{ p0x:number, p0y:number, p1x:number, p1y:number, p2x:number, p2y:number }} QuadCurve
 * @typedef {{ xMin:number, yMin:number, xMax:number, yMax:number }} Bounds
 */

/**
 * Convert line to quadratic (Slug tip: slight bow for diagonals).
 * @returns {QuadCurve}
 */
export function lineToQuadratic(x0, y0, x1, y1) {
  const mx = (x0 + x1) / 2;
  const my = (y0 + y1) / 2;
  const dx = x1 - x0;
  const dy = y1 - y0;
  if (Math.abs(dx) > 0.1 && Math.abs(dy) > 0.1) {
    const length = Math.hypot(dx, dy);
    if (length > 0) {
      const invLength = LINE_EPSILON / length;
      return {
        p0x: x0,
        p0y: y0,
        p1x: mx - dy * invLength,
        p1y: my + dx * invLength,
        p2x: x1,
        p2y: y1,
      };
    }
  }
  return { p0x: x0, p0y: y0, p1x: mx, p1y: my, p2x: x1, p2y: y1 };
}

/**
 * TrueType-style contours (on/off points, y-up font units) → quadratic curves.
 * @param {Array<Array<{x:number,y:number,on:boolean}>>} contours
 * @returns {{ curves: QuadCurve[], bounds: Bounds } | null}
 */
export function contoursToSlugCurves(contours) {
  /** @type {QuadCurve[]} */
  const curves = [];
  let xMin = Infinity;
  let yMin = Infinity;
  let xMax = -Infinity;
  let yMax = -Infinity;

  function touch(x, y) {
    if (x < xMin) xMin = x;
    if (y < yMin) yMin = y;
    if (x > xMax) xMax = x;
    if (y > yMax) yMax = y;
  }

  for (const raw of contours) {
    if (raw.length < 2) continue;
    const pts = raw.slice();
    if (!pts[0].on) {
      const last = pts[pts.length - 1];
      if (last.on) pts.unshift({ ...last });
      else {
        pts.unshift({
          x: (pts[0].x + last.x) / 2,
          y: (pts[0].y + last.y) / 2,
          on: true,
        });
      }
    }
    pts.push(pts[0]);

    let i = 0;
    while (i < pts.length - 1) {
      const a = pts[i];
      const b = pts[i + 1];
      if (b.on) {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        if (Math.abs(dx) > 0.05 || Math.abs(dy) > 0.05) {
          const c = lineToQuadratic(a.x, a.y, b.x, b.y);
          curves.push(c);
          touch(a.x, a.y);
          touch(b.x, b.y);
        }
        i += 1;
      } else {
        const c = pts[i + 2] || pts[0];
        let end;
        if (c.on) {
          end = c;
          i += 2;
        } else {
          end = { x: (b.x + c.x) / 2, y: (b.y + c.y) / 2, on: true };
          pts.splice(i + 2, 0, end);
          i += 2;
        }
        curves.push({
          p0x: a.x,
          p0y: a.y,
          p1x: b.x,
          p1y: b.y,
          p2x: end.x,
          p2y: end.y,
        });
        touch(a.x, a.y);
        touch(b.x, b.y);
        touch(end.x, end.y);
      }
    }
  }

  if (!curves.length || !Number.isFinite(xMin)) return null;
  // Pad bounds slightly so band math is stable
  const pad = 1;
  return {
    curves,
    bounds: {
      xMin: xMin - pad,
      yMin: yMin - pad,
      xMax: xMax + pad,
      yMax: yMax + pad,
    },
  };
}

/**
 * @param {QuadCurve[]} curves
 * @param {Bounds} bounds
 * @param {number} [bandCount]
 */
export function buildBands(curves, bounds, bandCount = 8) {
  const { xMin, yMin, xMax, yMax } = bounds;
  const width = xMax - xMin;
  const height = yMax - yMin;
  const hBands = Array.from({ length: bandCount }, () => ({ curveIndices: [] }));
  const vBands = Array.from({ length: bandCount }, () => ({ curveIndices: [] }));

  for (let ci = 0; ci < curves.length; ci++) {
    const c = curves[ci];
    const cyMin = Math.min(c.p0y, c.p1y, c.p2y);
    const cyMax = Math.max(c.p0y, c.p1y, c.p2y);
    const cxMin = Math.min(c.p0x, c.p1x, c.p2x);
    const cxMax = Math.max(c.p0x, c.p1x, c.p2x);

    // Skip pure horizontal from h-bands / pure vertical from v-bands (Slug tip)
    const pureH = Math.abs(cyMax - cyMin) < 1e-4;
    const pureV = Math.abs(cxMax - cxMin) < 1e-4;

    if (height > 0 && !pureH) {
      const b0 = Math.max(0, Math.floor(((cyMin - yMin) / height) * bandCount));
      const b1 = Math.min(
        bandCount - 1,
        Math.floor(((cyMax - yMin) / height) * bandCount),
      );
      for (let b = b0; b <= b1; b++) hBands[b].curveIndices.push(ci);
    }
    if (width > 0 && !pureV) {
      const b0 = Math.max(0, Math.floor(((cxMin - xMin) / width) * bandCount));
      const b1 = Math.min(
        bandCount - 1,
        Math.floor(((cxMax - xMin) / width) * bandCount),
      );
      for (let b = b0; b <= b1; b++) vBands[b].curveIndices.push(ci);
    }
  }
  return { hBands, vBands, hBandCount: bandCount, vBandCount: bandCount };
}

/**
 * Pack one or more glyphs into curve + band textures.
 * @param {Array<{ curves: QuadCurve[], bounds: Bounds, bands: ReturnType<typeof buildBands> }>} glyphs
 */
export function packGlyphData(glyphs) {
  let totalCurveTexels = 0;
  for (const g of glyphs) totalCurveTexels += g.curves.length * 2;
  const curveTexHeight = Math.max(1, Math.ceil(totalCurveTexels / TEX_WIDTH));
  const curveTexData = new Float32Array(TEX_WIDTH * curveTexHeight * 4);

  let curveTexelIdx = 0;
  const glyphCurveStarts = [];
  for (const g of glyphs) {
    glyphCurveStarts.push(curveTexelIdx);
    for (const c of g.curves) {
      const i0 = curveTexelIdx;
      const x0 = i0 % TEX_WIDTH;
      const y0 = (i0 / TEX_WIDTH) | 0;
      const off0 = (y0 * TEX_WIDTH + x0) * 4;
      curveTexData[off0] = c.p0x;
      curveTexData[off0 + 1] = c.p0y;
      curveTexData[off0 + 2] = c.p1x;
      curveTexData[off0 + 3] = c.p1y;

      const i1 = curveTexelIdx + 1;
      const x1 = i1 % TEX_WIDTH;
      const y1 = (i1 / TEX_WIDTH) | 0;
      const off1 = (y1 * TEX_WIDTH + x1) * 4;
      curveTexData[off1] = c.p2x;
      curveTexData[off1 + 1] = c.p2y;
      curveTexelIdx += 2;
    }
  }

  let totalBandTexels = 0;
  for (const g of glyphs) {
    const headerCount = g.bands.hBandCount + g.bands.vBandCount;
    const padded = TEX_WIDTH - (totalBandTexels % TEX_WIDTH);
    if (padded < headerCount && padded < TEX_WIDTH) totalBandTexels += padded;
    totalBandTexels += headerCount;
    for (const band of [...g.bands.hBands, ...g.bands.vBands]) {
      totalBandTexels += band.curveIndices.length;
    }
  }

  const bandTexHeight = Math.max(1, Math.ceil(totalBandTexels / TEX_WIDTH));
  const bandTexData = new Uint32Array(TEX_WIDTH * bandTexHeight * 4);
  let bandTexelIdx = 0;
  const glyphBandInfo = [];

  for (let gi = 0; gi < glyphs.length; gi++) {
    const g = glyphs[gi];
    const hBandCount = g.bands.hBandCount;
    const vBandCount = g.bands.vBandCount;
    const headerCount = hBandCount + vBandCount;

    const curX = bandTexelIdx % TEX_WIDTH;
    if (curX + headerCount > TEX_WIDTH) {
      bandTexelIdx = (((bandTexelIdx / TEX_WIDTH) | 0) + 1) * TEX_WIDTH;
    }

    const glyphLocX = bandTexelIdx % TEX_WIDTH;
    const glyphLocY = (bandTexelIdx / TEX_WIDTH) | 0;
    glyphBandInfo.push({ glyphLocX, glyphLocY });

    const glyphStart = bandTexelIdx;
    const glyphCurveStart = glyphCurveStarts[gi];

    const sortedHBands = g.bands.hBands.map((band) => ({
      curveIndices: [...band.curveIndices].sort((a, b) => {
        const ca = g.curves[a];
        const cb = g.curves[b];
        return (
          Math.max(cb.p0x, cb.p1x, cb.p2x) - Math.max(ca.p0x, ca.p1x, ca.p2x)
        );
      }),
    }));
    const sortedVBands = g.bands.vBands.map((band) => ({
      curveIndices: [...band.curveIndices].sort((a, b) => {
        const ca = g.curves[a];
        const cb = g.curves[b];
        return (
          Math.max(cb.p0y, cb.p1y, cb.p2y) - Math.max(ca.p0y, ca.p1y, ca.p2y)
        );
      }),
    }));
    const allBands = [...sortedHBands, ...sortedVBands];

    let curveListOffset = headerCount;
    const bandOffsets = [];
    for (const band of allBands) {
      bandOffsets.push(curveListOffset);
      curveListOffset += band.curveIndices.length;
    }

    for (let i = 0; i < allBands.length; i++) {
      const tl = glyphStart + i;
      const tx = tl % TEX_WIDTH;
      const ty = (tl / TEX_WIDTH) | 0;
      const di = (ty * TEX_WIDTH + tx) * 4;
      bandTexData[di] = allBands[i].curveIndices.length;
      bandTexData[di + 1] = bandOffsets[i];
    }

    for (let i = 0; i < allBands.length; i++) {
      const band = allBands[i];
      const listStart = glyphStart + bandOffsets[i];
      for (let j = 0; j < band.curveIndices.length; j++) {
        const ci = band.curveIndices[j];
        const curveTexel = glyphCurveStart + ci * 2;
        const cTexX = curveTexel % TEX_WIDTH;
        const cTexY = (curveTexel / TEX_WIDTH) | 0;
        const tl = listStart + j;
        const tx = tl % TEX_WIDTH;
        const ty = (tl / TEX_WIDTH) | 0;
        const di = (ty * TEX_WIDTH + tx) * 4;
        bandTexData[di] = cTexX;
        bandTexData[di + 1] = cTexY;
      }
    }
    bandTexelIdx = glyphStart + curveListOffset;
  }

  return {
    curveTexData,
    bandTexData,
    curveTexHeight,
    bandTexHeight,
    glyphBandInfo,
    TEX_WIDTH,
  };
}

export { TEX_WIDTH };
