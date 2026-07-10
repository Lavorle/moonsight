# Standard host commands (Phase 1–4)

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

Named arguments (`kind=background`, `duration=0.5`, `x=-200`) are preserved
through lower as marker pairs `Str("#:<name>")` + value. Bare keywords
(`kind=background`) and quoted strings both work for string-valued names.
**Named negatives** (`x=-200`, `y=-1.5`) are supported by the lexer.

System UI and dialogue HUD are **MoonBit** trees on `UiApp` (`std_ui` + optional
`ui_package`) — see [`ui-moonbit.md`](./ui-moonbit.md). Narrative scripts still
open/close modals with `@ui.show` / `@ui.hide`. Project `- screen` is rejected.

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
from `trans.fade` is separate from the layer list. HUD and modal widgets paint
via `UiDrawOp` above layers (with optional menu dim); see
[`ui-moonbit.md`](./ui-moonbit.md).

### `layer.show id resource [z] [x] [y] [opacity]` + named

```yuki
@layer.show "bg" "bg_room" kind=background
@layer.show "y" "char_y" kind=character z=10 x=-200 y=0 opacity=0
@layer.show "y" "char_y" 10 -200 0 0 kind=character   # negatives via positionals also ok
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
| **Notes** | Single-arg `@layer.show "id"` uses empty resource, default kind `character`. **Backgrounds must set `kind=background`** (default is character). Re-show without `kind` keeps character default. |
| **Errors** | missing id/resource → `layer.show: expected id Str and resource Str`; bad kind → `layer.show: invalid kind` |
| **Result** | `Ok` |

### `layer.set id` + named properties

```yuki
@layer.set "y" x=200 opacity=1.0 duration=0.5
@layer.set "y" y=0 duration=0.2
@layer.set "y" x=-100 duration=0.3
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
| **Modal open** | Menu input wins; wait countdown continues in background; Advance still ignored for narrative until menu closes |
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

Choice UI is the HUD `ChoiceList` node (`std_ui`); input mapping is in the host
(see Intent section below). Layout is overridable via `set_hud` /
[`ui-moonbit.md`](./ui-moonbit.md).

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

### `audio.bgm [resource]` + named `volume` / `fade`

```yuki
@audio.bgm "bgm_soft"
@audio.bgm "bgm_soft" volume=0.8
@audio.bgm "bgm_soft" volume=0.8 fade=1.0
@audio.bgm none               # stop; optional fade= for fade-out
@audio.bgm "bgm_soft" fade=0.5
```

| | |
|--|--|
| **Args** | `Str` resource id, or `None_` / empty / `none` to **stop** |
| **Named** | `volume` (default `1.0` logical gain), `fade` (default `0` seconds, linear wall-clock) |
| **Effect** | Set `stage.bgm`; play/stop on mixer. Same track + fade only adjusts volume; new track can fade in from silence. Stop with `fade>0` fades out then stops. |
| **Output** | Host multiplies logical × prefs `master_volume` × `bgm_volume` |
| **Errors** | `audio.bgm: expected resource Str or None_` |
| **Result** | `Ok` |

### `audio.se resource`

| | |
|--|--|
| **Args** | `Str` resource id |
| **Effect** | Set `stage.se`; one-shot `play_se` (× master × se prefs). **No SE fade.** |
| **Errors** | `audio.se: expected resource Str` |
| **Result** | `Ok` |

Resource ids match `manifest.json` `audio` map keys (basename without extension
from `assets/`).

### Audio hard-fail (Phase 3)

| Stage | Behavior |
|-------|----------|
| `moonsightc build` | Literal audio ids in scripts must exist in project assets; missing → **build failure** |
| Runtime fetch | Failed load → readable host error (`audio load failed: {id}`); **not** silent / warn-only |

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
| **Notes** | Fire-and-forget; runs in parallel with layer tweens. **Does not** Yield. No `trans.dissolve`. |
| **Errors** | type/arity → `trans.fade: expected from/to/duration numbers` (or shorter variants) |
| **Result** | `Ok` |

Overlay is packed as frame **veil_opacity** for the GPU host.

---

## ui (Phase 3–4)

Modals are registered in MoonBit (`std_ui` / project `ui_package`) — see
[`ui-moonbit.md`](./ui-moonbit.md). These host commands only **queue** stack ops
on `Stage`; the Engine drains them onto `UiRuntime` (`show_modal` / `hide_modal`).

`@ui.show` / `@ui.hide` remain the narrative bridge; they do **not** define widget trees.

### `ui.show name [mode=save|load]`

```yuki
@ui.show "game_menu"
@ui.show "save_load" mode=load
@ui.show "save_load" mode=save
```

| | |
|--|--|
| **Args** | `name: Str`; optional named `mode` (`save` \| `load`) for dual-purpose modals |
| **Effect** | Queue push modal; Engine shows modal and yields so narrative IP freezes while open |
| **Errors** | missing/non-str name → `ui.show: expected name Str` |
| **Result** | `Yield` (typical) |

### `ui.hide [name]`

```yuki
@ui.hide
@ui.hide "settings"
```

| | |
|--|--|
| **Args** | optional `Str` name |
| **Effect** | Queue pop top modal, or remove matching name when given |
| **Errors** | bad arg type → `ui.hide: expected optional name Str` |
| **Result** | `Ok` |

`OpenMenu` Intent (Esc) while Playing with empty stack ≡ show `game_menu`.
While a modal is open, Esc pops one layer (`return_modal`).

---

## sys

### `sys.save_hint`

| | |
|--|--|
| **Args** | ignored |
| **Effect** | Sets `stage.save_hint = true` (safe save point marker) |
| **Result** | `Ok` |

`Engine::save` consumes the flag (clears it). Browser host stores narrative JSON
under `localStorage` key `moonsight/save/{slot}` (multi-slot). Desktop shell uses
the same webview storage.

### Save format (v3)

Writers always emit **format_version 3**. Loaders accept **v2 and v3**.

| Field (v3) | Role |
|------------|------|
| `layers[]` | Current geometry + `tweens` (`prop`, `to`, `remaining`) + `pending_hide` |
| `overlay_opacity`, `fade_to`, **`fade_remaining`** | Overlay fade mid-state (wall-clock seconds left) |
| `wait_remaining` | Timed `@flow.wait` countdown left |
| `wait`, `choices`, `choose_result_var`, `auto` | VM / UI wait state (from v2) |
| audio block | BGM id + logical volume / fade mid-state where applicable |

- Mid-tween / mid-fade / mid-wait save → load continues with remaining times.
- v2 loads: layers without tweens; `kind` defaults as stored (missing → character semantics where applicable); no tween restore.
- Unknown higher versions are rejected with a clear error.
- **UI modal stack / HUD focus are not saved.** **Prefs are not part of slot saves.**

### Multi-slot + prefs (Phase 3+)

| Item | Detail |
|------|--------|
| Slot keys | `moonsight/save/{slot}` (`slot` int, default N=6) |
| Prefs key | `moonsight/prefs` (JSON object) |
| Prefs fields | `text_speed`, `auto_mode`, `master_volume`, `bgm_volume`, `se_volume` |
| Quick keys | Ctrl/Cmd+S / Ctrl/Cmd+L → **slot 0** |
| `save_slots` | `moonsight.json` optional field (default 6, clamp 1..20); also in `manifest.json` |

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
ui.hide
ui.show
var.set
```

---

## Intent mapping (host input → engine)

Defined in `render.intent_from_code` / `docs/draw-list-pack.md`, wired by
`host_web/js_glue/boot.js`:

| Code | Intent | Default binding |
|-----:|--------|-----------------|
| 0 | `None` | (no input) |
| 1 | `Advance` | **Click** / pointer on canvas; **Enter**; **Space**; **Z** (on modals/HUD = activate focused button) |
| 2 | `SkipTyping` | reserved one-shot; host uses Ctrl **hold** → `skip_held` instead |
| 3 | `OpenMenu` | **Esc** — Playing + empty stack → `game_menu`; modal open → pop one layer |
| 4 | `ToggleAuto` | **A** (also writes prefs.`auto_mode`) |
| 5 | `MenuUp` | **↑** / **W** — previous focusable on modal/HUD |
| 6 | `MenuDown` | **↓** / **S** — next focusable (plain S; Ctrl+S is quick-save) |
| 7 | `MenuLeft` | **←** — focused slider step down |
| 8 | `MenuRight` | **→** — focused slider step up |
| 9 | `OpenBacklog` | **H** — Playing + empty stack → backlog modal |
| 10+n | `Select(n)` | **1**–**9** → Select(0)…Select(8) |

**Ctrl hold** (not an intent code): each frame passes `skip_held=1` into
`export_frame` for burst advance while held (does not skip timed waits or
auto-select choices).

Save/load (not intents): **Ctrl/Cmd+S** save, **Ctrl/Cmd+L** load **slot 0**.

Engine policy:

| State | Advance | Select | SkipTyping | Menu intents |
|-------|---------|--------|------------|--------------|
| Dialogue typewriter | Completes text first; further Advance past yield | — | Completes typing | OpenMenu opens menu |
| Timed `@flow.wait` (`wait_remaining > 0`) | **Ignored** | **Ignored** | **Ignored** | OpenMenu allowed |
| Bare `@flow.wait` / `flow.yield` | Resume | — | — | OpenMenu allowed |
| `Choose` | — | Commits option index | — | OpenMenu allowed |
| Modal open | Activate focused button | optional direct activate | — | MenuUp/Down move focus; Esc = return |
| `Title` | Activate button | — | — | focus navigation |
| Layer tween / overlay fade only (VM Running) | Not gated | Not gated | Not gated | OpenMenu allowed |

Auto mode synthesizes Advance when enabled (`ToggleAuto`), subject to the same
timed-wait gate and modal freeze.

---

## Resource diagnostics

| Stage | Behavior |
|-------|----------|
| `moonsightc build` | Literal image/audio resource strings in scripts must exist in the project manifest / assets; missing → **build failure** (failed builds do not leave a broken `out_dir`) |
| Runtime texture fetch | Hard-fail with a readable host error (no silent empty sprites) |
| Runtime audio fetch | Hard-fail with `audio load failed: {id}` |

Dynamic / non-literal resource ids are not fully checked at build time.

---

## Draw-list pack

MoonBit packs Stage + screen widgets for JS WebGPU. See
[`draw-list-pack.md`](./draw-list-pack.md) for header layout, sprite/glyph
strides, intent codes (incl. MenuUp/Down), and wasm exports.
