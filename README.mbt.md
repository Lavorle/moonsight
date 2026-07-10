# MoonSight

MoonBit + WebGPU visual novel engine (Phases 1–4 + Q1/0.5 playable core + Q2
Engine presentation: runtime kernel, layer presentation, system UI, MoonBit UI
kernel, backlog, hold-to-skip, confirm, prefs→mixer, `trans.dissolve`, layer
`scale=`).

MoonYuki scripts compile to IR/bytecode, run on a VM + Stage/Director, and
render through a packed draw list consumed by a JS WebGPU host. System menus and
dialogue HUD use a retained MoonBit UI tree (`std_ui` + optional project
`ui_package`). Desktop uses the same web build inside a minimal Tauri shell.

## Quickstart

```bash
# from repo root
export CC=gcc

# typecheck + unit tests
moon check
moon test

# compile sample game + web dist (demo sets ui_package → rebuilds host wasm)
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo

# play in browser (WebGPU; use localhost — not file://)
cd dist/demo && python3 -m http.server 8080
# open http://localhost:8080/
```

## Web host (Q2+)

`moonsightc build` copies a web shell into the output directory:

1. **`apps/host-web/dist`** when present (Svelte/Vite; requires `index.html`)
2. **`host_web/js_glue`** fallback (vanilla JS — default playable path if dist is missing)

Recommended order when using the Svelte host:

```bash
export CC=gcc
cd apps/host-web && npm i && npm run build && cd ../..
moon build --target wasm-gc --release host_web
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Without a Svelte dist build, the vanilla `js_glue` shell is still used. With no
`ui_package`, you may still refresh wasm into the shell sources manually:

```bash
moon build --target wasm-gc --release host_web
cp _build/wasm-gc/release/build/host_web/host_web.wasm host_web/js_glue/
# optional: also into Svelte public/ for dev
# cp _build/wasm-gc/release/build/host_web/host_web.wasm apps/host-web/public/
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

**Input:** cold start on **title** (Start → entry scene). Click / Enter / Space /
Z advance (or activate focused menu button); **Esc** system menu; **↑↓** / W/S
focus; **←→** settings sliders; **H** backlog; **Ctrl hold** skip; 1–9 select
choices; A auto; Ctrl+S / Ctrl+L quick save & load slot 0 (`localStorage`).
Timed `@flow.wait` ignores Advance/skip until the countdown finishes. Menus
pause narrative Advance. Full semantics: [`docs/play-input.md`](./docs/play-input.md).

**Desktop shell:** build `dist/demo` first, then see
[`host_desktop/README.md`](./host_desktop/README.md).

## Packages

| Path | Role |
|------|------|
| `script` | MoonYuki → IR / `MSB1` (rejects project `- screen`) |
| `runtime` | VM, Director, Stage, UiApp/UiRuntime, prefs, save (v4), tweens + scale |
| `render` | Draw list pack, text layout, kind+z sort, scale→sprite size, `UiDrawOp` paint |
| `audio` | Logical BGM/SE mixer (volume / fade) |
| `std_commands` | Standard `@` host commands (layers, dissolve, ui.show/hide, audio) |
| `std_ui` | Default HUD + title / game_menu / save_load / settings / confirm / backlog |
| `host_web` | Browser wasm + `js_glue` fallback shell (WebGPU, prefs, multi-slot) |
| `apps/host-web` | Svelte+TS host shell (preferred by `moonsightc` when `dist/` exists) |
| `host_desktop` | Tauri 2 shell |
| `cmd/moonsightc` | `check` / `build` CLI (literal resource check, optional ui_package link) |
| `demo/game` | Sample project (+ optional `ui/` override) |

## Documentation

**Site (Q2):** bilingual Fumadocs app at [`apps/docs-site`](./apps/docs-site) —
Getting Started, MoonYuki subset, and play input (zh + en). From that directory:
`npm install && npm run dev` → `http://localhost:3000` (default `/zh`).

Repo markdown (engine source of truth until migration completes; Q2 core pages
on the site are authoritative for listed topics):

- [`docs/moon-yuki-subset.md`](./docs/moon-yuki-subset.md) — grammar subset
- [`docs/ui-moonbit.md`](./docs/ui-moonbit.md) — MoonBit UI authoring (HUD + modals)
- [`docs/host-commands.md`](./docs/host-commands.md) — host command table + intents
- [`docs/play-input.md`](./docs/play-input.md) — intents, skip hold, wait gate, backlog/confirm
- [`docs/project-layout.md`](./docs/project-layout.md) — repo & `moonsight.json`
- [`docs/draw-list-pack.md`](./docs/draw-list-pack.md) — frame pack format
- [`docs/screen-language.md`](./docs/screen-language.md) — obsolete Phase 3 Screen DSL archive

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

### Phase 3 (Screen UI + system menu)

**In (historical path):** Screen DSL + runtime stack/focus, standard four
screens, multi-slot saves + prefs, cold-start title, WebGPU-drawn widgets,
`@ui.show`/`@ui.hide`, named negatives, audio load hard-fail, BGM volume/fade.

### Phase 4 (MoonBit UI kernel)

**In:** retained `UiApp` / `UiRuntime` (HUD + modal stack), Capabilities +
button handlers, `std_ui` default HUD and four modals, optional project
`ui_package` linked into the same host wasm, dialogue/choice paint via HUD tree
only, project `- screen` hard error, no `screens.json` primary dist path, demo
override sample + author docs.

### Q1 / 0.5 (playable core)

**In:** session **backlog** (ring 100; H / History; not saved); **Ctrl hold**
`skip_held` burst advance (max 8/frame; no timed-wait skip; no auto-choice);
**confirm** for overwrite save + quit to title (default focus No); **prefs →
mixer** gains (master/bgm/se); settings **Slider** (←/→); slot labels show
`saved_at` when present; input/wait semantics in
[`docs/play-input.md`](./docs/play-input.md).

### Q2 (Engine presentation + multi-track)

**Engine (in):** `@trans.dissolve duration` dual-phase full-screen veil
(0→1→0 over wall-clock duration; non-blocking, pair with `@flow.wait`); layer
`scale=` on `@layer.show` / `@layer.set` with linear `duration=` tween (origin
top-left `(x,y)`; no rotate/anchor); save format **v4** (`scale` on layers;
v3 loads default `scale=1.0`); longer demo beats using dissolve/scale; docs for
dissolve/scale and presentation vs wait/skip in
[`docs/host-commands.md`](./docs/host-commands.md) /
[`docs/play-input.md`](./docs/play-input.md).

**Host / Docs (WIP mid-track):** Svelte+TS host shell (`apps/host-web`) and
Fumadocs site (`apps/docs-site`) are Q2 multi-track deliverables — not required
for Engine dissolve/scale. `moonsightc build` prefers `apps/host-web/dist` when
built; vanilla `host_web/js_glue` remains the fallback play path.

### Out of scope (through Q2 Engine non-goals)

Visual editor, i18n, achievements, Live2D / 3D, particle/postprocess stack,
full timeline / animation queues, blocking presentation DSL, rotate/anchor,
voice track, slot screenshots, backlog free-scroll / ScrollView, saving backlog
into slots, rollback, DOM menus, second native GPU backend, second wasm /
dynamic UI load, themes / transform animation stack, open host-string UI
actions, official Yukimi bytecode compatibility, long-term Screen DSL lower
compatibility.
