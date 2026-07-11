# MoonBit UI authoring (Phase 4)

Author-facing guide for the **retained MoonBit UI kernel**: system menus and
narrative HUD are both `UiNode` trees registered on a `UiApp`, painted via
`UiDrawOp`, and driven by closed **Capabilities** callbacks.

See also: [`host-commands.md`](./host-commands.md) (`@ui.*`, intents, prefs),
[`play-input.md`](./play-input.md) (keys, skip, backlog, confirm),
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
  game_menu Title → request_quit_to_title → confirm → quit_to_title
```

| Surface | Role |
|---------|------|
| **HUD** (`set_hud`) | Base chrome while Playing: dialogue box, nameplate, body text, choice list. Not a modal. |
| **Modal stack** (`register_modal`) | Title, game menu, save/load, settings, confirm, backlog, and any custom named modals. Stack top receives input. |

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
@std_ui.register(app)       // default HUD + six modals
@project_ui.register(app)   // optional game package (after std)
// Engine::from_ir(..., app~)
```

### `std_ui.register` / project `register`

```mbt
/// Install default HUD and title / game_menu / save_load / settings /
/// confirm / backlog.
pub fn register(app : @runtime.UiApp) -> Unit {
  app.set_hud(build_hud(app))
  app.register_modal("title", build_title(app))
  app.register_modal("game_menu", build_game_menu(app))
  app.register_modal("save_load", build_save_load(app))
  app.register_modal("settings", build_settings(app))
  app.register_modal("confirm", build_confirm(app))
  app.register_modal("backlog", build_backlog(app))
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
| `game_menu` | Continue / History / Save / Load / Settings / Title (Esc) |
| `save_load` | Six slots; `mode` save vs load; labels include `saved_at` when present; Back |
| `settings` | Pref sliders (←/→); Back |
| `backlog` | Session dialogue history (read-only); H or History |
| `confirm` | Overwrite save / quit to title (default focus No) |

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
| `confirm_yes()` / `confirm_no()` | Resolve pending overwrite / quit confirm |
| `request_quit_to_title()` | Show confirm before `quit_to_title` |

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
| `Slider` | Horizontal pref control; `MenuLeft`/`MenuRight` step value |
| `ScrollView` | Vertical viewport + clip; runtime owns `scroll_y` |

Logical canvas default: **1920×1080**, origin top-left, +y down.

### `UiNode::ScrollView`

Vertical scroll viewport. Children are laid out from the top of the content
area; paint and hit-test **clip** to the viewport. Scroll state lives on
`UiRuntime` (one active ScrollView metrics set for the top modal):

| Field / rule | Detail |
|--------------|--------|
| Geometry | `x`, `y`, `w`, `h` — viewport in logical px |
| `scroll_y` | Offset into content; **not saved** (cleared with modal stack) |
| Clamp | `[0, max(0, content_h - vp_h)]` |
| Scrollbar | Right edge strip (`ui.scroll_track` / `ui.scroll_thumb`) when content overflows |
| Wheel | Over viewport: `dy > 0` → `scroll_y` decreases (older content) |
| Drag | Content pan (pointer y↑ → older); thumb/track drag maps y → scroll |
| Keyboard | Engine maps MenuUp/Down to ±`ui_scroll_line_h` (64) when backlog is top |

```mbt
@runtime.UiNode::ScrollView(
  x=360.0,
  y=150.0,
  w=1200.0,
  h=780.0,
  children=[
    @runtime.UiNode::VBox(x=None, y=None, children=line_nodes),
  ],
)
```

**Q3 consumer:** `std_ui` backlog modal only (up to 100 `BacklogLine` rows;
Close sits **outside** the ScrollView so it stays focusable). Opening
`"backlog"` pins scroll to the newest line (bottom).

**Out of scope (not implemented):** horizontal / nested ScrollView, inertia
fling, rubber-band overscroll, multi-touch, runtime theme switcher /
multi-theme store, transform animation stack, DOM / HTML menus, real slot
screenshots (icons only), saving backlog into slots. Default **Amber Soft**
theme pack is in (see Themes). Play-input / pointer / wheel / backlog /
confirm: [`play-input.md`](./play-input.md).

## Themes

UI paint emits **stable logical role** resource ids. The host resolves each id
to a solid color and optional PNG; authors do not hard-code file paths in
`UiNode` trees.

### Logical roles

| Role | Use |
|------|-----|
| `ui.dialogue_box` | Dialogue panel chrome |
| `ui.nameplate` | Speaker nameplate |
| `ui.choice_row` | Choice row idle |
| `ui.choice_row_focus` | Choice row focused |
| `ui.choice_row_hover` | Choice row hovered (not focused) |
| `ui.button` | Button idle |
| `ui.button_focus` | Button focused |
| `ui.button_hover` | Button hovered (not focused) |
| `ui.menu_dim` | Modal full-screen dim |
| `ui.slider_track` | Settings slider track |
| `ui.slider_fill` | Settings slider fill |
| `ui.scroll_track` | ScrollView scrollbar track |
| `ui.scroll_thumb` | ScrollView scrollbar thumb |
| `ui.slot_empty` | Save/load empty-slot icon |
| `ui.slot_filled` | Save/load occupied-slot icon |

### Focused / hovered paint

For Button and Choice rows (same priority):

1. **Focused** → `*_focus` resource (+ higher opacity)
2. Else **hovered** → `*_hover` resource
3. Else idle

`UiDrawOp` carries `focused` and `hovered` flags. Focus wins over hover (hover
is suppressed on the focused index). Sliders tint track/fill opacity by focus /
hover; fill width follows the pref value. Host cursor uses `export_pointer`
`hover_kind` (1 button, 2 choice → `pointer`; 3 slider → `ew-resize`).

### Amber Soft pack

Default theme path (Svelte host public + build dist):

```text
themes/amber_soft/
  theme.json
  dialogue_box.png
  nameplate.png
  choice_row.png
  choice_row_focus.png
  choice_row_hover.png
  button.png
  button_focus.png
  button_hover.png
  menu_dim.png
  slider_track.png
  slider_fill.png
  scroll_track.png
  scroll_thumb.png
  slot_empty.png
  slot_filled.png
```

Authoritative sources:

- Pack: `apps/host-web/public/themes/amber_soft/`
- Loader: `apps/host-web/src/lib/theme.ts` (`loadTheme`)
- Generator: `apps/host-web/scripts/gen-amber-soft-theme.mjs`

`theme.json` lists `fallback_solids` (RGBA) and optional `roles[role].file`
PNGs. Host registers solids first, then tries each file; failed images keep the
solid. (Archived vanilla `archive/js_glue` kept Amber Soft solids only.) Demo
`moonsight.json` may set `"theme": "amber_soft"` as a project hint; the host
loads `/themes/amber_soft` by default.

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
| `BacklogLine(i)` | Preformatted backlog line; `i` = 0..capacity−1 of the bound window (oldest first; empty → `""`) |

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
| `Not(p)` | Negation (e.g. empty-slot icons with `Not(SlotOccupied(i))`) |

Load-mode slots typically use **`And(ModeIs("load"), SlotOccupied(i))`** so empty
slots are not focusable; save mode uses `ModeIs("save")` alone. Slot icons use
`ui.slot_empty` / `ui.slot_filled` with `Not(SlotOccupied)` / `SlotOccupied`.

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
| Enter / Space / Z | `Advance` — activate focused button on modals/HUD |
| Click (canvas) | `export_pointer` hit-test; empty Playing → Advance (not a frame intent) |
| Move / up / leave | Hover + drag update; phase **2** up ends scroll drag; leave clears hover |
| Wheel | `export_wheel` — scroll top-modal ScrollView when over viewport |
| ↑ / W · ↓ / S | Menu focus up / down; **backlog top** → scroll ± one line step |
| 1–9 | `Select(n)` choices while Playing |
| A | Toggle auto (prefs.`auto_mode`) |
| Ctrl/Cmd+S / L | Quick save / load **slot 0** |

Pointer / wheel details and same-frame `export_frame(0, …)` rule:
[`play-input.md`](./play-input.md#pointer).

## Author checklist

1. Prefer `std_ui` defaults; override only the modals/HUD you need.
2. Handlers call **Capabilities** only; keep trees data-like (`action_id`).
3. Use `@ui.show` / `@ui.hide` for scripted menus; Esc still opens `game_menu`.
4. Gate load-slot buttons with `And(ModeIs("load"), SlotOccupied(i))`.
5. Pair presentation with `@flow.wait` as in Phase 2; menus pause narrative.
6. Cold start needs a registered `title` modal (`std_ui` provides one).
