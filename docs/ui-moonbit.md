# MoonBit UI authoring (Phase 4)

Author-facing guide for the **retained MoonBit UI kernel**: system menus and
narrative HUD are both `UiNode` trees registered on a `UiApp`, painted via
`UiDrawOp`, and driven by closed **Capabilities** callbacks.

See also: [`host-commands.md`](./host-commands.md) (`@ui.*`, intents, prefs),
[`project-layout.md`](./project-layout.md) (`ui_package`, build),
[`moon-yuki-subset.md`](./moon-yuki-subset.md) (narrative-only grammar).

> **Migration:** Project `- screen` / `screens.json` were removed in Phase 4.
> The old guide is archived at [`screen-language.md`](./screen-language.md).

## Dual surface model

```
Cold start → Title modal (`title`)
  Start → start_game → Playing
  Playing → base HUD (dialogue + choices)
  Esc  → OpenMenu → push `game_menu` (modal stack)
  stack empty → Playing again (HUD only)
  Title action → quit_to_title
```

| Surface | Role |
|---------|------|
| **HUD** (`set_hud`) | Base chrome while Playing: dialogue box, nameplate, body text, choice list. Not a modal. |
| **Modal stack** (`register_modal`) | Title, game menu, save/load, settings, and any custom named modals. Stack top receives input. |

| `UiMode` | Meaning |
|----------|---------|
| `Title` | Cold start / after quit; title modal typically on stack |
| `Playing` | Narrative VM runs; HUD binds to Stage text/choices when no modal |
| `Menu` | Modal stack non-empty; narrative Advance ignored; focus on stack top |

**Input gate:** modal non-empty → only stack top; otherwise Playing narrative
intents + HUD (e.g. choice focus). Esc while Playing with empty stack ≡
`show_modal("game_menu")`; Esc while a modal is open pops one layer.

**Save:** narrative save **v3** + separate prefs. UI stack and focus are **not**
serialized into slots.

## Registration API

Hosts build one `UiApp`, install standard UI, then optional project overrides:

```mbt
let app = @runtime.UiApp::new()
@std_ui.register(app)       // default HUD + four modals
@project_ui.register(app)   // optional game package (after std)
// Engine::from_ir(..., app~)
```

### `std_ui.register` / project `register`

```mbt
/// Install default HUD and title / game_menu / save_load / settings.
pub fn register(app : @runtime.UiApp) -> Unit {
  app.set_hud(build_hud(app))
  app.register_modal("title", build_title(app))
  app.register_modal("game_menu", build_game_menu(app))
  app.register_modal("save_load", build_save_load(app))
  app.register_modal("settings", build_settings(app))
}
```

Project packages export the same entry point and run **after** `std_ui`, so
`register_modal` / `set_hud` **replace** earlier registrations by name / slot.

### `UiApp::set_hud`

Replace the base HUD tree (dialogue + choice chrome).

```mbt
app.set_hud(
  @runtime.UiNode::Fixed(
    x=0.0,
    y=0.0,
    w=Some(1920.0),
    h=Some(1080.0),
    children=[/* Panel / Text / ChoiceList … */],
  ),
)
```

### `UiApp::register_modal`

Register or replace a named modal root. Names used by the engine / scripts:

| Name | Default role (`std_ui`) |
|------|-------------------------|
| `title` | Start / Load / Settings |
| `game_menu` | Continue / Save / Load / Settings / Title (Esc) |
| `save_load` | Six slots; `mode` save vs load; Back |
| `settings` | Prefs adjusters; Back |

```mbt
app.register_modal(
  "title",
  @runtime.UiNode::VBox(
    x=Some(760.0),
    y=Some(360.0),
    children=[
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Literal("My Game"),
        x=0.0,
        y=0.0,
        font_size=36.0,
        visible=@runtime.VisiblePred::Always,
      ),
      app.button("Start", fn(c : &@runtime.Capabilities) { c.start_game() }),
    ],
  ),
)
```

### Buttons and handlers

`UiNode::Button` holds an **`action_id`**, not a free-form string. Prefer
`app.button(label, handler)` which allocates an id and stores
`(caps : &Capabilities) -> Unit`.

```mbt
app.button("Settings", fn(c : &@runtime.Capabilities) {
  c.show_modal("settings", mode=None)
})
```

Handlers must only call **Capabilities** (no direct VM / Stage internals).

## Capabilities

Closed host surface for UI actions (engine implements; tests can fake):

| Method | Effect |
|--------|--------|
| `start_game()` | Clear stack, load entry scene, Playing |
| `quit_to_title()` | Tear down narrative, Title + `title` when registered |
| `show_modal(name, mode~)` | Push modal; optional mode (e.g. `"save"` / `"load"`) |
| `return_modal()` | Pop one modal |
| `hide_modal(name~)` | Pop top, or remove matching name when given |
| `save_slot(i)` / `load_slot(i)` | Multi-slot narrative save |
| `slot_occupied(i)` / `slot_label(i)` | Slot occupancy helpers |
| `set_pref_f` / `set_pref_b` / `adjust_pref` | Prefs write + clamp |
| `confirm_choice(i)` / `advance()` | Narrative choice / advance |
| `prefs()` | Read current prefs |

No open host-string actions and no general expression language on the tree.

## Widget MVP

| Node | Role |
|------|------|
| `VBox` / `HBox` | Flow layout; optional absolute origin `x` / `y` |
| `Fixed` | Absolute region with optional `w` / `h` |
| `Spacer` | Empty space in flow |
| `Panel` | Sprite / chrome resource rect + `visible` |
| `Text` | Label from `TextBindSrc` + `visible` |
| `Image` | Resource sprite + `visible` |
| `Button` | Focusable; `action_id` → handler |
| `ChoiceList` | Expands Stage choices into focusable rows |

Logical canvas default: **1920×1080**, origin top-left, +y down.

**Out of scope (Phase 4):** sliders, scroll views, themes, transform animation
stack, DOM / HTML menus, backlog, slot screenshots.

## TextBind / VisibleIf

### `TextBindSrc`

| Variant | Resolves to |
|---------|-------------|
| `Literal(s)` | Fixed string |
| `DialogueName` | Current speaker / nameplate |
| `DialogueBody` | Typewriter / dialogue body |
| `Pref(key)` | Live prefs display (`text_speed`, `auto_mode`, volumes, …) |
| `SlotLabel(i)` | Slot label (empty vs occupied styling) |
| `Var(name)` | Stringified narrative var (missing → `""`) |

```mbt
@runtime.UiNode::Text(
  src=@runtime.TextBindSrc::DialogueBody,
  x=80.0,
  y=848.0,
  font_size=32.0,
  visible=@runtime.VisiblePred::HasText,
)
```

### `VisiblePred` (VisibleIf)

| Variant | True when |
|---------|-----------|
| `Always` / `Never` | Constant |
| `HasText` | Stage has active dialogue text |
| `HasChoices` | Stage has open choices |
| `PrefBool(key)` | Boolean pref (e.g. `auto_mode`) |
| `SlotOccupied(i)` | Save slot `i` has data |
| `ModeIs(m)` | Current modal instance `mode` equals `m` |
| `And(a, b)` | Short-circuit conjunction |

Load-mode slots typically use **`And(ModeIs("load"), SlotOccupied(i))`** so empty
slots are not focusable; save mode uses `ModeIs("save")` alone.

```mbt
@runtime.UiNode::Button(
  label="Slot \{slot}",
  action_id=load_id,
  visible=@runtime.VisiblePred::And(
    @runtime.VisiblePred::ModeIs("load"),
    @runtime.VisiblePred::SlotOccupied(slot),
  ),
)
```

## `ui_package` in `moonsight.json`

```json
{
  "name": "moonsight-demo",
  "entry": "main.yuki",
  "logical_width": 1920,
  "logical_height": 1080,
  "ui_package": "ui"
}
```

| Field | Meaning |
|-------|---------|
| `ui_package` | Optional path **relative to the project root** of a directory of `.mbt` sources |

At `moonsightc build`:

1. Sources are copied into `host_web/project_ui/` (engine overlay).
2. `host_web` is rebuilt (`wasm-gc` release) so the package is in the binary.
3. The committed **no-op stub** is restored so the working tree stays clean.

The package must export:

```mbt
pub fn register(app : @runtime.UiApp) -> Unit { … }
```

Only `*.mbt` files are linked; `moon.pkg` is rewritten to import
`moonsight/moonsight/runtime` (not a separate Moon module).

Omit `ui_package` to ship **std_ui only** (demo default without override).

### Minimal override example

`demo/game/ui/lib.mbt` (when `ui_package: "ui"`):

```mbt
///|
/// Demo project UI: re-register title with a custom label after std_ui.
pub fn register(app : @runtime.UiApp) -> Unit {
  app.register_modal(
    "title",
    @runtime.UiNode::VBox(
      x=Some(760.0),
      y=Some(360.0),
      children=[
        @runtime.UiNode::Text(
          src=@runtime.TextBindSrc::Literal("MoonSight Demo"),
          x=0.0,
          y=0.0,
          font_size=36.0,
          visible=@runtime.VisiblePred::Always,
        ),
        app.button("Start", fn(c : &@runtime.Capabilities) { c.start_game() }),
        app.button(
          "Load",
          fn(c : &@runtime.Capabilities) {
            c.show_modal("save_load", mode=Some("load"))
          },
        ),
        app.button(
          "Settings",
          fn(c : &@runtime.Capabilities) {
            c.show_modal("settings", mode=None)
          },
        ),
      ],
    ),
  )
}
```

## Migration from `- screen`

| Phase 3 | Phase 4 |
|---------|---------|
| `- screen "name"` in `.yuki` | **Compile error** — define UI in MoonBit |
| `screens.json` dist primary | Removed; UI is linked into `host_web.wasm` |
| `std_screens/*.yuki` | `std_ui` package (`register`) |
| `ScreenAction` enum strings | `Capabilities` + `app.button` handlers |
| Project screen name override | `register_modal` after `std_ui.register` |
| Hard-coded dialogue `UiLayout` | HUD tree via `set_hud` |

Parser diagnostic (excerpt):

```text
`- screen` was removed in Phase 4; define UI in a MoonBit ui package
(see docs/ui-moonbit.md)
```

Steps:

1. Map each `- screen` tree to `UiNode` constructors in a project UI package.
2. Replace `action=…` with `app.button` / `alloc_action` + Capabilities.
3. Set `"ui_package": "ui"` (or your path) in `moonsight.json` if you need
   overrides; otherwise rely on `std_ui`.
4. Remove any leftover `screens.json` expectations from custom hosts.

## Narrative bridge: `@ui.show` / `@ui.hide`

Still valid in MoonYuki; they **queue** `UiHostOp` on Stage and Engine drains
them onto the modal stack (`show_modal` / `hide_modal`).

```yuki
@ui.show "game_menu"
@ui.show "save_load" mode=load
@ui.hide
@ui.hide "settings"
```

| Command | Result | Notes |
|---------|--------|-------|
| `@ui.show name [mode=…]` | `Yield` | Push named modal; narrative pauses while stack non-empty |
| `@ui.hide` | `Ok` | Pop top |
| `@ui.hide "name"` | `Ok` | Remove matching name if present |

Modal **names** must match `register_modal` keys (std or project). Scripts do
not define widget trees.

## Input defaults (host)

| Input | Effect |
|-------|--------|
| Esc | `OpenMenu` — Playing empty stack → `game_menu`; modal open → pop |
| Enter / Space / Z / click | `Advance` — activate focused button on modals/HUD |
| ↑ / W · ↓ / S | Menu focus up / down |
| 1–9 | `Select(n)` choices while Playing |
| A | Toggle auto (prefs.`auto_mode`) |
| Ctrl/Cmd+S / L | Quick save / load **slot 0** |

## Author checklist

1. Prefer `std_ui` defaults; override only the modals/HUD you need.
2. Handlers call **Capabilities** only; keep trees data-like (`action_id`).
3. Use `@ui.show` / `@ui.hide` for scripted menus; Esc still opens `game_menu`.
4. Gate load-slot buttons with `And(ModeIs("load"), SlotOccupied(i))`.
5. Pair presentation with `@flow.wait` as in Phase 2; menus pause narrative.
6. Cold start needs a registered `title` modal (`std_ui` provides one).
