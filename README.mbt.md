# MoonSight

MoonBit + WebGPU visual novel engine (Phases 1–4 + Q1/0.5 + Q2 multi-track +
Q3/0.8 system UI + **Q4 / 1.0 candidate** publish path: `moonsightc new`,
Svelte-only build, SaveStore Web/desktop, sample chapter, publish scripts).

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

# Svelte host shell (required by moonsightc build)
cd apps/host-web && npm i && npm run build && cd ../..
moon build --target wasm-gc --release host_web

# compile sample game + package web dist (demo sets ui_package → rebuilds host wasm)
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo

# play in browser (WebGPU; use localhost — not file://)
cd dist/demo && python3 -m http.server 8080
# open http://localhost:8080/
```

Scaffold a new project (copies `templates/minimal`):

```bash
export CC=gcc
moon run cmd/moonsightc --target native -- new mygame
cd apps/host-web && npm i && npm run build && cd ../..
moon run cmd/moonsightc --target native -- check mygame
moon run cmd/moonsightc --target native -- build mygame -o dist/mygame
```

One-shot web package: `./scripts/publish-web.sh [project] [out]` (default
`demo/game` → `dist/demo`). Desktop: `./scripts/publish-desktop.sh` (see
[`host_desktop/README.md`](./host_desktop/README.md)).

## Web host (Svelte)

`moonsightc build` copies the **Svelte** web shell from **`apps/host-web/dist`**
(requires `index.html`). Build that shell first, then package the game.

```bash
export CC=gcc
cd apps/host-web && npm i && npm run build && cd ../..
moon build --target wasm-gc --release host_web
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

With no `ui_package`, moonsightc does not rebuild wasm automatically — refresh
into Svelte `public/` for dev when needed:

```bash
moon build --target wasm-gc --release host_web
cp _build/wasm-gc/release/build/host_web/host_web.wasm apps/host-web/public/
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

**Input:** cold start on **title** (Start → entry scene). Pointer is engine
hit-test via `export_pointer` (button / choice / slider; empty Playing click →
Advance; move = hover + cursor; leave clears hover). Same frame: pointer then
`export_frame(0, dt, skip)` — no double Advance. Keyboard: Enter / Space / Z
advance (or activate focused menu button); **Esc** system menu; **↑↓** / W/S
focus; **←→** settings sliders; **H** backlog; **Ctrl hold** skip; 1–9 select
choices; A auto; Ctrl+S / Ctrl+L quick save & load slot 0 (`localStorage`).
Timed `@flow.wait` ignores Advance/skip until the countdown finishes. Menus
pause narrative Advance. Full semantics: [`docs/play-input.md`](./docs/play-input.md).

**Theme:** default **Amber Soft** pack at `themes/amber_soft` (logical `ui.*`
roles; host solids + optional PNGs). Author notes:
[`docs/ui-moonbit.md`](./docs/ui-moonbit.md#themes).

**Desktop shell:** build `dist/demo` first, then see
[`host_desktop/README.md`](./host_desktop/README.md). Desktop saves use
**appData** (`DesktopSaveStore`); browser uses **`localStorage`** — slots are
**not** interchangeable.

## Packages

| Path | Role |
|------|------|
| `script` | MoonYuki → IR / `MSB1` (rejects project `- screen`) |
| `runtime` | VM, Director, Stage, UiApp/UiRuntime, prefs, save (v4), tweens + scale |
| `render` | Draw list pack, text layout, kind+z sort, scale→sprite size, `UiDrawOp` paint |
| `audio` | Logical BGM/SE mixer (volume / fade) |
| `std_commands` | Standard `@` host commands (layers, dissolve, ui.show/hide, audio) |
| `std_ui` | Default HUD + title / game_menu / save_load / settings / confirm / backlog |
| `host_web` | Browser wasm host (WebGPU entry; shell is `apps/host-web`) |
| `apps/host-web` | Svelte+TS host shell (**required** by `moonsightc`; build `dist/` first) |
| `host_desktop` | Tauri 2 shell (appData SaveStore) |
| `cmd/moonsightc` | `new` / `check` / `build` CLI (scaffold, resource check, optional ui_package) |
| `templates/minimal` | Source tree for `moonsightc new` |
| `demo/game` | Sample project (+ optional `ui/` override) |

## Documentation

**Site:** bilingual Fumadocs app at [`apps/docs-site`](./apps/docs-site) —
Getting Started (incl. `new`), MoonYuki, play input, UI, **publish**, **desktop**
(zh + en). From that directory: `npm install && npm run dev` →
`http://localhost:3000` (default `/zh`).

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

### Q2 (Engine presentation + multi-track) — delivered

**Engine:** `@trans.dissolve duration` dual-phase full-screen veil (0→1→0 over
wall-clock duration; non-blocking, pair with `@flow.wait`); layer `scale=` on
`@layer.show` / `@layer.set` with linear `duration=` tween (origin top-left
`(x,y)`; no rotate/anchor); save format **v4** (`scale` on layers; v3 loads
default `scale=1.0`); longer demo (`demo/game`) with dissolve/scale beats and
extra garden/bench scenes; docs for dissolve/scale and presentation vs wait/skip
in [`docs/host-commands.md`](./docs/host-commands.md) /
[`docs/play-input.md`](./docs/play-input.md). Voice track and deep SE work were
explicitly **not** in scope (SE status quo).

**Host:** Vite + Svelte 5 + TypeScript shell at [`apps/host-web`](./apps/host-web)
with WebGPU/Slug adapters under `src/adapters/`. `moonsightc build` requires
`apps/host-web/dist` (`index.html`). Default playable path after `npm run build`
in `apps/host-web` + `moonsightc build` is the Svelte shell.

**Docs:** Fumadocs (Next.js) bilingual site at
[`apps/docs-site`](./apps/docs-site) — Getting Started, MoonYuki subset, play
input, publish, desktop for **zh** and **en**. Routes:
`/{lang}/docs/getting-started` (and sibling pages under `/{lang}/docs/…`).
Default locale **zh**. Repo `docs/*.md` remain engine source of truth for
unmigrated topics.

### Q3 / 0.8 (system UI) — automated gate green

**In:** vertical `UiNode::ScrollView` (clip, scrollbar track/thumb) consumed by
the backlog modal (full ring bind, pin newest on open); wheel + content pan +
bar drag + ↑/↓ line scroll; pointer **phase 2** (`pointerup`) ends drag without
Advance; dual-host wheel sign (`dy = -deltaY`) and **Ctrl blur/visibility**
clears sticky skip; confirm unified (overwrite / quit-to-title, default **No**);
slot empty/filled theme icons; scroll + slot theme roles; host full-panel
loading/error; `layer.show`/`set` **scale** on both builtins and std_commands
paths; mid-dissolve load **hard-clears** dissolve veil; menu/quick-save host
stamps `saved_at` for slot labels; author docs + Fumadocs zh/en (play-input +
UI). See [`.superpowers/sdd/q3-final-verify-report.md`](./.superpowers/sdd/q3-final-verify-report.md).

**Automated gates (0.8):** `export CC=gcc` then `moon check`, `moon test`,
`moon build --target wasm-gc --release host_web`,
`moon run cmd/moonsightc --target native -- build demo/game -o dist/demo`,
`apps/host-web` `npm run build`, `apps/docs-site` `npm run build` — all exit 0.

**Manual D6 (WebGPU browser):** Title → Start → long backlog scroll (wheel /
drag / bar / ↑↓) → Close/Esc; mouse Advance / choices / Esc menu / overwrite
confirm defaults No; dissolve + scale visible; Ctrl skip vs `@flow.wait`; blur
clears skip; force error path message. **Deferred to human browser** (same
honest pattern as Pointer Theme) — not claimed pass in CI/agent headless.

### Out of scope / deferred to Q4+

Visual editor, full product i18n beyond docs-site locales, achievements,
Live2D / 3D, particle/postprocess stack, full timeline / animation queues,
blocking presentation DSL, rotate/anchor, voice track, slot screenshots,
horizontal / nested ScrollView, list virtualization, fling/rubber-band, saving
backlog into slots, rollback, DOM game menus, second native GPU backend, second
wasm / dynamic UI load, runtime theme switcher / multi-theme store, transform
animation stack, open host-string UI actions, official Yukimi bytecode
compatibility, long-term Screen DSL lower compatibility, **`moonsight new` /
project templates**, **desktop native save**, Host full consolidation,
interactive WebGPU CI, committing wasm build artifacts to git.
