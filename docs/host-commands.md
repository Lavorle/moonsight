# Standard host commands (Phase 1)

Host commands are invoked from MoonYuki as `@name …` (or as IR `Host` ops after
dialogue lower). Runtime dispatch lives in `std_commands` via
`standard_registry()` → `Director.register_fn`. Compile-time names live in
`script.builtin_externs()` and **must match** registry keys (enforced by test).

Handlers receive `(Stage, Array[Value])` and return `HostResult`:

| Result | Effect |
|--------|--------|
| `Ok` | Continue VM |
| `Yield` | Suspend until intent (Advance / Select / …) |
| `JumpScene(name)` | VM switches scene, resets IP |
| `Error(msg)` | Soft-halt VM (no panic) |

Logical canvas default: **1920×1080**, origin top-left, +y down.

---

## text

Dialogue is normally produced by the lowerer; these may also be called
explicitly.

### `text.begin [speaker]`

| | |
|--|--|
| **Args** | optional `Str` speaker; empty / `None_` → no speaker |
| **Effect** | `stage.begin_text(speaker=…)` |
| **Errors** | non-string non-none arg → `text.begin: expected speaker Str or None_` |
| **Result** | `Ok` |

### `text.type chunk`

| | |
|--|--|
| **Args** | `Str` chunk (required) |
| **Effect** | Append typewriter chunk via `stage.type_more` |
| **Errors** | missing/non-str → `text.type: expected Str chunk` |
| **Result** | `Ok` |

### `text.end`

| | |
|--|--|
| **Args** | ignored |
| **Effect** | No-op on stage; leaves typewriter incomplete so the engine can reveal chars |
| **Result** | `Ok` |

---

## layer

### `layer.show id resource [z] [x] [y] [opacity]`

| | |
|--|--|
| **Args** | `id: Str`, `resource: Str`, then optional numeric `z`, `x`, `y`, `opacity` |
| **Defaults** | `z=0`, `x=0`, `y=0`, `opacity=1.0`; kind is always **Background** in Phase 1 |
| **Effect** | Show/replace layer by id (`stage.show_layer`) |
| **Notes** | Single-arg form `@layer.show "id"` uses empty resource. Characters are z-ordered only (e.g. `z=10`), not a separate `LayerKind`. |
| **Errors** | missing id/resource (when two-arg form expected) → `layer.show: expected id Str and resource Str` |
| **Result** | `Ok` |

### `layer.hide id`

| | |
|--|--|
| **Args** | `id: Str` |
| **Effect** | Hide layer by id |
| **Errors** | `layer.hide: expected id Str` |
| **Result** | `Ok` |

### `layer.move id x y`

| | |
|--|--|
| **Args** | `id: Str`, `x`/`y` int or float |
| **Effect** | Update layer position if present; **no-op** if missing |
| **Errors** | bad shape/types → `layer.move: expected id Str and x/y numbers` |
| **Result** | `Ok` |

---

## flow

### `flow.jump scene`

| | |
|--|--|
| **Args** | `scene: Str` |
| **Effect** | Returns `JumpScene(scene)`; VM loads that scene’s ops |
| **Errors** | `flow.jump: expected scene Str` |
| **Result** | `JumpScene` |

Unknown scene names fail at VM jump time (empty ops / halt depending on loader).

### `flow.wait [time]`

| | |
|--|--|
| **Args** | optional numeric time (int/float); empty args also allowed |
| **Effect** | Host-level `Yield` (duration reserved for engine frame logic) |
| **Errors** | non-numeric when present → `flow.wait: expected numeric time` |
| **Result** | `Yield` |

### `flow.yield`

| | |
|--|--|
| **Args** | ignored |
| **Effect** | Explicit host yield |
| **Result** | `Yield` |

### `flow.choice …`

**Preferred path:** the lowerer special-cases `@flow.choice` into IR
`Choose(options, result_var)` (not a runtime Host call). Supported source
forms:

```yuki
@flow.choice "Yes" "No" --result c
@flow.choice result="c" "Yes" "No"
@flow.choice "Yes" "No" result=c
```

| | |
|--|--|
| **Options** | Positional `Str` / `Ident` labels |
| **Result var** | `--result name` / `result=…`; default `"_"` |
| **Select** | Intent `Select(n)` stores **Int index** `n` in the result var and resumes |
| **Host stub** | If invoked as Host (tests), string args become choices and handler `Yield`s |

UI rendering of choices is Stage + draw-list; input mapping is in the host
(see Intent section below).

---

## var

### `var.set name value`

| | |
|--|--|
| **Args** | `name: Str`, `value: Value` (any runtime value) |
| **Effect** | `stage.set_var(name, value)` |
| **Errors** | `var.set: expected name Str and value` |
| **Result** | `Ok` |

---

## audio

Logical mixer is `@audio` (`global_mixer`); Stage mirrors `bgm` / `se` ids for
snapshots. JS host drains audio events and drives `HTMLAudioElement`.

### `audio.bgm [resource]`

| | |
|--|--|
| **Args** | `Str` resource id, or `None_` / empty to **stop** |
| **Effect** | Set `stage.bgm`; `play_bgm` / `stop_bgm` on mixer (default volume 1.0, looped) |
| **Errors** | `audio.bgm: expected resource Str or None_` |
| **Result** | `Ok` |

### `audio.se resource`

| | |
|--|--|
| **Args** | `Str` resource id |
| **Effect** | Set `stage.se`; one-shot `play_se` |
| **Errors** | `audio.se: expected resource Str` |
| **Result** | `Ok` |

Resource ids match `manifest.json` `audio` map keys (basename without extension
from `assets/`).

---

## trans

### `trans.fade from to duration` (shorter forms allowed)

| Form | Behavior |
|------|----------|
| `from to duration` | If `duration > 0`, start overlay at `from`, ease toward `to`; else snap to `to` |
| `from to` | Snap overlay to `to` (`duration=0`) |
| `to` | Snap overlay to `to` |

| | |
|--|--|
| **Args** | numbers (int/float) as above |
| **Effect** | Sets `stage.overlay_opacity`, `fade_to`, `fade_duration` |
| **Errors** | type/arity → `trans.fade: expected from/to/duration numbers` (or shorter variants) |
| **Result** | `Ok` |

Overlay is packed as frame **veil_opacity** for the GPU host.

---

## sys

### `sys.save_hint`

| | |
|--|--|
| **Args** | ignored |
| **Effect** | Sets `stage.save_hint = true` (safe save point marker) |
| **Result** | `Ok` |

`Engine::save` consumes the flag (clears it). Browser host stores JSON under
`localStorage` key `moonsight/save/{slot}` via `save_json` / `load_json` wasm
exports. Desktop shell uses the same webview storage in Phase 1.

---

## Name registry (canonical list)

Sorted for the exact-match test:

```
audio.bgm
audio.se
flow.choice
flow.jump
flow.wait
flow.yield
layer.hide
layer.move
layer.show
sys.save_hint
text.begin
text.end
text.type
trans.fade
var.set
```

---

## Intent mapping (host input → engine)

Defined in `render.intent_from_code` / `docs/draw-list-pack.md`, wired by
`host_web/js_glue/boot.js`:

| Code | Intent | Default binding |
|-----:|--------|-----------------|
| 0 | `None` | (no input) |
| 1 | `Advance` | **Click** / pointer on canvas; **Enter**; **Space**; **Z** |
| 2 | `SkipTyping` | **Control** (keydown) |
| 3 | `OpenMenu` | *(no default key in boot.js)* |
| 4 | `ToggleAuto` | **A** |
| 10+n | `Select(n)` | **1**–**9** → Select(0)…Select(8) |

Save/load (not intents): **Ctrl/Cmd+S** save, **Ctrl/Cmd+L** load slot 0.

Engine policy:

- While typing: Advance completes text first; further Advance proceeds past yield.
- On `Choose`: only `Select(n)` (and related) commits the option index.
- Auto mode synthesizes Advance when enabled (`ToggleAuto`).

---

## Draw-list pack

MoonBit packs Stage snapshot floats for JS WebGPU. See
[`draw-list-pack.md`](./draw-list-pack.md) for header layout, sprite/glyph
strides, resource ids, and wasm exports (`export_frame`, `frame_at`, …).
