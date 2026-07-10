# Project layout (Phase 1)

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
  runtime/                 # VM, Director, Stage, intents, save
  render/                  # DrawList, pack, text layout, glyph atlas helpers
  audio/                   # Logical mixer + event queue
  std_commands/            # Standard host command table
  host_web/                # Wasm host entry + js_glue (WebGPU/audio/input)
  host_desktop/            # Minimal Tauri 2 shell over dist/demo
  cmd/moonsightc/          # check / build CLI (native)
  demo/game/               # Sample project (authoring source)
  dist/                    # Build output (usually untracked)
  docs/                    # Specs, plans, Phase 1 docs
```

| Package | Role |
|---------|------|
| `script` | Compile MoonYuki → IR/bytecode |
| `runtime` | IR VM, Director, Stage, save JSON |
| `render` | CPU draw list + float pack for JS GPU |
| `audio` | BGM/SE logical mixer |
| `std_commands` | `standard_registry()` host handlers |
| `host_web` | `init_demo` / `export_frame` / save exports |
| `cmd/moonsightc` | Project check & web dist builder |

Dependency direction (high level):

```
script ──► (no render)
runtime ──► script types/IR usage as needed
std_commands ──► runtime (+ audio for bgm/se)
render ──► runtime (intent, stage snapshot inputs)
host_web ──► runtime, render, std_commands, script, audio
moonsightc ──► script (+ native FS)
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
```

Demo: `demo/game/` (same shape). Mini golden fixture:
`script/testdata/mini_game/`.

### `moonsight.json`

Phase 1 pins **JSON** (no TOML dependency).

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `name` | string | `"moonsight"` | Project display name → manifest |
| `entry` | string | `"main.yuki"` | Entry source path relative to project root |
| `logical_width` | number | `1920` | Logical canvas width |
| `logical_height` | number | `1080` | Logical canvas height |

Example (`demo/game/moonsight.json`):

```json
{
  "name": "moonsight-demo",
  "entry": "main.yuki",
  "logical_width": 1920,
  "logical_height": 1080
}
```

`build` fails if `moonsight.json` is missing. Missing entry file warns but still
compiles other `.yuki` files.

### Asset ids

`moonsightc build` walks `assets/` recursively:

- **Images** (png/webp/jpg/…) → `manifest.resources[id] = relative path`
- **Audio** (ogg/mp3/…) → `manifest.audio[id] = relative path`
- **id** = file basename without extension (subdir is **not** part of the id)

Script references use those ids: `@layer.show "bg" "bg_room"`,
`@audio.bgm "bgm_soft"`.

## Build outputs

```bash
export CC=gcc   # moonsightc forces gcc on native
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Typical `dist/demo/`:

| Artifact | Purpose |
|----------|---------|
| `game.msb` | Merged bytecode (`MSB1`) |
| `demo.yuki` | Copy of entry source (host load path today) |
| `manifest.json` | name, logical size, resources, audio maps |
| `assets/**` | Copied media |
| `index.html`, `boot.js`, `webgpu_bridge.js`, `host_web.wasm` | From `host_web/js_glue` |

`manifest.json` shape:

```json
{
  "name": "moonsight-demo",
  "logical_width": 1920,
  "logical_height": 1080,
  "resources": { "bg_room": "assets/bg_room.png", "char_y": "assets/char_y.png" },
  "audio": { "bgm_soft": "assets/bgm_soft.ogg" }
}
```

Ensure `host_web` wasm is built/copied into js_glue when needed:

```bash
moon build --target wasm-gc --release host_web
cp _build/wasm-gc/release/build/host_web/host_web.wasm host_web/js_glue/
```

## Hosts

### Browser (`host_web`)

Serve `dist/demo` (or `host_web/js_glue` after copy) over localhost. WebGPU
requires a secure context. Input and save keys are documented in
[`host-commands.md`](./host-commands.md) (Intent mapping).

### Desktop (`host_desktop`)

Minimal **Tauri 2** shell: same static files as browser (`frontendDist` →
`dist/demo`). See `host_desktop/README.md`. Saves remain webview
`localStorage` in Phase 1.

## CLI

```text
moonsightc version
moonsightc check <file.yuki|dir>
moonsightc build <project_dir> [-o <out_dir>]
```

Via MoonBit:

```bash
moon run cmd/moonsightc --target native -- version
moon run cmd/moonsightc --target native -- check demo/game
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

## Core tests

```bash
moon check
moon test
```

Package tests cover lexer/parser/lower/bytecode, VM/director/stage/save,
render pack, audio mixer, std_commands registry alignment, and host_web
blackbox where applicable.

## Documentation index

| Doc | Content |
|-----|---------|
| [`moon-yuki-subset.md`](./moon-yuki-subset.md) | Grammar subset + examples |
| [`host-commands.md`](./host-commands.md) | Host table, intents, errors |
| [`draw-list-pack.md`](./draw-list-pack.md) | Packed frame format |
| [`project-layout.md`](./project-layout.md) | This file |
| `superpowers/specs/…` | Design spec |
| `superpowers/plans/…` | Implementation plan |

## Explicit non-goals (Phase 1)

Do not expect or document as shipped:

- Visual editor
- Full i18n / achievements
- Live2D or second native GPU backend
- Official YukimiScript bytecode interop
- TOML project config
