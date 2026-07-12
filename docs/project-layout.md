# Project layout (Phases 1–4 + Q1–Q4)

MoonSight is a MoonBit module (`moonsight/moonsight`) with packages at the
repository root (not under a nested `packages/` folder). Preferred build target
is `wasm-gc`; the CLI package is **native-only**.

## Repository map

```
moonsight/
  moon.mod                 # module metadata (readme → README.mbt.md)
  README.mbt.md            # quickstart
  LICENSE                  # Apache-2.0
  .github/workflows/ci.yml # moon check + moon test (+ moonsightc smoke)

  script/                  # MoonYuki lexer → parser → macro → resolve → IR → MSB
  runtime/                 # VM, Director, Stage, intents, save, UiApp/UiRuntime, prefs
  render/                  # DrawList, pack, text layout, UiDrawOp paint, glyph atlas
  audio/                   # Logical mixer + event queue (volume/fade)
  std_commands/            # Standard host command table (incl. ui.show/hide, dissolve)
  std_ui/                  # Default HUD + title / game_menu / save_load / settings / backlog / confirm
  apps/
    host-web/              # Svelte+TS host shell (Vite 6 + Svelte 5); moonsightc requires dist/
      src/
        adapters/          # webgpu_bridge, slug, wasm boot
        lib/               # gameSession + SaveStore + host glue (TS)
        App.svelte         # shell UI chrome
      public/              # wasm, fonts, demo placeholders for vite dev
      dist/                # static production shell (index.html + assets/) — required by moonsightc
    docs-site/             # Fumadocs (Next.js) bilingual author docs (zh default)
      content/
        zh/                # Chinese MDX (getting-started, publish, desktop, …)
        en/                # English MDX (same page set)
      app/                 # Next app router ([lang], docs, search, llms)
  host_web/                # Wasm host entry (WebGPU/audio/input/prefs)
    project_ui/            # Overlay stub; moonsightc may link project ui_package here
  archive/js_glue/         # Historical vanilla shell only (not referenced by moonsightc)
  host_desktop/            # Minimal Tauri 2 shell over dist/demo (appData SaveStore)
  cmd/moonsightc/          # new / check / build CLI (native)
  templates/minimal/       # Scaffold copied by moonsightc new
  scripts/                 # publish-web.sh, publish-desktop.sh
  demo/game/               # Sample project (authoring source + optional ui/)
  dist/                    # Build output (usually untracked)
  docs/                    # Specs, plans, author docs (repo SoT for unmigrated topics)
```

| Package / app | Role |
|---------------|------|
| `script` | Compile MoonYuki → IR/bytecode (narrative only; rejects `- screen`) |
| `runtime` | IR VM, Director, Stage (scale + dissolve clock), UiApp/UiRuntime, prefs, save **v5** (reads v2-v5) |
| `render` | CPU draw list + float pack for JS GPU (layers + scale × size + `UiDrawOp`) |
| `audio` | BGM/SE logical mixer (volume, fade) |
| `std_commands` | `standard_registry()` host handlers (`trans.dissolve`, `scale=`, …) |
| `std_ui` | Default HUD + system modals including backlog / confirm (MoonBit) |
| `host_web` | `init_demo` / `export_frame` / prefs exports; links `std_ui` + `project_ui` |
| `apps/host-web` | Required browser shell (Svelte+TS static dist + SaveStore) |
| `apps/docs-site` | Author-facing docs site (not linked into wasm) |
| `templates/minimal` | Source tree for `moonsightc new` |
| `cmd/moonsightc` | `new` / `check` / `build`; optional `ui_package` link |

Dependency direction (high level):

```
script ──► (no render)
runtime ──► script types/IR usage as needed
std_commands ──► runtime (+ audio for bgm/se)
std_ui ──► runtime (UiApp)
render ──► runtime (intent, stage, UiDrawOp)
host_web ──► runtime, render, std_commands, std_ui, project_ui, script, audio
moonsightc ──► script (+ native FS); links project_ui when ui_package set
```

## Game project layout

A playable project is a directory with JSON config, sources, and assets:

```
my_game/
  moonsight.json           # required for moonsightc build
  main.yuki                # entry (or path in config)
  scenes/                  # optional extra .yuki files
    intro.yuki
  assets/                  # images + audio (optional)
    bg_room.png
    char_y.png
    bgm_soft.ogg
  locales/                 # strict complete catalogs for supported locales
    en.json
    zh-Hans-CN.json
  ui/                      # optional MoonBit UI package (see ui_package)
    lib.mbt
```

UI is **not** authored with `- screen` in `.yuki` (Phase 4 compile error).
Default chrome ships from engine `std_ui`. Optional project package overrides
via `ui_package` — see [`ui-moonbit.md`](./ui-moonbit.md).

### Scaffold: `moonsightc new`

```bash
moon run cmd/moonsightc --target native -- new mygame
# optional: new mygame -o path/to/parent
```

Copies monorepo **`templates/minimal/`** into `<parent>/<name>/` (default parent
is cwd). Destination must not already exist. Template contents:

| Path | Role |
|------|------|
| `moonsight.json` | Minimal valid config (`entry`, sizes, `save_slots`; no `ui_package`) |
| `main.yuki` | Short playable loop (title → dialogue → choice → end) |
| `assets/` | Empty placeholder dir (add media as needed) |
| `README.md` | Short check / build / play steps |

No project `ui/` — cold-start title and menus come from engine `std_ui`. Demo
showcase remains `demo/game/` (longer sample + optional `ui/`). Mini golden
fixture: `script/testdata/mini_game/`.

### `moonsight.json`

Phase 1 pins **JSON** (no TOML dependency).

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `name` | string | `"moonsight"` | Project display name → manifest |
| `entry` | string | `"main.yuki"` | Entry source path relative to project root |
| `logical_width` | number | `1920` | Logical canvas width |
| `logical_height` | number | `1080` | Logical canvas height |
| `save_slots` | number | `6` | Multi-slot count (clamped **1..20**) |
| `default_locale` | string | `"en"` | Initial catalog locale |
| `supported_locales` | string[] | `[default_locale]` | Strict complete locale set packaged into MSB2 |
| `ui_package` | string \| omit | omit | Relative dir of MoonBit UI sources linked into host wasm |

Example (`demo/game/moonsight.json`):

```json
{
  "name": "moonsight-demo",
  "entry": "main.yuki",
  "logical_width": 1920,
  "logical_height": 1080,
  "ui_package": "ui"
}
```

`build` fails if `moonsight.json` is missing. Missing entry file warns but still
compiles other `.yuki` files. When `ui_package` is set, build copies `*.mbt`
into `host_web/project_ui`, rebuilds `host_web` wasm, then **restores** the
committed no-op stub.

### Asset ids

`moonsightc build` walks `assets/` recursively:

- **Images** (png/webp/jpg/…) → `manifest.resources[id] = relative path`
- **Audio** (ogg/mp3/…) → `manifest.audio[id] = relative path`
- **id** = file basename without extension (subdir is **not** part of the id)

Script references use those ids: `@layer.show "bg" "bg_room"`,
`@audio.bgm "bgm_soft"`. Literal missing ids fail the build (audio and images).

## Build outputs

```bash
export CC=gcc   # moonsightc forces gcc on native
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Typical `dist/demo/`:

| Artifact | Purpose |
|----------|---------|
| `game.msb` | Deterministic executable plus embedded locale catalogs (`MSB2`; executable payload remains MSB1-compatible internally) |
| `demo.yuki` | Copy of entry source (host load path today) |
| `manifest.json` | name, logical size, resources, audio, save_slots |
| `assets/**` | Copied media |
| `index.html`, `host_web.wasm`, shell assets | Host shell from `apps/host-web/dist` only (Svelte/Vite). Wasm includes `std_ui` + linked project UI. Dist ships Vite-bundled JS/CSS under `assets/`. |

**Host shell discovery** (`moonsightc build`): **only** `apps/host-web/dist`
when it contains `index.html`. Missing shell → build fails (build the Svelte
host first). Project `manifest.json` always overwrites any shell placeholder;
release `host_web.wasm` is injected when present under
`_build/wasm-gc/release/build/host_web/`.

**No `screens.json` primary path.** UI trees live in the host wasm via
`std_ui` / `project_ui` registration at engine init.

`manifest.json` shape:

```json
{
  "name": "moonsight-demo",
  "logical_width": 1920,
  "logical_height": 1080,
  "save_slots": 6,
  "resources": { "bg_room": "assets/bg_room.png", "char_y": "assets/char_y.png" },
  "audio": { "bgm_soft": "assets/bgm_soft.ogg" }
}
```

Build uses staging then promotes on success; failure must not leave a broken
`out_dir`. With `ui_package`, a failed prepare/rebuild restores `project_ui`
stub.

Recommended web shell build order (Svelte only):

```bash
export CC=gcc
cd apps/host-web && npm i && npm run build && cd ../..
moon build --target wasm-gc --release host_web
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Or one-shot from repo root:

```bash
./scripts/publish-web.sh demo/game dist/demo
```

Without `apps/host-web/dist/index.html`, `moonsightc build` fails (Svelte dist
required). Without `ui_package`, moonsightc does not rebuild wasm automatically
— refresh into Svelte `public/` for dev when needed:

```bash
moon build --target wasm-gc --release host_web
cp _build/wasm-gc/release/build/host_web/host_web.wasm apps/host-web/public/
```

## Hosts

### Browser (`apps/host-web` only)

Serve `dist/demo` (or a host shell root after copy) over localhost. WebGPU
requires a secure context. **WebGPU only** — no WebGL fallback.

Cold start path: load narrative (`game.msb` / entry) → hydrate slots/prefs →
`boot_title()` → title **Start** → narrative entry. Init order:
`UiApp::new` → `@std_ui.register` → `@project_ui.register` → `Engine::from_ir`.

**Svelte shell** (`apps/host-web`):

| Path | Role |
|------|------|
| `src/lib/gameSession.ts` | Boot loop, input → intents, Ctrl→`skip_held`, frame export |
| `src/lib/saveStore.ts` | `SaveStore` + `WebSaveStore` (`localStorage`) |
| `src/lib/desktopSaveStore.ts` | `DesktopSaveStore` (Tauri appData) |
| `src/adapters/` | `webgpu_bridge`, Slug shaders/JS, wasm helpers |
| `src/App.svelte` | Minimal chrome; picks Web vs Desktop SaveStore |
| `dist/` | Vite production output copied by `moonsightc` |

Web prefs/slots: `localStorage` keys `moonsight/prefs`, `moonsight/save/{n}`.

Input, prefs keys, and save keys are documented in
[`host-commands.md`](./host-commands.md),
[`play-input.md`](./play-input.md), and
[`ui-moonbit.md`](./ui-moonbit.md). Author publish guide:
docs-site **Build & Publish (Web)**.

### Docs site (`apps/docs-site`)

Standalone Next.js / Fumadocs app (not part of `moonsightc build`):

```bash
cd apps/docs-site && npm install && npm run dev
# default http://localhost:3000 → /zh
```

| Locale routes | Content |
|---------------|---------|
| `/zh/docs`, `/zh/docs/getting-started`, `…/publish`, `…/desktop`, … | `content/zh/*.mdx` |
| `/en/docs`, `/en/docs/getting-started`, … | `content/en/*.mdx` |

i18n: `parser: 'dir'`, default language **zh**. Search API and `llms*.txt`
routes ship with the scaffold.

### Desktop (`host_desktop`)

Minimal **Tauri 2** shell: same static files as browser (`frontendDist` →
`dist/demo`). See `host_desktop/README.md` and docs-site **Desktop**.

Saves use **OS appData** via `DesktopSaveStore` (not webview `localStorage`):

| Kind | Path |
|------|------|
| Prefs | `{appDataDir}/moonsight/prefs.json` |
| Slot *n* | `{appDataDir}/moonsight/saves/{n}.json` |

**Web slots ≠ desktop slots** — no automatic migration between browser
`localStorage` and appData files. Engine save JSON is v5 on both and readers
accept v2-v5.

One-shot: `./scripts/publish-desktop.sh` (web package + `tauri build`).

## CLI

```text
moonsightc version
moonsightc new <name> [-o <parent_dir>]
moonsightc check <file.yuki|dir>
moonsightc build <project_dir> [-o <out_dir>]
```

Via MoonBit:

```bash
moon run cmd/moonsightc --target native -- version
moon run cmd/moonsightc --target native -- new mygame
moon run cmd/moonsightc --target native -- check demo/game
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

## Core tests

```bash
export CC=gcc
moon check
moon test
```

Package tests cover lexer/parser/lower/bytecode, VM / director / stage / save /
UI kernel, render pack, audio mixer, std_commands registry alignment,
`std_ui` registration, and host_web blackbox where applicable.

## Phase / quarter notes

| Phase / Q | Focus |
|-----------|--------|
| **1** | Runtime kernel: compile, VM, layers, dialogue, choices, BGM/SE, fade, save, WebGPU host, CLI |
| **2** | Layer kinds, property tweens, `layer.set`, real `flow.wait`, wall-clock fade, save v3, resource checks |
| **3** | Screen DSL + runtime stack, std 4 screens, multi-slot + prefs, cold-start title, named negatives, audio hard-fail, BGM volume/fade, build cleanup |
| **4** | MoonBit UI kernel (HUD + modal stack), `std_ui`, Capabilities, optional `ui_package`, remove Screen DSL / `screens.json` primary |
| **Q1 / 0.5** | Session backlog (H), Ctrl hold skip, confirm overwrite/quit, prefs→mixer gains, settings Slider, play-input docs |
| **Q2** | `trans.dissolve`, layer `scale` + save v4, longer demo, Svelte host path, Fumadocs zh/en core pages |
| **Q3 / 0.8** | ScrollView backlog, pointer phase 2, dual-host wheel, confirm unified, slot/theme polish |
| **Q4** | `moonsightc new` + `templates/minimal`; Svelte-only shell; Web/Desktop SaveStore; publish scripts; publish/desktop docs |
| **Formal 1.0** | portable dot-separated author IDs; deterministic MSB2 with embedded strict locale catalogs; atomic hot locale switching; save v5; aggregate-state rollback with barriers and bounded history; retained release evidence |

## Documentation index

| Doc | Content |
|-----|---------|
| [`apps/docs-site`](../apps/docs-site) | Bilingual site (Getting Started, MoonYuki, play-input, UI, publish, desktop) |
| [`moon-yuki-subset.md`](./moon-yuki-subset.md) | Grammar subset + examples (repo SoT) |
| [`ui-moonbit.md`](./ui-moonbit.md) | MoonBit UI authoring (HUD + modals) |
| [`screen-language.md`](./screen-language.md) | **Obsolete** Phase 3 Screen DSL archive |
| [`host-commands.md`](./host-commands.md) | Host table, intents, errors (dissolve/scale) |
| [`play-input.md`](./play-input.md) | Intents, skip hold, wait gate, backlog/confirm |
| [`draw-list-pack.md`](./draw-list-pack.md) | Packed frame format + MenuUp/Down |
| [`project-layout.md`](./project-layout.md) | This file |
| [`formal-1.0-author-guide.md`](./formal-1.0-author-guide.md) | Formal 1.0 IDs, catalogs, migration review, MSB2, save v5, locale switching, rollback, budgets, and exclusions |
| [`release-1.0-verification.md`](./release-1.0-verification.md) | Exact-SHA release evidence template; W1/D1/C1 remain external gates |
| `superpowers/specs/…` | Design specs |
| `superpowers/plans/…` | Implementation plans |

## Explicit non-goals after Formal 1.0

Do not expect or document as shipped:

- Visual editor, achievements, Live2D, second native GPU backend
- Official YukimiScript bytecode interop, TOML project config
- Voice track; deep SE overhaul (SE status quo)
- Slot screenshot thumbnails; saving backlog into slots
- DOM / HTML **game** menus (host chrome may be DOM; narrative UI is MoonBit/wasm)
- Second wasm / dynamic UI load; general theme files; rotate/anchor; transform animation stack
- Open host-string UI actions / general expression language on the tree
- SE fade; cloud save sync; automatic **Web ↔ desktop** save migration
- Long-term Screen DSL lower compatibility (`- screen` is a hard error)
- Playable vanilla shell — historical sources only under `archive/js_glue/`
