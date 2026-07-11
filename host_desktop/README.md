# MoonSight desktop shell (Tauri 2)

Minimal **Tauri 2** window that loads the **same** static package as the browser:
`dist/demo` produced by `moonsightc build`. There is **no** second render backend
and **no** React/Svelte toolchain inside Tauri — WebGPU + WASM run in the webview
exactly as when serving `dist/demo` over HTTP.

The packaged shell content is whatever moonsightc copied from
**`apps/host-web/dist`** (Svelte/Vite; required — no vanilla fallback).

## Layout

```
host_desktop/
  README.md                 # this file
  tauri/                    # npm + Tauri CLI project
    package.json
    scripts/
      serve-dist.mjs        # static server → ../../../dist/demo
    src-tauri/
      Cargo.toml
      tauri.conf.json       # frontendDist → ../../../dist/demo
      capabilities/
      icons/
      src/{main,lib}.rs
```

Asset path (from `src-tauri/`):

| Mode | Source |
|------|--------|
| Production bundle | `build.frontendDist` = `../../../dist/demo` |
| Dev | `beforeDevCommand` → `npm run serve-dist` on `http://127.0.0.1:4173` serving the same `dist/demo` |

Both resolve to **repo-root** `dist/demo` (not `apps/host-web/dist` directly). Rebuild the game package after changing the Svelte host.

## Prerequisites

1. **Web dist** — build the Svelte host and package the demo into `dist/demo`
   first. `moonsightc` requires `apps/host-web/dist` (`index.html`):

   ```bash
   # from repo root
   export CC=gcc
   cd apps/host-web && npm i && npm run build && cd ../..
   moon build --target wasm-gc --release host_web   # wasm used by ui_package / inject
   moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
   ```

2. **Rust** stable + system deps for Tauri 2 on Linux (WebKitGTK, etc.):
   - See [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/)
   - Fedora: `webkit2gtk4.1-devel`, `openssl-devel`, `gtk3-devel`, `libayatana-appindicator-gtk3-devel`, `librsvg2-devel`, `gcc`, `pkg-config`

3. **Node.js** + npm (for `@tauri-apps/cli`)

4. **Display** — `tauri dev` / `tauri build` open a native window (needs a working GUI /
   WebKitGTK). On headless CI or SSH without display, skip the GUI and smoke the
   static path only (see below).

## Run

```bash
# build web dist, then
cd host_desktop/tauri && npm install && npm run tauri dev
```

Production-style package (embeds `dist/demo`):

```bash
cd host_desktop/tauri && npm run tauri build
```

### Headless / no-display smoke

When `DISPLAY` is unset or WebKit is unavailable, verify the same assets Tauri would load:

```bash
# from repo root — dist/demo must already exist
cd host_desktop/tauri && node scripts/serve-dist.mjs &
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4173/
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4173/host_web.wasm
# expect 200; Svelte shell: index references assets/index-*.js
# stop the server when done (Ctrl-C / kill)
```

**Manual GUI check** (local desktop): after `npm run tauri dev`, confirm the window
loads the title screen (same behavior as browser on `dist/demo`).

## Saves (Phase 1)

Phase 1 **keeps `localStorage`** inside the webview (`moonsight/save/{slot}` via the
Svelte web shell). No Tauri filesystem plugin is wired yet.

If later localStorage is insufficient (quota / multi-profile / export), map the save
path to the OS app data dir with `@tauri-apps/plugin-fs` (or a thin Rust command)
under e.g. `{appDataDir}/moonsight/save/`. That is intentionally deferred past Phase 1.

## Design notes

- **Same web build** — do not reimplement GPU/audio in Rust; only shell chrome and (future) native paths.
- **No in-Tauri frontend framework** — Tauri only hosts static files from `dist/demo`.
- **CSP** — left open (`null`) so WASM + WebGPU glue match browser hosting.
- **WebGPU in webview** — depends on the platform webview (WebView2 / WKWebView / WebKitGTK). If GPU init fails, fall back to browser serve of `dist/demo`.
- **Icons** — placeholder PNGs under `src-tauri/icons/`; replace with `npm run tauri icon path/to/app.png` when branding lands.
