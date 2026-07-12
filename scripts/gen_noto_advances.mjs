import fs from "fs";
import { parseTrueType } from "../apps/host-web/src/adapters/slug/ttf.js";

const fontPath = "apps/host-web/public/fonts/NotoSans-Regular.ttf";
const font = parseTrueType(fs.readFileSync(fontPath).buffer);
const upem = font.unitsPerEm;

const lines = [];
lines.push("///|");
lines.push("/// Auto-generated from NotoSans-Regular.ttf (unitsPerEm=" + upem + ").");
lines.push("/// Do not edit by hand — run `node scripts/gen_noto_advances.mjs`.");
lines.push("/// Advance as a fraction of em (`advanceWidth / unitsPerEm`).");
lines.push("pub fn noto_advance_em(ch : Char) -> Float {");
lines.push("  match ch {");

function charLit(cp) {
  if (cp === 32) return "' '";
  if (cp === 39) return "'\\''"; // '
  if (cp === 92) return "'\\\\'"; // \
  const ch = String.fromCodePoint(cp);
  // MoonBit char literals for printable ASCII
  return "'" + ch + "'";
}

for (let cp = 32; cp <= 126; cp++) {
  const adv = font.advanceOf(cp) / upem;
  lines.push("    " + charLit(cp) + " => " + adv.toFixed(4));
}
lines.push("    _ => 0.55");
lines.push("  }");
lines.push("}");

const out = "render/noto_advances.mbt";
fs.writeFileSync(out, lines.join("\n") + "\n");
console.log("wrote", out);
