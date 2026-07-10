/**
 * Outline coverage rasterizer for quadratic Bézier glyphs.
 *
 * Inspired by the Slug algorithm (Eric Lengyel) — ray / winding accumulation
 * for coverage. Reference shaders: third_party/slug/ (MIT).
 *
 * Phase 1 uses a CPU multi-sample winding raster into an RGBA atlas cell.
 * This avoids the full band-texture pipeline while still drawing from
 * outline control points (not a system bitmap fillText).
 */

/**
 * @param {Array<{p0:[number,number], p1:[number,number], p2:[number,number]}>} curves
 * font-unit y-up
 * @param {number} unitsPerEm
 * @param {number} pixelW
 * @param {number} pixelH
 * @param {number} [pad]
 * @returns {Uint8ClampedArray} straight-alpha white coverage, length w*h*4
 */
export function rasterizeBeziers(curves, unitsPerEm, pixelW, pixelH, pad = 1) {
  const w = Math.max(1, pixelW | 0);
  const h = Math.max(1, pixelH | 0);
  const out = new Uint8ClampedArray(w * h * 4);
  if (!curves.length || unitsPerEm <= 0) return out;

  // Fit glyph bounds into the cell with padding (y-up font → y-down pixels).
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const c of curves) {
    for (const p of [c.p0, c.p1, c.p2]) {
      if (p[0] < minX) minX = p[0];
      if (p[1] < minY) minY = p[1];
      if (p[0] > maxX) maxX = p[0];
      if (p[1] > maxY) maxY = p[1];
    }
  }
  if (!Number.isFinite(minX)) return out;
  const gw = Math.max(1, maxX - minX);
  const gh = Math.max(1, maxY - minY);
  const sx = (w - pad * 2) / gw;
  const sy = (h - pad * 2) / gh;
  const scale = Math.min(sx, sy);
  const ox = pad - minX * scale;
  // Flip Y: font y-up → canvas y-down, fit into [pad, h-pad]
  const oy = h - pad + minY * scale;

  /** @type {Array<{p0:[number,number], p1:[number,number], p2:[number,number]}>} */
  const segs = curves.map((c) => ({
    p0: [ox + c.p0[0] * scale, oy - c.p0[1] * scale],
    p1: [ox + c.p1[0] * scale, oy - c.p1[1] * scale],
    p2: [ox + c.p2[0] * scale, oy - c.p2[1] * scale],
  }));

  // 4×4 stratified samples for coverage
  const offs = [0.125, 0.375, 0.625, 0.875];
  for (let py = 0; py < h; py++) {
    for (let px = 0; px < w; px++) {
      let cover = 0;
      for (const oyS of offs) {
        for (const oxS of offs) {
          const x = px + oxS;
          const y = py + oyS;
          if (windingEvenOdd(segs, x, y)) cover++;
        }
      }
      const a = Math.round((cover / 16) * 255);
      if (a <= 0) continue;
      const i = (py * w + px) * 4;
      out[i] = 255;
      out[i + 1] = 255;
      out[i + 2] = 255;
      out[i + 3] = a;
    }
  }
  return out;
}

/**
 * Non-zero winding test for quadratic segments (scanline horizontal ray to +∞).
 * Uses root-code style eligibility similar to Slug for y-crossings.
 *
 * @param {Array<{p0:[number,number], p1:[number,number], p2:[number,number]}>} segs
 * @param {number} x
 * @param {number} y
 */
function windingEvenOdd(segs, x, y) {
  // Use even-odd for robustness with simplified composites.
  let crossings = 0;
  for (const s of segs) {
    crossings += horizCrossings(s.p0, s.p1, s.p2, x, y);
  }
  return (crossings & 1) === 1;
}

/**
 * Count +x ray crossings of quadratic Bézier at sample (x,y).
 * @param {[number,number]} p0
 * @param {[number,number]} p1
 * @param {[number,number]} p2
 * @param {number} x
 * @param {number} y
 */
function horizCrossings(p0, p1, p2, x, y) {
  // Translate so sample is origin
  const y0 = p0[1] - y;
  const y1 = p1[1] - y;
  const y2 = p2[1] - y;
  const x0 = p0[0] - x;
  const x1 = p1[0] - x;
  const x2 = p2[0] - x;

  // Degenerate flat horizontal: skip (Slug tip)
  if (Math.abs(y0) < 1e-8 && Math.abs(y1) < 1e-8 && Math.abs(y2) < 1e-8) {
    return 0;
  }

  // Quadratic: y(t) = (1-t)^2 y0 + 2t(1-t) y1 + t^2 y2 = 0
  // a t^2 + b t + c = 0 with
  const a = y0 - 2 * y1 + y2;
  const b = 2 * (y1 - y0);
  const c = y0;

  /** @type {number[]} */
  const ts = [];
  if (Math.abs(a) < 1e-8) {
    // Linear
    if (Math.abs(b) < 1e-8) return 0;
    const t = -c / b;
    if (t >= 0 && t <= 1) ts.push(t);
  } else {
    const disc = b * b - 4 * a * c;
    if (disc < 0) return 0;
    const s = Math.sqrt(disc);
    const t1 = (-b - s) / (2 * a);
    const t2 = (-b + s) / (2 * a);
    if (t1 >= 0 && t1 <= 1) ts.push(t1);
    if (t2 >= 0 && t2 <= 1 && Math.abs(t2 - t1) > 1e-8) ts.push(t2);
  }

  let n = 0;
  for (const t of ts) {
    const mt = 1 - t;
    const px = mt * mt * x0 + 2 * mt * t * x1 + t * t * x2;
    // Crossing to the right of sample
    if (px > 0) {
      // Direction: dy/dt at t for winding sign — even-odd only needs count
      n++;
    }
  }
  return n;
}
