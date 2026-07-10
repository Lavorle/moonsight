# Screen language (Phase 3)

Author-facing guide for the **Screen DSL**: modal system UI (title, menu,
save/load, settings) authored in `.yuki` and rendered via the same WebGPU
draw list as the narrative. Screens do **not** enter the narrative VM.

See also: [`host-commands.md`](./host-commands.md) (`@ui.*`, intents, prefs),
[`moon-yuki-subset.md`](./moon-yuki-subset.md) (grammar),
[`project-layout.md`](./project-layout.md) (std merge + `screens.json`).

## Quick model

```
Cold start → Title (std `title` screen)
  Start → start_game → Playing (entry scene)
  Esc  → OpenMenu → game_menu (modal stack)
  stack empty → Playing again
  Title action → quit_to_title
```

| `UiMode` | Meaning |
|----------|---------|
| `Title` | Cold start / after quit; narrative VM not advancing into play |
| `Playing` | Narrative VM runs; no modal (unless script `@ui.show`) |
| `Menu` | Modal screen stack non-empty; narrative Advance ignored |

**In scope:** `vbox` / `hbox` / `fixed` / `text` / `button`, closed **action**
enum, 6 save slots (configurable), prefs, keyboard focus, full WebGPU widgets.

**Out of scope (non-goals):** backlog / history, dialogue or choice
screen-ization (still hard-coded `UiLayout`), confirm dialogs, slot screenshots,
DOM menus, `if` / expressions / `image` / sliders / themes.

## Syntax

Top-level (alongside `- scene` / `- macro` / `- extern`):

```yuki
- screen "name"
  vbox x=760 y=360:
    text "MoonSight"
    button "Start" action=start_game
    button "Load" action=show_screen("save_load", mode=load)
    button "Settings" action=show_screen("settings")
```

- Indentation: **2 spaces** for parent/child.
- Names are global across the project + std merge (duplicate name → project
  wins over `std_screens/`; two project screens with the same name → error).
- Screens compile to `ScreenDef` IR and ship as **`screens.json`** next to
  `game.msb` (not as narrative bytecode scenes).

### Nodes

| Node | Form | Notes |
|------|------|-------|
| `vbox` | `vbox:` or `vbox x=… y=…:` | Vertical flow of children |
| `hbox` | same | Horizontal flow |
| `fixed` | `fixed x= y= [w= h=]:` | Absolute-ish region container |
| `text` | `text "…"` / bindings | Non-focusable label |
| `button` | `button "Label" action=…` | Focusable; Activate runs action |

Flow children ignore their own x/y (use `fixed` for absolute placement).
Root defaults to the logical canvas (1920×1080). Named numeric args accept
negatives (`x=-40`).

### Text bindings

| Form | Meaning |
|------|---------|
| `text "Settings"` | Literal |
| `text slot_label(0)` | Empty → `"Empty"`; occupied → scene · time style label |
| `text pref("master_volume")` | Live prefs value (read-only display) |

No general expressions.

### Actions (closed set)

| Action | Effect |
|--------|--------|
| `return` | Pop one modal |
| `start_game` | Clear stack, load entry scene, `Playing` |
| `quit_to_title` | Tear down narrative, `Title` + `title` when defined |
| `show_screen("name")` | Push modal; optional `mode=save` \| `mode=load` |
| `hide_screen` / `hide_screen("name")` | Pop top or remove matching name |
| `save_slot(i)` | Write slot `i` (in `mode=load`, runtime treats as load) |
| `load_slot(i)` | Load slot `i` → Playing, clear stack |
| `set_pref("key", value)` | Literal prefs write + clamp |
| `adjust_pref("key", delta)` | Relative step + clamp |
| `noop` | No-op |

Unknown actions / bad `mode` → **compile** diagnostics. No free-form host
string actions.

## Standard four screens

Shipped from `std_screens/*.yuki`; project screens with the same name **override**.

| Name | Role |
|------|------|
| `title` | Start / Load / Settings |
| `game_menu` | Continue / Save / Load / Settings / Title (Esc) |
| `save_load` | Slots 0..N−1; `mode` selects save vs load; Back |
| `settings` | text speed, auto, master/BGM/SE volumes; Back |

- Default **N = 6**; set `"save_slots": N` in `moonsight.json` (clamped 1..20).
- `mode=load`: empty slots are **not focusable**.
- `mode=save`: overwrite without confirm; no screenshots.
- Screen stack is **not** part of narrative save JSON. Prefs are separate.

## Narrative bridge

```yuki
@ui.show "game_menu"
@ui.show "save_load" mode=load
@ui.hide
@ui.hide "settings"
```

`OpenMenu` (Esc) while Playing with an empty stack ≡ show `game_menu`.
While a modal is open, Esc pops one layer (return).

## Input (host defaults)

| Input | Intent / effect |
|-------|-----------------|
| Esc | `OpenMenu` (3) |
| Enter / Space / Z / click | `Advance` — activates focused button on screens |
| ↑ / W | `MenuUp` (5) |
| ↓ / S | `MenuDown` (6) |
| A | `ToggleAuto` (syncs prefs.`auto_mode`) |
| 1–9 | `Select(n)` choices while Playing |
| Ctrl/Cmd+S / L | Quick save/load **slot 0** (not via Screen) |

## Prefs keys

Stored as one JSON object under `localStorage` key `moonsight/prefs`.

| Key | Type | Default | Clamp / notes |
|-----|------|---------|----------------|
| `text_speed` | float | `1.0` | 0.25..3.0 — typewriter multiplier |
| `auto_mode` | bool | `false` | Mirrors engine auto / ToggleAuto |
| `master_volume` | float | `1.0` | 0..1 |
| `bgm_volume` | float | `1.0` | 0..1 |
| `se_volume` | float | `1.0` | 0..1 |

Output BGM/SE ≈ logical volume × master × channel prefs (host multiplies).

## Slot keys

| Storage | Key |
|---------|-----|
| Slot blob | `localStorage` `moonsight/save/{slot}` |
| Prefs | `moonsight/prefs` |

Body is narrative save **v3**. Screen stack is never serialized into the slot.

## Author checklist

1. Prefer overriding a std screen only when needed; keep the same action set.
2. Use `@ui.show` for scripted menus; do not invent widget trees from host ops.
3. Pair presentation waits with `@flow.wait` as in Phase 2 (menus pause narrative).
4. Cold start requires a `title` def (std provides one); without it the engine
   stays in Playing after `boot_title`.
