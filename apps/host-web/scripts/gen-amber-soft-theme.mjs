/**
 * Generate Amber Soft theme PNGs into public/themes/amber_soft/.
 *
 * Larger tiles with soft gradients, top sheen, and hairline borders so
 * stretched UI panels look intentional (not flat 1×1 solids).
 *
 * Zero npm deps — Node built-in zlib only.
 *
 * Usage:
 *   node apps/host-web/scripts/gen-amber-soft-theme.mjs
 */
import { deflateSync } from "node:zlib";
import { mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, "../public/themes/amber_soft");
const MANIFEST_PATH = join(OUT_DIR, "theme.json");

/**
 * Per-file draw recipe. Larger than layout rects so bilinear stretch stays soft.
 * @type {Record<string, { w: number, h: number, r: number, style: string }>}
 */
const SPECS = {
  "dialogue_box.png": { w: 384, h: 160, r: 28, style: "panel_deep" },
  "nameplate.png": { w: 256, h: 64, r: 18, style: "nameplate" },
  "choice_row.png": { w: 320, h: 64, r: 16, style: "row_idle" },
  "choice_row_focus.png": { w: 320, h: 64, r: 16, style: "row_focus" },
  "choice_row_hover.png": { w: 320, h: 64, r: 16, style: "row_hover" },
  "button.png": { w: 256, h: 72, r: 18, style: "btn_idle" },
  "button_focus.png": { w: 256, h: 72, r: 18, style: "btn_focus" },
  "button_hover.png": { w: 256, h: 72, r: 18, style: "btn_hover" },
  "menu_dim.png": { w: 32, h: 32, r: 0, style: "dim" },
  "slider_track.png": { w: 256, h: 28, r: 14, style: "slider_track" },
  "slider_fill.png": { w: 256, h: 28, r: 14, style: "slider_fill" },
};

// Amber Soft palette (sRGB).
const C = {
  ink: [16, 12, 18],
  deep: [22, 16, 20],
  plate: [48, 36, 40],
  row: [40, 30, 36],
  hover: [90, 56, 42],
  focus: [120, 72, 48],
  amber: [212, 160, 106],
  amberHot: [232, 186, 130],
  fill: [200, 140, 90],
  track: [36, 28, 32],
  hair: [200, 150, 110],
  rose: [56, 36, 48],
};

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
  }
  return (c ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBuf = Buffer.from(type, "ascii");
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const crcBuf = Buffer.concat([typeBuf, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(crcBuf), 0);
  return Buffer.concat([len, typeBuf, data, crc]);
}

function encodePng(width, height, rgba) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    const rowStart = y * (stride + 1);
    raw[rowStart] = 0;
    rgba.copy(raw, rowStart + 1, y * stride, y * stride + stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  return Buffer.concat([
    sig,
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(raw, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function clamp01(t) {
  return t < 0 ? 0 : t > 1 ? 1 : t;
}

function mix(a, b, t) {
  const u = clamp01(t);
  return [
    Math.round(a[0] + (b[0] - a[0]) * u),
    Math.round(a[1] + (b[1] - a[1]) * u),
    Math.round(a[2] + (b[2] - a[2]) * u),
  ];
}

function withAlpha(rgb, a) {
  return [rgb[0], rgb[1], rgb[2], Math.round(clamp01(a) * 255)];
}

/** Signed distance-ish cover for rounded rect (0 outside → 1 inside). */
function rrCover(px, py, w, h, r) {
  const rr = Math.max(0, Math.min(r, Math.floor(Math.min(w, h) / 2)));
  const x = px + 0.5;
  const y = py + 0.5;
  const cx = clamp01((x - rr) / Math.max(1, w - 2 * rr)) * Math.max(0, w - 2 * rr) + rr;
  const cy = clamp01((y - rr) / Math.max(1, h - 2 * rr)) * Math.max(0, h - 2 * rr) + rr;
  // Use corner SDF only in corner regions.
  const inCorner =
    (x < rr || x >= w - rr) && (y < rr || y >= h - rr);
  if (!inCorner || rr <= 0) {
    if (x < 0 || y < 0 || x >= w || y >= h) return 0;
    // Edge AA for sharp sides
    const dx = Math.min(x, w - x);
    const dy = Math.min(y, h - y);
    const d = Math.min(dx, dy);
    if (d >= 1) return 1;
    if (d <= 0) return 0;
    return d;
  }
  const cornerCx = x < rr ? rr : w - rr;
  const cornerCy = y < rr ? rr : h - rr;
  const dist = Math.hypot(x - cornerCx, y - cornerCy);
  const outer = rr + 0.5;
  const inner = rr - 0.5;
  if (dist > outer) return 0;
  if (dist < inner) return 1;
  return outer - dist;
}

function setPx(buf, w, x, y, rgba) {
  if (x < 0 || y < 0 || x >= w) return;
  const i = (y * w + x) * 4;
  buf[i] = rgba[0];
  buf[i + 1] = rgba[1];
  buf[i + 2] = rgba[2];
  buf[i + 3] = rgba[3];
}

/**
 * Composite premultiplied-ish over opaque buffer: src over dst with src alpha.
 */
function over(dst, srcA, srcRgb) {
  const a = clamp01(srcA);
  if (a <= 0) return dst;
  if (a >= 1) return [...srcRgb, 255];
  const da = dst[3] / 255;
  const outA = a + da * (1 - a);
  if (outA <= 0) return [0, 0, 0, 0];
  const r = (srcRgb[0] * a + dst[0] * da * (1 - a)) / outA;
  const g = (srcRgb[1] * a + dst[1] * da * (1 - a)) / outA;
  const b = (srcRgb[2] * a + dst[2] * da * (1 - a)) / outA;
  return [Math.round(r), Math.round(g), Math.round(b), Math.round(outA * 255)];
}

function drawPanel(w, h, r, style) {
  const out = Buffer.alloc(w * h * 4);
  const ny = (y) => (h <= 1 ? 0 : y / (h - 1));

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const cover = rrCover(x, y, w, h, r);
      if (cover <= 0) {
        setPx(out, w, x, y, [0, 0, 0, 0]);
        continue;
      }

      const t = ny(y);
      let base;
      let alpha = 0.86;
      let borderBoost = 0;
      let sheen = 0;

      switch (style) {
        case "panel_deep": {
          // Dialogue / modal card: warm ink gradient + faint rose lift.
          base = mix(mix(C.ink, C.deep, 0.35), C.rose, t * 0.15);
          base = mix(base, C.plate, 0.08 + t * 0.12);
          alpha = 0.88;
          sheen = Math.max(0, 1 - t * 3.2) * 0.18;
          borderBoost = 0.55;
          break;
        }
        case "nameplate": {
          base = mix(C.plate, C.hover, 0.25 + t * 0.15);
          base = mix(base, C.amber, 0.08);
          alpha = 0.92;
          sheen = Math.max(0, 1 - t * 2.5) * 0.22;
          borderBoost = 0.7;
          break;
        }
        case "row_idle": {
          base = mix(C.row, C.deep, t * 0.35);
          alpha = 0.78;
          sheen = Math.max(0, 1 - t * 2.8) * 0.1;
          borderBoost = 0.35;
          break;
        }
        case "row_hover": {
          base = mix(C.hover, C.row, t * 0.25);
          alpha = 0.9;
          sheen = Math.max(0, 1 - t * 2.5) * 0.2;
          borderBoost = 0.55;
          break;
        }
        case "row_focus": {
          base = mix(C.focus, C.amber, 0.12 + (1 - t) * 0.1);
          alpha = 0.95;
          sheen = Math.max(0, 1 - t * 2.2) * 0.28;
          borderBoost = 0.85;
          break;
        }
        case "btn_idle": {
          base = mix(C.plate, C.row, t * 0.4);
          alpha = 0.9;
          sheen = Math.max(0, 1 - t * 2.6) * 0.16;
          borderBoost = 0.45;
          break;
        }
        case "btn_hover": {
          base = mix(C.hover, C.plate, t * 0.3);
          alpha = 0.94;
          sheen = Math.max(0, 1 - t * 2.3) * 0.24;
          borderBoost = 0.65;
          break;
        }
        case "btn_focus": {
          base = mix(C.focus, C.amber, 0.18 * (1 - t));
          alpha = 0.97;
          sheen = Math.max(0, 1 - t * 2.0) * 0.32;
          borderBoost = 0.95;
          break;
        }
        case "slider_track": {
          base = mix(C.track, C.ink, t * 0.35);
          alpha = 0.85;
          sheen = Math.max(0, 1 - t * 2.0) * 0.08;
          borderBoost = 0.3;
          break;
        }
        case "slider_fill": {
          base = mix(C.fill, C.amberHot, (1 - t) * 0.45);
          alpha = 0.96;
          sheen = Math.max(0, 1 - t * 1.8) * 0.35;
          borderBoost = 0.5;
          break;
        }
        case "dim": {
          base = C.ink;
          alpha = 0.55;
          borderBoost = 0;
          sheen = 0;
          break;
        }
        default: {
          base = C.plate;
          alpha = 0.9;
        }
      }

      // Vertical sheen (top light).
      if (sheen > 0) {
        base = mix(base, [255, 240, 220], sheen);
      }

      // Soft inner border / amber hairline near edge.
      const edge = edgeFactor(x, y, w, h, r);
      if (borderBoost > 0 && edge < 2.5) {
        const hairA = clamp01((2.5 - edge) / 2.5) * borderBoost * 0.55;
        base = mix(base, C.hair, hairA);
        if (style.includes("focus") || style === "nameplate") {
          base = mix(base, C.amber, hairA * 0.45);
        }
      }

      // Left amber accent for focus rows/buttons.
      if (style === "btn_focus" || style === "row_focus") {
        const accent = clamp01(1 - x / Math.max(1, w * 0.08));
        if (accent > 0) {
          base = mix(base, C.amberHot, accent * 0.55);
        }
      }

      const a = alpha * cover;
      setPx(out, w, x, y, withAlpha(base, a));
    }
  }
  return out;
}

/** Approximate distance to rounded-rect boundary (for border). */
function edgeFactor(px, py, w, h, r) {
  const x = px + 0.5;
  const y = py + 0.5;
  const rr = Math.max(0, Math.min(r, Math.floor(Math.min(w, h) / 2)));
  const dx = Math.min(x, w - x);
  const dy = Math.min(y, h - y);
  if ((x < rr || x >= w - rr) && (y < rr || y >= h - rr)) {
    const cx = x < rr ? rr : w - rr;
    const cy = y < rr ? rr : h - rr;
    return Math.abs(rr - Math.hypot(x - cx, y - cy));
  }
  return Math.min(dx, dy);
}

function main() {
  mkdirSync(OUT_DIR, { recursive: true });
  // Keep theme.json as source of truth for solids; only rewrite PNG bytes.
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
  const roles = manifest.roles;

  let n = 0;
  for (const [role, spec] of Object.entries(roles)) {
    const file = spec.file;
    if (!file) continue;
    const recipe = SPECS[file];
    if (!recipe) {
      console.warn(`skip ${file}: no SPECS entry`);
      continue;
    }
    const rgba = drawPanel(recipe.w, recipe.h, recipe.r, recipe.style);
    const png = encodePng(recipe.w, recipe.h, rgba);
    writeFileSync(join(OUT_DIR, file), png);
    console.log(`wrote ${file} ${recipe.w}x${recipe.h} (${recipe.style}) ← ${role}`);
    n++;
  }
  console.log(`Amber Soft theme: ${n} PNGs → ${OUT_DIR}`);
}

main();
