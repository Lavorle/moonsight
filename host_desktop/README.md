# MoonSight desktop shell (Tauri 2)

Minimal **Tauri 2** window that loads the **same** `host_web` static build used in the browser. There is no second render backend: WebGPU + WASM run inside the webview exactly as in `dist/demo`.

## Layout

```
host_desktop/
  README.md                 # this file
  tauri/                    # npm + Tauri CLI project
    package.json
    src-tauri/
      Cargo.toml
      tauri.conf.json       # frontendDist → ../../dist/demo
      capabilities/
      icons/
      src/{main,lib}.rs
```

Asset path (from `src-tauri/`):

| Mode | Source |
|------|--------|
| Production bundle | `build.frontendDist` = `../../../dist/demo` |
| Dev | local static server on `http://127.0.0.1:4173` serving `dist/demo` |

## Prerequisites

1. **Web dist** — build the demo (or any project) into `dist/demo` first:

   ```bash
   # from repo root
   export CC=gcc
   moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
   # ensures host_web.wasm is present (release wasm-gc build of host_web if needed)
   ```

2. **Rust** stable + system deps for Tauri 2 on Linux (WebKitGTK, etc.):
   - See [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/)
   - Fedora: `webkit2gtk4.1-devel`, `openssl-devel`, `gtk3-devel`, `libayatana-appindicator-gtk3-devel`, `librsvg2-devel`, `gcc`, `pkg-config`

3. **Node.js** + npm (for `@tauri-apps/cli`)

## Run

```bash
# build web dist, then
cd host_desktop/tauri && npm install && npm run tauri dev
```

Production-style package (embeds `dist/demo`):

```bash
cd host_desktop/tauri && npm run tauri build
```

## Saves (Phase 1)

Phase 1 **keeps `localStorage`** inside the webview (`moonsight/save/{slot}` via `host_web/js_glue/boot.js`). No Tauri filesystem plugin is wired yet.

If later localStorage is insufficient (quota / multi-profile / export), map the save path to the OS app data dir with `@tauri-apps/plugin-fs` (or a thin Rust command) under e.g. `{appDataDir}/moonsight/save/`. That is intentionally deferred past Phase 1.

## Design notes

- **Same web build** — do not reimplement GPU/audio in Rust; only shell chrome and (future) native paths.
- **CSP** — left open (`null`) so WASM + WebGPU glue match browser hosting.
- **WebGPU in webview** — depends on the platform webview (WebView2 / WKWebView / WebKitGTK). If GPU init fails, fall back to browser serve of `dist/demo`.
- **Icons** — placeholder PNGs under `src-tauri/icons/`; replace with `npm run tauri icon path/to/app.png` when branding lands.
