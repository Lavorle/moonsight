# MoonSight

MoonBit + WebGPU visual novel engine (Phase 1 runtime kernel + Phase 2 layer
presentation).

MoonYuki scripts compile to IR/bytecode, run on a VM + Stage/Director, and
render through a packed draw list consumed by a JS WebGPU host. Desktop uses
the same web build inside a minimal Tauri shell.

## Quickstart

```bash
# from repo root
export CC=gcc

# typecheck + unit tests
moon check
moon test

# compile sample game + web dist
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo

# optional: refresh host wasm into js_glue before build if missing
moon build --target wasm-gc --release host_web
cp _build/wasm-gc/release/build/host_web/host_web.wasm host_web/js_glue/

# play in browser (WebGPU; use localhost — not file://)
cd dist/demo && python3 -m http.server 8080
# open http://localhost:8080/
```

### Browser / WebGPU (important on Linux)

MoonSight **requires WebGPU**. There is no WebGL fallback.

| Browser | Notes |
|---------|--------|
| **Chrome / Edge / Chromium** | Best path. On **Linux** enable flags if needed (below). |
| **Brave** | Chromium-based; on Linux often needs the same flags as Chrome. |
| **Firefox** | WebGPU shipped more fully on Windows/macOS; **Linux is still experimental** and often needs `about:config` or Nightly. |

**Brave / Chrome (Linux) — if you see `WebGPU not available`:**

1. Open `brave://flags` or `chrome://flags`
2. Enable **Unsafe WebGPU Support** (`#enable-unsafe-webgpu`)
3. Enable **Vulkan** (`#enable-vulkan`) — commonly required on Linux
4. Optional: **Ignore GPU blocklist** (`#ignore-gpu-blocklist`)
5. Relaunch, then check `brave://gpu` / `chrome://gpu` (WebGPU should not be “Disabled”)

CLI:

```bash
brave-browser --enable-unsafe-webgpu --enable-features=Vulkan --use-angle=vulkan http://localhost:8080/
# or: google-chrome --enable-unsafe-webgpu --enable-features=Vulkan ...
```

**Firefox:**

1. `about:config` → set `dom.webgpu.enabled` = `true`
2. Also try `gfx.webgpu.force-enabled` and/or `gfx.webgpu.ignore-blocklist` = `true`
3. Restart; if `navigator.gpu` is still missing, use **Firefox Nightly** or a Chromium browser

Always serve via **`http://localhost`** (or https). Opening `file://` blocks WebGPU.

**Input:** click / Enter / Space / Z advance; 1–9 select choices; Ctrl+S / Ctrl+L
save & load (localStorage). Timed `@flow.wait` ignores Advance until the
countdown finishes.

**Desktop shell:** build `dist/demo` first, then see
[`host_desktop/README.md`](./host_desktop/README.md).

## Packages

| Path | Role |
|------|------|
| `script` | MoonYuki → IR / `MSB1` bytecode |
| `runtime` | VM, Director, Stage, save (v3), tweens |
| `render` | Draw list pack, text layout, kind+z sort |
| `audio` | Logical BGM/SE mixer |
| `std_commands` | Standard `@` host commands (`layer.set`, kinds, duration) |
| `host_web` | Browser wasm + `js_glue` |
| `host_desktop` | Tauri 2 shell |
| `cmd/moonsightc` | `check` / `build` CLI (literal resource check) |
| `demo/game` | Sample project |

## Documentation

- [`docs/moon-yuki-subset.md`](./docs/moon-yuki-subset.md) — grammar subset
- [`docs/host-commands.md`](./docs/host-commands.md) — host command table + intents
- [`docs/project-layout.md`](./docs/project-layout.md) — repo & `moonsight.json`
- [`docs/draw-list-pack.md`](./docs/draw-list-pack.md) — frame pack format

## Scope

### Phase 1 (runtime kernel)

**In:** compile pipeline, VM, layers, dialogue typing, choices, variables,
jumps, BGM/SE, fade, save/load, browser host, desktop shell, demo, CLI, tests.

### Phase 2 (layer presentation)

**In:** `LayerKind` via `@layer.show kind=…`, linear `x`/`y`/`opacity` duration
tweens, `@layer.set`, wall-clock `trans.fade` (`fade_remaining`), real
`@flow.wait` timing (non-skippable), save format **v3** (tweens + wait/fade
remaining; v2 still loads), build-time literal resource checks, hard-fail
texture loads, updated demo/docs.

### Out of scope (both phases)

Visual editor, i18n, achievements, Live2D / 3D, particle/postprocess stack,
full timeline / animation queues, blocking presentation DSL, `trans.dissolve`,
system menu / backlog / multi-slot UI, second native GPU backend, official
Yukimi bytecode compatibility.
