#!/usr/bin/env node
/**
 * Static file server for dist/demo during `tauri dev`.
 *
 * No React/Svelte toolchain inside Tauri — moonsightc packages the host shell
 * into dist/demo (prefers apps/host-web/dist Svelte build, else host_web/js_glue).
 * Paths: scripts/ → repo root is ../../../dist/demo (same as tauri.conf frontendDist).
 */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
/** Repo-root dist/demo (from host_desktop/tauri/scripts/). */
const ROOT = path.resolve(__dirname, "../../../dist/demo");
const PORT = Number(process.env.MOONSIGHT_DEV_PORT || 4173);
const HOST = process.env.MOONSIGHT_DEV_HOST || "127.0.0.1";

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".wasm": "application/wasm",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".ogg": "audio/ogg",
  ".mp3": "audio/mpeg",
  ".yuki": "text/plain; charset=utf-8",
  ".msb": "application/octet-stream",
  ".wgsl": "text/plain; charset=utf-8",
  ".map": "application/json; charset=utf-8",
};

if (!fs.existsSync(ROOT)) {
  console.error(
    `[serve-dist] missing ${ROOT}\n` +
      `Build first (from repo root):\n` +
      `  export CC=gcc\n` +
      `  # optional Svelte shell (moonsightc prefers apps/host-web/dist):\n` +
      `  cd apps/host-web && npm i && npm run build && cd ../..\n` +
      `  moon build --target wasm-gc --release host_web\n` +
      `  moon run cmd/moonsightc --target native -- build demo/game -o dist/demo`,
  );
  process.exit(1);
}

const server = http.createServer((req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${HOST}:${PORT}`);
    let rel = decodeURIComponent(url.pathname);
    if (rel === "/") rel = "/index.html";
    const file = path.normalize(path.join(ROOT, rel));
    if (!file.startsWith(ROOT)) {
      res.writeHead(403).end("forbidden");
      return;
    }
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404).end("not found");
      return;
    }
    const ext = path.extname(file).toLowerCase();
    res.writeHead(200, {
      "Content-Type": TYPES[ext] || "application/octet-stream",
      "Cache-Control": "no-cache",
      // COOP/COEP not required for Phase 1; keep simple for webview.
    });
    fs.createReadStream(file).pipe(res);
  } catch (e) {
    res.writeHead(500).end(String(e));
  }
});

server.listen(PORT, HOST, () => {
  console.log(`[serve-dist] ${ROOT} → http://${HOST}:${PORT}/`);
});
