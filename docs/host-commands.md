# Standard host commands (Phase 1 + Phase 2)

Host commands are invoked from MoonYuki as `@name …` (or as IR `Host` ops after
dialogue lower). Runtime dispatch lives in `std_commands` via
`standard_registry()` → `Director.register_fn`. Compile-time names live in
`script.builtin_externs()` and **must match** registry keys (enforced by test).

Handlers receive `(Stage, Array[Value])` and return `HostResult`:

| Result | Effect |
|--------|--------|
| `Ok` | Continue VM |
| `Yield` | Suspend until intent (Advance / Select / …) or timed wait ends |
| `JumpScene(name)` | VM switches scene, resets IP |
| `Error(msg)` | Soft-halt VM (no panic) |

Logical canvas default: **1920×1080**, origin top-left, +y down.

Named arguments (`kind=background`, `duration=0.5`) are preserved through lower
as marker pairs `Str("#:<name>")` + value. Bare keywords (e.g. `kind=background`)
and quoted strings (`kind="background"`) both work for string-valued names.

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

Layer property animation is **fire-and-forget**: tweens do not block the VM.
Synchronize with `@flow.wait` when the script must pause for presentation.
Ease is **linear**. New tweens replace same-layer same-property tweens
(from current value → new target).

Draw order (bottom → top): `background` → `character` → `effect` → `ui`, then
within each kind by `z` ascending (stable on ties). Fullscreen overlay veil
from `trans.fade` is separate from the layer list.

### `layer.show id resource [z] [x] [y] [opacity]` + named

```yuki
@layer.show "bg" "bg_room" kind=background
@layer.show "y" "char_y" kind=character z=10 x=0 opacity=0
@layer.show "y" "char_y" 10 -200 0 0 kind=character   # negative x via positionals
@layer.show "fx" "spark" kind=effect duration=0.4
```

| | |
|--|--|
| **Args** | `id: Str`, `resource: Str`, optional positional `z`, `x`, `y`, `opacity` |
| **Named** | `kind`, `z`, `x`, `y`, `opacity`, `duration` (named overrides positional when both present) |
| **Defaults** | `kind=character`, `z=0`, `x=0`, `y=0`, `opacity=1.0`, `duration=0` |
| **kind values** | `background` \| `character` \| `effect` \| `ui` (case-insensitive; also accepts `overlay`) |
| **Effect** | Show/replace layer by id |
| **New layer + duration>0** | `kind` / `resource` / `z` / `x` / `y` applied immediately; **opacity starts at 0** and linear-tweens to the target (default `1.0`) |
| **New layer + duration=0** | All properties snap to targets |
| **Existing layer** | `kind` / `resource` / `z` immediate; only specified `x` / `y` / `opacity` tween or snap |
| **Notes** | Single-arg `@layer.show "id"` uses empty resource, default kind `character`. **Backgrounds must set `kind=background`** (Phase 2 default is character). |
| **Errors** | missing id/resource → `layer.show: expected id Str and resource Str`; bad kind → `layer.show: invalid kind` |
| **Result** | `Ok` |

### `layer.set id` + named properties

```yuki
@layer.set "y" x=200 opacity=1.0 duration=0.5
@layer.set "y" y=0 duration=0.2
```

| | |
|--|--|
| **Args** | `id: Str` (positional); named `x`, `y`, `opacity`, optional `duration` |
| **Defaults** | `duration=0` (immediate) |
| **Effect** | Update properties without changing `resource` or `kind`; each specified prop tweens or snaps |
| **Errors** | missing id arg → `layer.set: expected id Str`; unknown id → `layer.set: missing layer id '…'` (**soft-halt**, not silent no-op) |
| **Result** | `Ok` |

### `layer.hide id` + optional duration

```yuki
@layer.hide "y"
@layer.hide "y" duration=0.3
```

| | |
|--|--|
| **Args** | `id: Str`; named optional `duration` |
| **Defaults** | `duration=0` → immediate remove |
| **Effect** | `duration=0`: remove layer now. `duration>0`: `pending_hide`, opacity tweens to 0, then remove |
| **Errors** | `layer.hide: expected id Str` |
| **Result** | `Ok` |

### `layer.move id x y` + optional duration

```yuki
@layer.move "y" 400 0
@layer.move "y" 400 0 duration=0.5
```

| | |
|--|--|
| **Args** | `id: Str`, `x`/`y` int or float; named optional `duration` |
| **Defaults** | `duration=0` (snap) |
| **Effect** | Tween or snap position if layer present; **no-op** if missing (Phase 1 compatibility) |
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

```yuki
@flow.wait 0.5   # timed: wall-clock countdown, auto-resume
@flow.wait       # bare: wait for one Advance
```

| | |
|--|--|
| **Args** | optional numeric time in seconds (int/float); empty args allowed |
| **Timed (`time > 0`)** | Sets `stage.wait_remaining = time`, returns `Yield`; engine ticks wall-clock `dt` until remaining ≤ 0, then resumes from Yield |
| **Bare / zero** | `wait_remaining = 0`; resumes on **Advance** (same as Phase 1 yield) |
| **Input while timed** | **Advance**, **SkipTyping**, and **Select** are **ignored** (wait cannot be skipped) |
| **Errors** | non-numeric when present → `flow.wait: expected numeric time` |
| **Result** | `Yield` |

Does **not** wait for layer tweens or fade by itself — pair with a matching duration
when the script should stay paused for presentation.

### `flow.yield`

| | |
|--|--|
| **Args** | ignored |
| **Effect** | Explicit host yield (wait for Advance / menu flow) |
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

```yuki
@trans.fade 1.0 0.0 0.5
@flow.wait 0.5          # required if script must pause for the fade
```

| Form | Behavior |
|------|----------|
| `from to duration` | If `duration > 0`, start overlay at `from`, linear ease toward `to` over **wall-clock** `duration` seconds (`fade_remaining = duration`); else snap to `to` |
| `from to` | Snap overlay to `to` (`fade_remaining=0`) |
| `to` | Snap overlay to `to` |

| | |
|--|--|
| **Args** | numbers (int/float) as above |
| **Effect** | Sets `stage.overlay_opacity`, `fade_to`, **`fade_remaining`** (seconds left for the whole transition — not a stale rate field) |
| **Notes** | Fire-and-forget; runs in parallel with layer tweens. **Does not** Yield. Phase 2 does **not** provide `trans.dissolve`. |
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
exports. Desktop shell uses the same webview storage.

### Save format (v3)

Writers always emit **format_version 3**. Loaders accept **v2 and v3**.

| Field (v3) | Role |
|------------|------|
| `layers[]` | Current geometry + `tweens` (`prop`, `to`, `remaining`) + `pending_hide` |
| `overlay_opacity`, `fade_to`, **`fade_remaining`** | Overlay fade mid-state (wall-clock seconds left) |
| `wait_remaining` | Timed `@flow.wait` countdown left |
| `wait`, `choices`, `choose_result_var`, `auto` | VM / UI wait state (from v2) |

- Mid-tween / mid-fade / mid-wait save → load continues with remaining times.
- v2 loads: layers without tweens; `kind` defaults as stored (missing → character semantics where applicable); no tween restore.
- Unknown higher versions are rejected with a clear error.

---

## Name registry (canonical list)

Sorted for the exact-match test (`standard_host_names` / `builtin_externs`):

```
audio.bgm
audio.se
flow.choice
flow.jump
flow.jump_if
flow.jump_if_not
flow.wait
flow.yield
layer.hide
layer.move
layer.set
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

| State | Advance | Select | SkipTyping |
|-------|---------|--------|------------|
| Dialogue typewriter | Completes text first; further Advance past yield | — | Completes typing |
| Timed `@flow.wait` (`wait_remaining > 0`) | **Ignored** | **Ignored** | **Ignored** |
| Bare `@flow.wait` / `flow.yield` | Resume | — | — |
| `Choose` | — | Commits option index | — |
| Layer tween / overlay fade only (VM Running) | Not gated | Not gated | Not gated |

Auto mode synthesizes Advance when enabled (`ToggleAuto`), subject to the same
timed-wait gate.

---

## Resource diagnostics (Phase 2)

| Stage | Behavior |
|-------|----------|
| `moonsightc build` | Literal resource strings in scripts must exist in the project manifest / assets; missing → **build failure** |
| Runtime texture fetch | Hard-fail with a readable host error (no silent empty sprites) |

Dynamic / non-literal resource ids are not fully checked at build time.

---

## Draw-list pack

MoonBit packs Stage snapshot floats for JS WebGPU. See
[`draw-list-pack.md`](./draw-list-pack.md) for header layout, sprite/glyph
strides, resource ids, and wasm exports (`export_frame`, `frame_at`, …).
