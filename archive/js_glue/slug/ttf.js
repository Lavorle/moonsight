/**
 * Minimal TrueType (glyf) loader for quadratic outlines.
 * Enough for Latin / common Noto Sans glyphs used by the demo.
 *
 * Outline rasterization uses a winding-number approach inspired by the
 * Slug algorithm (Eric Lengyel, MIT — see third_party/slug/).
 */

/**
 * @param {ArrayBuffer} buf
 */
export function parseTrueType(buf) {
  const dv = new DataView(buf);
  const u16 = (o) => dv.getUint16(o, false);
  const i16 = (o) => dv.getInt16(o, false);
  const u32 = (o) => dv.getUint32(o, false);
  const i16s = (o) => dv.getInt16(o, false);

  const numTables = u16(4);
  /** @type {Record<string, {offset:number, length:number}>} */
  const tables = {};
  for (let i = 0; i < numTables; i++) {
    const o = 12 + i * 16;
    const tag = String.fromCharCode(
      dv.getUint8(o),
      dv.getUint8(o + 1),
      dv.getUint8(o + 2),
      dv.getUint8(o + 3),
    );
    tables[tag] = { offset: u32(o + 8), length: u32(o + 12) };
  }

  function need(tag) {
    const t = tables[tag];
    if (!t) throw new Error(`TTF missing table ${tag}`);
    return t;
  }

  const head = need("head");
  const unitsPerEm = u16(head.offset + 18);
  const indexToLocFormat = i16(head.offset + 50);

  const maxp = need("maxp");
  const numGlyphs = u16(maxp.offset + 4);

  const hhea = need("hhea");
  const numberOfHMetrics = u16(hhea.offset + 34);
  const ascent = i16(hhea.offset + 4);
  const descent = i16(hhea.offset + 6);

  const hmtx = need("hmtx");
  /** @type {number[]} */
  const advances = new Array(numGlyphs);
  /** @type {number[]} */
  const lsbs = new Array(numGlyphs);
  let ho = hmtx.offset;
  let lastAdv = 0;
  for (let i = 0; i < numberOfHMetrics; i++) {
    lastAdv = u16(ho);
    advances[i] = lastAdv;
    lsbs[i] = i16(ho + 2);
    ho += 4;
  }
  for (let i = numberOfHMetrics; i < numGlyphs; i++) {
    advances[i] = lastAdv;
    lsbs[i] = i16(ho);
    ho += 2;
  }

  const loca = need("loca");
  /** @type {number[]} */
  const locaOff = new Array(numGlyphs + 1);
  if (indexToLocFormat === 0) {
    for (let i = 0; i <= numGlyphs; i++) {
      locaOff[i] = u16(loca.offset + i * 2) * 2;
    }
  } else {
    for (let i = 0; i <= numGlyphs; i++) {
      locaOff[i] = u32(loca.offset + i * 4);
    }
  }

  const glyf = need("glyf");
  const cmap = need("cmap");
  const cmapToGlyph = parseCmap(dv, cmap.offset, cmap.length);

  /**
   * @param {number} glyphId
   * @returns {{contours: Array<Array<{x:number,y:number,on:boolean}>>, advance: number, lsb: number} | null}
   */
  function loadGlyph(glyphId) {
    if (glyphId < 0 || glyphId >= numGlyphs) return null;
    const start = locaOff[glyphId];
    const end = locaOff[glyphId + 1];
    if (end <= start) {
      return { contours: [], advance: advances[glyphId], lsb: lsbs[glyphId] };
    }
    const base = glyf.offset + start;
    const numberOfContours = i16(base);
    if (numberOfContours < 0) {
      // Composite — expand simple components only (enough for many Latin accents).
      return expandComposite(base, glyphId);
    }
    return {
      contours: parseSimpleGlyph(dv, base, numberOfContours),
      advance: advances[glyphId],
      lsb: lsbs[glyphId],
    };
  }

  function expandComposite(base, glyphId) {
    /** @type {Array<Array<{x:number,y:number,on:boolean}>>} */
    const contours = [];
    let o = base + 10;
    // eslint-disable-next-line no-constant-condition
    while (true) {
      const flags = u16(o);
      o += 2;
      const gId = u16(o);
      o += 2;
      let arg1;
      let arg2;
      if (flags & 1) {
        arg1 = i16(o);
        arg2 = i16(o + 2);
        o += 4;
      } else {
        arg1 = dv.getInt8(o);
        arg2 = dv.getInt8(o + 1);
        o += 2;
      }
      let dx = 0;
      let dy = 0;
      if (flags & 2) {
        dx = arg1;
        dy = arg2;
      }
      // Skip scale fields
      if (flags & 8) o += 2;
      else if (flags & 64) o += 4;
      else if (flags & 128) o += 8;

      const sub = loadGlyph(gId);
      if (sub) {
        for (const c of sub.contours) {
          contours.push(
            c.map((p) => ({ x: p.x + dx, y: p.y + dy, on: p.on })),
          );
        }
      }
      if (!(flags & 32)) break;
    }
    return { contours, advance: advances[glyphId], lsb: lsbs[glyphId] };
  }

  return {
    unitsPerEm,
    ascent,
    descent,
    /**
     * @param {number} codepoint
     */
    glyphForCodepoint(codepoint) {
      const gId = cmapToGlyph.get(codepoint) ?? 0;
      return loadGlyph(gId);
    },
    /**
     * Advance width in font units.
     * @param {number} codepoint
     */
    advanceOf(codepoint) {
      const gId = cmapToGlyph.get(codepoint) ?? 0;
      return advances[gId] ?? unitsPerEm;
    },
  };
}

/**
 * @param {DataView} dv
 * @param {number} cmapOffset
 * @param {number} _len
 */
function parseCmap(dv, cmapOffset, _len) {
  const u16 = (o) => dv.getUint16(o, false);
  const u32 = (o) => dv.getUint32(o, false);
  const numTables = u16(cmapOffset + 2);
  let best = null;
  for (let i = 0; i < numTables; i++) {
    const o = cmapOffset + 4 + i * 8;
    const platformID = u16(o);
    const encodingID = u16(o + 2);
    const offset = u32(o + 4);
    // Prefer Windows Unicode BMP (3,1) or full (3,10) or Unicode (0,*)
    if (
      (platformID === 3 && (encodingID === 1 || encodingID === 10)) ||
      platformID === 0
    ) {
      best = cmapOffset + offset;
      if (platformID === 3 && encodingID === 10) break;
    }
  }
  /** @type {Map<number, number>} */
  const map = new Map();
  if (best == null) return map;
  const format = u16(best);
  if (format === 4) {
    const segCount = u16(best + 6) / 2;
    const endCount = best + 14;
    const startCount = endCount + 2 + segCount * 2;
    const idDelta = startCount + segCount * 2;
    const idRangeOffset = idDelta + segCount * 2;
    for (let i = 0; i < segCount; i++) {
      const end = u16(endCount + i * 2);
      const start = u16(startCount + i * 2);
      const delta = dv.getInt16(idDelta + i * 2, false);
      const rangeOff = u16(idRangeOffset + i * 2);
      for (let c = start; c <= end; c++) {
        let g;
        if (rangeOff === 0) {
          g = (c + delta) & 0xffff;
        } else {
          const glyphOffset =
            idRangeOffset + i * 2 + rangeOff + (c - start) * 2;
          g = u16(glyphOffset);
          if (g !== 0) g = (g + delta) & 0xffff;
        }
        if (g) map.set(c, g);
      }
    }
  } else if (format === 12) {
    const nGroups = u32(best + 12);
    let o = best + 16;
    for (let i = 0; i < nGroups; i++) {
      const start = u32(o);
      const end = u32(o + 4);
      const startGlyph = u32(o + 8);
      o += 12;
      for (let c = start; c <= end; c++) {
        map.set(c, startGlyph + (c - start));
      }
    }
  }
  return map;
}

/**
 * @param {DataView} dv
 * @param {number} base
 * @param {number} numberOfContours
 */
function parseSimpleGlyph(dv, base, numberOfContours) {
  const u16 = (o) => dv.getUint16(o, false);
  const i16 = (o) => dv.getInt16(o, false);
  /** @type {number[]} */
  const endPts = [];
  for (let i = 0; i < numberOfContours; i++) {
    endPts.push(u16(base + 10 + i * 2));
  }
  const nPoints = endPts[endPts.length - 1] + 1;
  let o = base + 10 + numberOfContours * 2;
  const instructionLength = u16(o);
  o += 2 + instructionLength;

  /** @type {number[]} */
  const flags = [];
  for (let i = 0; i < nPoints; ) {
    const f = dv.getUint8(o++);
    flags.push(f);
    i++;
    if (f & 8) {
      const rep = dv.getUint8(o++);
      for (let r = 0; r < rep; r++) {
        flags.push(f);
        i++;
      }
    }
  }

  /** @type {number[]} */
  const xs = new Array(nPoints);
  let x = 0;
  for (let i = 0; i < nPoints; i++) {
    const f = flags[i];
    if (f & 2) {
      const dx = dv.getUint8(o++);
      x += f & 16 ? dx : -dx;
    } else if (!(f & 16)) {
      x += i16(o);
      o += 2;
    }
    xs[i] = x;
  }

  /** @type {number[]} */
  const ys = new Array(nPoints);
  let y = 0;
  for (let i = 0; i < nPoints; i++) {
    const f = flags[i];
    if (f & 4) {
      const dy = dv.getUint8(o++);
      y += f & 32 ? dy : -dy;
    } else if (!(f & 32)) {
      y += i16(o);
      o += 2;
    }
    ys[i] = y;
  }

  /** @type {Array<Array<{x:number,y:number,on:boolean}>>} */
  const contours = [];
  let start = 0;
  for (const end of endPts) {
    /** @type {Array<{x:number,y:number,on:boolean}>} */
    const pts = [];
    for (let i = start; i <= end; i++) {
      pts.push({ x: xs[i], y: ys[i], on: !!(flags[i] & 1) });
    }
    contours.push(pts);
    start = end + 1;
  }
  return contours;
}

/**
 * Convert TrueType point contours to quadratic Bezier segments
 * `{p0, p1, p2}` in font units (y up).
 *
 * @param {Array<Array<{x:number,y:number,on:boolean}>>} contours
 * @returns {Array<{p0:[number,number], p1:[number,number], p2:[number,number]}>}
 */
export function contoursToBeziers(contours) {
  /** @type {Array<{p0:[number,number], p1:[number,number], p2:[number,number]}>} */
  const curves = [];
  for (const raw of contours) {
    if (raw.length < 2) continue;
    // Normalize: ensure starts on-curve (TTF allows off-curve start).
    const pts = raw.slice();
    if (!pts[0].on) {
      const last = pts[pts.length - 1];
      if (last.on) pts.unshift(last);
      else {
        pts.unshift({
          x: (pts[0].x + last.x) / 2,
          y: (pts[0].y + last.y) / 2,
          on: true,
        });
      }
    }
    // Close contour
    pts.push(pts[0]);

    let i = 0;
    while (i < pts.length - 1) {
      const a = pts[i];
      const b = pts[i + 1];
      if (b.on) {
        // line as quadratic with duplicated end (Slug tip)
        curves.push({
          p0: [a.x, a.y],
          p1: [b.x, b.y],
          p2: [b.x, b.y],
        });
        i += 1;
      } else {
        const c = pts[i + 2] || pts[0];
        let end;
        if (c.on) {
          end = c;
          i += 2;
        } else {
          end = { x: (b.x + c.x) / 2, y: (b.y + c.y) / 2, on: true };
          // insert implied on-curve for next iteration
          pts.splice(i + 2, 0, end);
          i += 2;
        }
        curves.push({
          p0: [a.x, a.y],
          p1: [b.x, b.y],
          p2: [end.x, end.y],
        });
      }
    }
  }
  return curves;
}
