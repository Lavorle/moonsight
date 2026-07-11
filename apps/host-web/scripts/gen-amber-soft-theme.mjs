/**
 * Generate Amber Soft theme PNGs (rounded-rect panels) into public/themes/amber_soft/.
 *
 * Zero npm deps — uses Node built-in zlib only.
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

/** Panel sizes (logical UI proportions for 9-slice-friendly fills). */
const SIZES = {
  "dialogue_box.png": { w: 64, h: 48, r: 12 },
  "nameplate.png": { w: 48, h: 24, r: 8 },
  "choice_row.png": { w: 64, h: 28, r: 8 },
  "choice_row_focus.png": { w: 64, h: 28, r: 8 },
  "choice_row_hover.png": { w: 64, h: 28, r: 8 },
  "button.png": { w: 48, h: 28, r: 8 },
  "button_focus.png": { w: 48, h: 28, r: 8 },
  "button_hover.png": { w: 48, h: 28, r: 8 },
  "menu_dim.png": { w: 16, h: 16, r: 0 },
  "slider_track.png": { w: 64, h: 12, r: 6 },
  "slider_fill.png": { w: 64, h: 12, r: 6 },
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

/** Minimal RGBA8 PNG encoder (filter none + zlib). */
function encodePng(width, height, rgba) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    const rowStart = y * (stride + 1);
    raw[rowStart] = 0; // filter: none
    rgba.copy(raw, rowStart + 1, y * stride, y * stride + stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  return Buffer.concat([
    sig,
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(raw)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function distSq(px, py, cx, cy) {
  const dx = px - cx;
  const dy = py - cy;
  return dx * dx + dy * dy;
}

/** Soft rounded-rect fill with slight edge AA. */
function drawRoundedRect(w, h, r, rgba) {
  const out = Buffer.alloc(w * h * 4);
  const [R, G, B, A] = rgba;
  const rr = Math.max(0, Math.min(r, Math.floor(Math.min(w, h) / 2)));
  const r2 = rr * rr;
  const rOuter = (rr + 0.5) * (rr + 0.5);
  const rInner = Math.max(0, (rr - 0.5) * (rr - 0.5));

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let cover = 1;
      if (rr > 0) {
        let cx = x;
        let cy = y;
        // Map to nearest corner center if in corner region
        const inLeft = x < rr;
        const inRight = x >= w - rr;
        const inTop = y < rr;
        const inBottom = y >= h - rr;
        if ((inLeft || inRight) && (inTop || inBottom)) {
          cx = inLeft ? rr : w - 1 - rr;
          cy = inTop ? rr : h - 1 - rr;
          const d2 = distSq(x + 0.5, y + 0.5, cx + 0.5, cy + 0.5);
          if (d2 > rOuter) cover = 0;
          else if (d2 > rInner) {
            const d = Math.sqrt(d2);
            cover = Math.max(0, Math.min(1, rr + 0.5 - d));
          }
        }
      }
      const i = (y * w + x) * 4;
      if (cover <= 0) {
        out[i] = 0;
        out[i + 1] = 0;
        out[i + 2] = 0;
        out[i + 3] = 0;
      } else {
        out[i] = R;
        out[i + 1] = G;
        out[i + 2] = B;
        out[i + 3] = Math.round(A * cover);
      }
    }
  }
  return out;
}

function main() {
  mkdirSync(OUT_DIR, { recursive: true });
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
  const solids = manifest.fallback_solids;
  const roles = manifest.roles;

  let n = 0;
  for (const [role, spec] of Object.entries(roles)) {
    const file = spec.file;
    if (!file) continue;
    const rgba = solids[role];
    if (!rgba) {
      console.warn(`skip ${role}: no fallback solid`);
      continue;
    }
    const size = SIZES[file] || { w: 32, h: 32, r: 6 };
    const rgbaBuf = drawRoundedRect(size.w, size.h, size.r, rgba);
    const png = encodePng(size.w, size.h, rgbaBuf);
    writeFileSync(join(OUT_DIR, file), png);
    console.log(`wrote ${file} (${size.w}x${size.h}) for ${role}`);
    n++;
  }
  console.log(`Amber Soft theme: ${n} PNGs → ${OUT_DIR}`);
}

main();
