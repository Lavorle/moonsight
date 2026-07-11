# Play input semantics (Q1 / 0.5)

Host devices map to **intent codes** each frame; the engine applies them in
`Engine::tick(intent, dt~, skip_held~)`. Full host-command tables live in
[`host-commands.md`](./host-commands.md); pack/export wiring in
[`draw-list-pack.md`](./draw-list-pack.md); UI trees in
[`ui-moonbit.md`](./ui-moonbit.md).

## Intent table + codes

Defined in `render.intent_from_code` / `intent_to_code`, wired by
`host_web/js_glue/boot.js` → `export_frame(intent_code, dt_ms, skip_held)`.

| Code | Intent | Meaning |
|-----:|--------|---------|
| 0 | `None_` | No one-shot input this frame |
| 1 | `Advance` | Complete typewriter, resume bare Yield, or activate focused button |
| 2 | `SkipTyping` | One-shot complete typing / advance (compat); host prefers hold skip |
| 3 | `OpenMenu` | Playing + empty stack → `game_menu`; modal open → pop one layer |
| 4 | `ToggleAuto` | Toggle auto-advance (+ prefs `auto_mode`) |
| 5 | `MenuUp` | Previous focusable (menus / choices) |
| 6 | `MenuDown` | Next focusable |
| 7 | `MenuLeft` | Focused slider step down (or left focus where used) |
| 8 | `MenuRight` | Focused slider step up |
| 9 | `OpenBacklog` | Playing + empty stack → show `"backlog"` modal |
| 10+n | `Select(n)` | Commit choice index `n` (keys **1**–**9** → n = 0..8) |

**Not an intent code:** `skip_held` is a separate `export_frame` argument (0/1)
set every frame while **Control** is held.

## Default keys (browser host)

| Input | Effect |
|-------|--------|
| Click / Enter / Space / Z | `Advance` (on menus = activate focused button) |
| Esc | `OpenMenu` (open `game_menu` or pop modal) |
| ↑ / W | `MenuUp` |
| ↓ / S | `MenuDown` (plain **S**; **Ctrl/Cmd+S** = quick-save slot 0) |
| ← / → | `MenuLeft` / `MenuRight` (settings sliders) |
| A | `ToggleAuto` |
| H | `OpenBacklog` (Playing; ignored with Ctrl chord) |
| 1–9 | `Select(0)`…`Select(8)` |
| **Ctrl hold** | `skip_held=1` each frame (burst skip) |
| Ctrl/Cmd+S / Ctrl/Cmd+L | Quick save / load **slot 0** (not intents) |

Cold start is **Title** (`title` modal). Narrative Advance is frozen while any
modal is open; only the stack top receives UI intents.

## Pointer

Engine-owned hit-test (not host layout constants). Host maps canvas events to
logical 1920×1080 coords and calls `export_pointer(x, y, phase)`:

| `phase` | Event | Engine effect |
|--------:|-------|---------------|
| 0 | `pointermove` | Hover update; returns `hover_kind` |
| 1 | `pointerdown` | Hit-test activate, or miss→Advance when Playing |
| 3 | `pointerleave` | Clear hover |

Return value `hover_kind`: **0** none, **1** button, **2** choice, **3** slider.
Host maps that to CSS cursor (`pointer` / `ew-resize` / `default`).

| Input | Effect |
|-------|--------|
| Click empty (Playing) | Advance (engine; typewriter complete-first, same as keyboard) |
| Click button / choice / slider | Hit-test activate (choice commits that row; slider sets pref from x ratio) |
| Move | Hover + cursor |
| Leave canvas | Clear hover |

**Same-frame rule:** call `export_pointer` then `export_frame(0, dt, skip_held)`
in the same frame. Pointer down already consumed the interaction — host must
set pending intent to `None` (code **0**) so the frame tick does **not** double
`Advance`. Pointer does **not** advance `wait_remaining` / tweens; presentation
clocks still run via `export_frame`. While `wait_remaining > 0`, pointer down
does not Advance or Select. On Title / modal stack, only the stack top is
hit-tested; empty-canvas click does not Advance narrative.

Keyboard intents remain on `export_frame` (Esc, ↑↓, 1–9, Ctrl hold, …).

## `skip_held` vs `SkipTyping`

| | `SkipTyping` (code 2) | `skip_held` (tick flag) |
|--|----------------------|-------------------------|
| Shape | One-shot intent | Per-frame boolean while Ctrl held |
| Typewriter incomplete | Completes text | Completes text (once per burst entry) |
| Yield, text complete | Resume like Advance | Burst-advance up to **`skip_burst_max` = 8** Yield→run cycles/frame |
| Timed `@flow.wait` | **Ignored** (gate) | **Ignored** (gate) |
| `Choose` waiting | Does not auto-pick | **Does not** auto-select options |
| Modal / Title active | UI path only | Flag ignored for narrative |
| Overlay fade mid-flight | Not forced-snap | Same as Advance (no extra fade gate in Q1) |

Host maps **Ctrl hold** → `skip_held`, not one-shot `SkipTyping`. Auto mode
synthesizes `Advance` when idle; hold skip is the faster path when both apply.

## `wait_remaining` gate

Timed `@flow.wait T` (`T > 0`) sets `stage.wait_remaining = T` and yields.
While `wait_remaining > 0`:

- **`Advance`**, **`SkipTyping`**, and **`Select`** are dropped to `None_`.
- **`skip_held`** does not burst-advance (burst loop also stops if wait > 0).
- **`OpenMenu` / menu navigation** still work; countdown continues in the
  background while a modal is open.
- Bare `@flow.wait` / `@flow.yield` leave `wait_remaining = 0` and resume on
  Advance (or skip burst).

Layer tweens, `trans.fade`, and `trans.dissolve` do **not** gate Advance by
themselves — scripts must pair them with `@flow.wait` when presentation must
block.

### Presentation clocks vs wait / skip

Dissolve and fade clocks **advance during** timed `@flow.wait` (and while menus
are open — same presentation tick). Hold-skip and Advance remain blocked by
`wait_remaining > 0` and **do not snap** mid-fade or mid-dissolve; after the
wait ends, any remaining presentation time continues on the wall clock until
complete.

## Confirm behavior

Dangerous UI actions go through modal `"confirm"` and `ConfirmKind`:

| Kind | Trigger | Yes | No (default focus) |
|------|---------|-----|---------------------|
| `OverwriteSave(slot)` | Save into an occupied slot | Writes slot | Cancels |
| `QuitToTitle` | Game menu → Title (`request_quit_to_title`) | `quit_to_title` | Cancels |

- Message text is a fixed `Literal("Are you sure?")` in `std_ui` (not kind-bound;
  `ConfirmKind` only selects the Yes action).
- **Default focus is No** so Enter alone does not confirm destructive actions.
- `confirm_yes` / `confirm_no` Capabilities close the confirm flow.

## Backlog behavior

| Item | Rule |
|------|------|
| Source | Completed dialogue lines (`speaker` + full text) after typewriter complete |
| Capacity | Ring buffer **100**; oldest dropped |
| Persist | **Session only** — not in save v3; cleared on `start_game`, `quit_to_title`, load |
| Open | **H** / `OpenBacklog`, or game menu **History** → `"backlog"` |
| Close | Esc / Close → `return_modal` |
| UI | Read-only list (last **12** lines via `BacklogLine`); no free scroll (Q3) |
| Non-recorded | Choice labels, system modal copy |

## Related

- Engine: `runtime/engine.mbt` (`tick`, `tick_skip_burst`, `pointer_event`, backlog)
- Host: `host_web/main.mbt` `export_pointer` / `export_frame`; `js_glue/boot.js`;
  Svelte `apps/host-web/src/lib/gameSession.ts`
- UI: `std_ui` modals `"backlog"`, `"confirm"`, settings `Slider`; themes in
  [`ui-moonbit.md`](./ui-moonbit.md)
