# MoonSight

MoonBit + WebGPU visual novel engine (Phase 1 runtime kernel).

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

# play in browser (WebGPU; use localhost)
cd dist/demo && python3 -m http.server 8080
# open http://localhost:8080/
```

**Input:** click / Enter / Space / Z advance; 1–9 select choices; Ctrl+S / Ctrl+L
save & load (localStorage).

**Desktop shell:** build `dist/demo` first, then see
[`host_desktop/README.md`](./host_desktop/README.md).

## Packages

| Path | Role |
|------|------|
| `script` | MoonYuki → IR / `MSB1` bytecode |
| `runtime` | VM, Director, Stage, save |
| `render` | Draw list pack, text layout |
| `audio` | Logical BGM/SE mixer |
| `std_commands` | Standard `@` host commands |
| `host_web` | Browser wasm + `js_glue` |
| `host_desktop` | Tauri 2 shell |
| `cmd/moonsightc` | `check` / `build` CLI |
| `demo/game` | Sample project |

## Documentation

- [`docs/moon-yuki-subset.md`](./docs/moon-yuki-subset.md) — grammar subset
- [`docs/host-commands.md`](./docs/host-commands.md) — host command table + intents
- [`docs/project-layout.md`](./docs/project-layout.md) — repo & `moonsight.json`
- [`docs/draw-list-pack.md`](./docs/draw-list-pack.md) — frame pack format

## Phase 1 scope

**In:** compile pipeline, VM, layers, dialogue typing, choices, variables,
jumps, BGM/SE, fade, save/load, browser host, desktop shell, demo, CLI, tests.

**Out:** visual editor, i18n, achievements, Live2D / 3D, second native GPU
backend, official Yukimi bytecode compatibility.
