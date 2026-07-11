# MoonSight Q3 — 系统与 UI 完备（0.8）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close product gate **0.8**: vertical `UiNode::ScrollView` with full scroll gestures for backlog, parallel Q3 system MVPs (confirm/slots/theme/host error/docs), and closable post-Q2 residual debt.

**Architecture:** Scroll state lives on `UiRuntime` (not saved). Layout walks `ScrollView` children with `scroll_y` offset and **CPU-clips** ops/hits to the viewport; scrollbar is painted as track/thumb widgets. Host sends `export_pointer` (incl. phase=2 up) and new `export_wheel`; Engine gates modal so scroll never Advances narrative. Backlog bind expands from 12 lines to ring capacity (100).

**Tech Stack:** MoonBit (`moon test` / `moon check` / `moon build --target wasm-gc`), Vite + Svelte 5 + TS (`apps/host-web`), vanilla `host_web/js_glue` parity, Fumadocs (`apps/docs-site`), existing WebGPU draw-list host.

**Spec:** `docs/superpowers/specs/2026-07-11-moonsight-q3-system-ui-design.md`  
**Roadmap:** `docs/superpowers/specs/2026-07-11-moonsight-roadmap-v2-design.md` (Q3 row)

**Pinned defaults (from spec):**

| Item | Choice |
|------|--------|
| ScrollView | Vertical only; no nesting |
| Consumer | backlog modal only this quarter |
| Gestures | wheel + content pan + scrollbar drag + ↑↓ (/ PgUp/PgDn if mapped) |
| Wheel sign | `dy > 0` → `scroll_y` **decreases** (reveal earlier lines above) |
| Open backlog | `scroll_y = max` (pin newest); no session memory of offset |
| Clip | CPU discard out-of-viewport ops/hits first; GPU scissor optional |
| Scrollbar roles | `ui.scroll_track`, `ui.scroll_thumb` |
| Confirm | existing modal; default focus No; no second confirm system |
| Slot thumbs | icons/placeholders only (`ui.slot_empty` / `ui.slot_filled`) |
| Dual host | Svelte + js_glue both get wheel/up/blur |
| Debt | D1–D7 closable list; D6 = one manual WebGPU run |

**Cut order if schedule slips:** ScrollView+backlog → D1–D4 → confirm+Host error → slots/theme → Docs → D6/D7.

---

## File map

| Path | Role |
|------|------|
| `runtime/ui_types.mbt` | `UiNode::ScrollView`; optional `TextBindSrc` helpers |
| `runtime/ui_runtime.mbt` | scroll state, walk clip, scrollbar paint, wheel/drag/keyboard scroll |
| `runtime/ui_test.mbt` | ScrollView unit tests (clamp, wheel, drag, clip, pin newest) |
| `runtime/engine.mbt` | `wheel_event`; pointer phase=2; backlog bind max=capacity; MenuUp/Down scroll when backlog |
| `runtime/engine_test.mbt` | modal gate + wheel no Advance; confirm default; dissolve save (D2) |
| `runtime/host.mbt` | D1: `scale=` on builtin `layer.show` / `layer.set` parity with std_commands |
| `runtime/host` tests or `runtime/*_test.mbt` | scale builtin tests |
| `runtime/save.mbt` / docs | D2: document mid-dissolve load = fade-only (phase not saved); tests |
| `std_ui/modals.mbt` | backlog ScrollView; save_load slot icons; confirm contract comments/tests |
| `std_ui/lib_test.mbt` | backlog structure smoke |
| `render/snapshot.mbt` | optional resource name constants for scroll/slot |
| `host_web/main.mbt` | `export_wheel`; pointer docs phase=2 |
| `host_web/moon.pkg` | export `export_wheel` |
| `apps/host-web/src/lib/gameSession.ts` | wheel, pointerup, blur→ctrlHeld false, load/error status |
| `apps/host-web/src/App.svelte` + `app.css` | loading/error chrome |
| `apps/host-web/public/themes/amber_soft/theme.json` (+ solids) | scroll + slot roles |
| `apps/host-web/scripts/gen-amber-soft-theme.mjs` | generate scroll/slot PNGs if used |
| `host_web/js_glue/boot.js` | parity wheel/up/blur |
| `docs/play-input.md`, `docs/ui-moonbit.md`, `docs/host-commands.md` | scroll + dissolve save + scale |
| `apps/docs-site/content/{zh,en}/*` | play-input + backlog/UI notes |
| `README.md` | Q3 / 0.8 scope when gate met |
| `.superpowers/sdd/` | task briefs/reports optional during SDD |

---

## Task 1: `UiNode::ScrollView` + measure/clip paint (no gestures yet)

**Files:**
- Modify: `runtime/ui_types.mbt`
- Modify: `runtime/ui_runtime.mbt`
- Modify: `runtime/ui_test.mbt`

- [ ] **Step 1: Write failing tests**

Append to `runtime/ui_test.mbt`:

```mbt
///|
test "ScrollView paints only content inside viewport" {
  let app = UiApp::new()
  // 3 text lines × ui_line_h; viewport only 1.5 lines tall
  let lines : Array[UiNode] = []
  for i in 0..<3 {
    lines.push(
      UiNode::Text(
        src=TextBindSrc::Literal("L\{i}"),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=VisiblePred::Always,
      ),
    )
  }
  app.register_modal(
    "sv",
    UiNode::ScrollView(
      x=100.0,
      y=100.0,
      w=400.0,
      h=96.0, // ~1.5 * 64
      children=[UiNode::VBox(x=None, y=None, children=lines)],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("sv")
  rt.sync_bind(UiBindCtx::empty())
  let ops = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty())
  // At scroll_y=0, only top lines intersect viewport; ops with text must have y in [100, 196)
  for op in ops {
    match op.text {
      Some(_) => {
        assert_true(op.y.to_double() >= 100.0 - 0.1)
        assert_true(op.y.to_double() < 196.0)
      }
      None => ()
    }
  }
}

///|
test "ScrollView content_h exceeds viewport when many children" {
  let app = UiApp::new()
  let lines : Array[UiNode] = []
  for i in 0..<5 {
    lines.push(
      UiNode::Text(
        src=TextBindSrc::Literal("x"),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=VisiblePred::Always,
      ),
    )
  }
  app.register_modal(
    "sv",
    UiNode::ScrollView(
      x=0.0,
      y=0.0,
      w=400.0,
      h=64.0,
      children=[UiNode::VBox(x=None, y=None, children=lines)],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("sv")
  rt.sync_bind(UiBindCtx::empty())
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  assert_true(rt.scroll_max() > 0.0)
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
export CC=gcc
moon test -p runtime
```

Expected: FAIL — `ScrollView` not a constructor / methods missing.

- [ ] **Step 3: Add node variant**

In `runtime/ui_types.mbt` on `UiNode`:

```mbt
  /// Vertical scroll viewport. Children laid out from top; runtime owns scroll_y.
  ScrollView(
    x~ : Double,
    y~ : Double,
    w~ : Double,
    h~ : Double,
    children~ : Array[UiNode],
  )
```

- [ ] **Step 4: Runtime scroll fields + walk**

In `UiRuntime` add (names may be private helpers):

```mbt
// On UiRuntime:
mut scroll_y : Double
mut scroll_content_h : Double
mut scroll_vp_x : Float
mut scroll_vp_y : Float
mut scroll_vp_w : Float
mut scroll_vp_h : Float
mut scroll_bar_w : Float  // e.g. 16.0
```

Constants:

```mbt
let ui_scroll_bar_w : Float = 16.0
let ui_res_scroll_track : String = "ui.scroll_track"
let ui_res_scroll_thumb : String = "ui.scroll_thumb"
```

Implement `walk_ui_node` arm for `ScrollView`:

1. Set viewport rect from `x,y,w,h` (absolute; same as Panel).
2. **Measure pass:** walk `children` at `(vx, vy)` with a temporary `UiWalkState` (`paint=false`) to get `(cw, ch)` → store `scroll_content_h = ch`.
3. **Clamp** `scroll_y` to `[0, max(0, ch - h)]`.
4. **Paint/hit pass:** walk children at `(vx, vy - scroll_y)` with `paint` as parent; after each child (or filter ops), **drop** any op whose rect does not intersect viewport; **drop** focusables whose rect does not intersect viewport (shift focusable y by scroll already via origin).
5. If `ch > h` and `paint`, push track (`ui.scroll_track`) on right edge and thumb (`ui.scroll_thumb`) sized by `h/ch` (min thumb height ~24px).

Helpers:

```mbt
pub fn UiRuntime::scroll_max(self : UiRuntime) -> Double {
  let m = self.scroll_content_h - self.scroll_vp_h.to_double()
  if m > 0.0 { m } else { 0.0 }
}

fn clamp_scroll(self : UiRuntime) -> Unit {
  let max = self.scroll_max()
  if self.scroll_y < 0.0 { self.scroll_y = 0.0 }
  if self.scroll_y > max { self.scroll_y = max }
}
```

**Clip helper:** reject op if `op.y + op.h <= vp_y || op.y >= vp_y + vp_h` (and optional x). Same for focus rects.

- [ ] **Step 5: Run tests — expect PASS**

```bash
moon test -p runtime
```

- [ ] **Step 6: Commit**

```bash
git add runtime/ui_types.mbt runtime/ui_runtime.mbt runtime/ui_test.mbt
git commit -m "feat(runtime): UiNode::ScrollView with clipped paint"
```

---

## Task 2: Scroll API — clamp, wheel, pin newest

**Files:**
- Modify: `runtime/ui_runtime.mbt`
- Modify: `runtime/ui_test.mbt`

- [ ] **Step 1: Failing tests**

```mbt
///|
test "scroll_by clamps to range" {
  // setup ScrollView content_h > viewport as Task 1
  // ... build rt with 5 lines, h=64 ...
  ignore(rt.paint_modal(...)) // ensure content_h measured
  rt.scroll_by(-1000.0)
  assert_eq(rt.scroll_y, 0.0)
  rt.scroll_by(10000.0)
  assert_true(rt.scroll_y >= rt.scroll_max() - 0.01)
}

///|
test "wheel dy positive decreases scroll_y" {
  // pin near bottom first
  ignore(rt.paint_modal(...))
  rt.scroll_y = rt.scroll_max()
  let before = rt.scroll_y
  assert_true(rt.handle_wheel(150.0, 120.0, 40.0)) // over viewport
  assert_true(rt.scroll_y < before)
}

///|
test "wheel outside viewport is ignored" {
  ignore(rt.paint_modal(...))
  let before = rt.scroll_y
  assert_false(rt.handle_wheel(10.0, 10.0, 40.0))
  assert_eq(rt.scroll_y, before)
}

///|
test "show_modal backlog pins scroll to newest" {
  // after measure, pin_scroll_end sets scroll_y = max
  rt.pin_scroll_end()
  ignore(rt.paint_modal(...))
  assert_true(rt.scroll_y >= rt.scroll_max() - 0.01)
}
```

- [ ] **Step 2: Run — FAIL**

```bash
moon test -p runtime
```

- [ ] **Step 3: Implement**

```mbt
/// Wheel over viewport. dy>0 => scroll_y decreases (spec).
/// Returns true if event was consumed.
pub fn UiRuntime::handle_wheel(
  self : UiRuntime,
  x : Double,
  y : Double,
  dy : Double,
) -> Bool {
  if self.stack.is_empty() { return false }
  // need last layout metrics — call ensure_scroll_layout(bind) or require paint first
  if !point_in_scroll_viewport(self, x, y) { return false }
  let k = 1.0 // logical px per dy unit; host can scale
  self.scroll_y = self.scroll_y - k * dy
  self.clamp_scroll()
  true
}

pub fn UiRuntime::scroll_by(self : UiRuntime, delta : Double) -> Unit {
  self.scroll_y = self.scroll_y + delta
  self.clamp_scroll()
}

pub fn UiRuntime::pin_scroll_end(self : UiRuntime) -> Unit {
  self.scroll_y = self.scroll_max() // if content_h unknown, set flag pin_on_next_layout
}
```

On `show_modal`, if name is `"backlog"` (or always for any ScrollView): set `pin_on_next_layout = true`. During next walk of ScrollView, if flag: `scroll_y = max` then clear flag.

- [ ] **Step 4: Tests PASS + commit**

```bash
moon test -p runtime
git add runtime/ui_runtime.mbt runtime/ui_test.mbt
git commit -m "feat(runtime): ScrollView wheel, clamp, pin-to-end"
```

---

## Task 3: Pointer drag — content pan + scrollbar + phase up

**Files:**
- Modify: `runtime/ui_runtime.mbt`
- Modify: `runtime/ui_test.mbt`
- Modify: `runtime/engine.mbt` (phase==2)
- Modify: `runtime/engine_test.mbt`

- [ ] **Step 1: Failing tests**

```mbt
///|
test "content drag pans scroll_y" {
  // scroll_y starts 50; drag content down by 20 (pointer y increases) => scroll_y decreases by 20
  rt.begin_scroll_drag_content(y=200.0)
  rt.pointer_scroll_move(y=220.0)
  // scroll_y -= (220-200)
  assert_true(...)
  rt.end_scroll_drag()
}

///|
test "scrollbar thumb drag maps to scroll_y" {
  // down on thumb, move to bottom of track => scroll near max
}

///|
test "button hit preferred over content pan" {
  // ScrollView with a Button child OR Close outside — down on Close activates, no drag
}
```

Engine test:

```mbt
///|
test "pointer phase 2 ends scroll drag without Advance" {
  // open modal with ScrollView; phase 1 content; phase 2 up; Playing path not used
}
```

- [ ] **Step 2: Drag state**

```mbt
enum ScrollDrag {
  Idle
  Content(last_y : Double)
  Bar
} derive(Debug)

// On UiRuntime:
mut scroll_drag : ScrollDrag
```

Hit priority in a new `UiRuntime::handle_pointer_scroll` **before** focusable activation, or integrate into `handle_pointer` / engine path:

1. Collect focusables (already clipped). If hit Button → activate (existing); clear drag.  
2. Else if hit thumb rect → `scroll_drag = Bar`.  
3. Else if hit track → jump `scroll_y` from y ratio; optional `Bar`.  
4. Else if hit viewport content → `scroll_drag = Content(y)`.  
5. Return true if consumed (so Engine does not Advance).

On phase 0 move: if `Content`, update scroll from dy; if `Bar`, map y to scroll_y.

On phase 2 or 3: `scroll_drag = Idle` (leave also clears).

**Engine `pointer_event`:**

```mbt
if phase == 2 {
  self.ui.end_scroll_drag()
  return self.ui.hover_kind()
}
// phase 0: existing hover + if dragging, move scroll
if phase == 0 {
  self.ui.pointer_scroll_move(x, y) // no-op if Idle
  ignore(self.ui.pointer_hover(x, y))
  return self.ui.hover_kind()
}
```

For phase 1 with modal: call scroll-aware pointer handler that returns consumed bool.

- [ ] **Step 3: Tests PASS + commit**

```bash
moon test -p runtime
git add runtime/ui_runtime.mbt runtime/ui_test.mbt runtime/engine.mbt runtime/engine_test.mbt
git commit -m "feat(runtime): ScrollView content and scrollbar drag"
```

---

## Task 4: Full backlog bind + `std_ui` ScrollView modal

**Files:**
- Modify: `runtime/engine.mbt` (`format_backlog_lines` max)
- Modify: `std_ui/modals.mbt` (`build_backlog`)
- Modify: `runtime/engine_test.mbt` / `std_ui/lib_test.mbt`

- [ ] **Step 1: Failing tests**

```mbt
///|
test "sync_ui_bind exposes up to backlog capacity lines" {
  // push 20 lines; format with max=100; length == 20
  assert_eq(eng.ui.bind.backlog_lines.length(), 20)
}

///|
test "std_ui backlog modal registers and uses ScrollView" {
  // optional: walk tree or paint and assert scroll_max > 0 with many lines
}
```

- [ ] **Step 2: Engine bind**

Change:

```mbt
// was: format_backlog_lines(self.backlog, 12)
let backlog_lines = format_backlog_lines(self.backlog, self.backlog.capacity)
```

- [ ] **Step 3: Rebuild `build_backlog`**

Replace fixed 12-loop with ScrollView. Keep Close **outside** the ScrollView so it is always clickable:

```mbt
fn build_backlog(app : @runtime.UiApp) -> @runtime.UiNode {
  // Pre-create max capacity text rows (100); empty lines resolve to "".
  let line_nodes : Array[@runtime.UiNode] = []
  for i in 0..<100 {
    line_nodes.push(
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::BacklogLine(i),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=@runtime.VisiblePred::Always,
      ),
    )
  }
  // Optional: use VisiblePred later to hide empty — not required if "" paints thin.
  @runtime.UiNode::Fixed(
    x=0.0, y=0.0, w=Some(1920.0), h=Some(1080.0),
    children=[
      @runtime.UiNode::Panel(
        resource="ui.dialogue_box",
        x=280.0, y=48.0, w=1360.0, h=980.0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::VBox(
        x=Some(360.0), y=Some(72.0),
        children=[
          @runtime.UiNode::Text(
            src=@runtime.TextBindSrc::Literal("History"),
            x=0.0, y=0.0, font_size=30.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Spacer(w=800.0, h=8.0),
          @runtime.UiNode::ScrollView(
            x=360.0, y=150.0, w=1200.0, h=780.0,
            children=[
              @runtime.UiNode::VBox(x=None, y=None, children=line_nodes),
            ],
          ),
          // Close below viewport in fixed layout — place with Fixed coords if VBox flow fights ScrollView absolute.
          app.button("Close", fn(c) { c.return_modal() }),
        ],
      ),
    ],
  )
}
```

**Layout note:** `ScrollView` uses absolute `x,y,w,h` like Panel. Prefer structure:

```text
Fixed full screen
  Panel card
  Text "History" at absolute
  ScrollView at absolute viewport
  Button Close at absolute bottom
```

rather than nesting ScrollView inside flowing VBox if absolute/flow conflict. Mirror existing Fixed+absolute style from `build_confirm`.

On `show_modal("backlog")` already in UiRuntime: set `pin_on_next_layout`.

- [ ] **Step 4: Hide empty backlog rows (recommended)**

Either:

- Only push `BacklogLine(i)` for `i < bind.backlog_lines.length()` by rebuilding tree each bind (heavier), or  
- In `walk` Text with `BacklogLine`: if resolve empty, return `(0,0)` height so empty slots collapse.

Prefer **collapse empty** in Text walk:

```mbt
let label = src.resolve(st.bind)
if label == "" && src is BacklogLine(_) {
  return (0.0, 0.0)
}
```

- [ ] **Step 5: Tests PASS + commit**

```bash
moon test -p runtime -p std_ui
git add runtime/engine.mbt runtime/ui_runtime.mbt std_ui/modals.mbt runtime/engine_test.mbt std_ui/lib_test.mbt
git commit -m "feat(std_ui): backlog ScrollView with full ring bind"
```

---

## Task 5: Engine wheel export + keyboard scroll + modal gate

**Files:**
- Modify: `runtime/engine.mbt`
- Modify: `runtime/engine_test.mbt`
- Modify: `host_web/main.mbt`
- Modify: `host_web/moon.pkg`
- Modify: `runtime/intent` path for MenuUp/Down when backlog top

- [ ] **Step 1: Tests**

```mbt
///|
test "wheel on backlog does not Advance narrative" {
  // Playing with text; open backlog; wheel; stage text unchanged / no apply Advance
}

///|
test "MenuUp on backlog decreases scroll_y toward older" {
  // open backlog, pin end, MenuUp => scroll_y decreases by ~ui_line_h
}
```

- [ ] **Step 2: Engine API**

```mbt
/// Returns hover_kind (0) or 4 if over scroll chrome (optional).
pub fn Engine::wheel_event(self : Engine, x : Double, y : Double, dy : Double) -> Int {
  self.sync_ui_bind()
  if self.ui.stack_depth() == 0 {
    return 0
  }
  // ensure layout metrics: paint walk or measure-only
  ignore(self.ui.ensure_scroll_metrics(self.ui.bind))
  ignore(self.ui.handle_wheel(x, y, dy))
  self.ui.hover_kind()
}
```

In `tick_ui` when top modal is backlog (name `"backlog"`):

```mbt
MenuUp => {
  ignore(self.ui.ensure_scroll_metrics(self.ui.bind))
  self.ui.scroll_by(0.0 - 64.0) // line height; expose constant
}
MenuDown => {
  ignore(self.ui.ensure_scroll_metrics(self.ui.bind))
  self.ui.scroll_by(64.0)
}
```

If focus is on Close button, **spec says** scroll still preferred for ↑↓ on backlog — implement as: backlog top → always scroll on MenuUp/Down; Activate still Enter on Close. (Matches design §3.4.)

Optional: map host PageUp/PageDown later; not required if intents missing.

- [ ] **Step 3: Wasm export**

`host_web/main.mbt`:

```mbt
/// Wheel: logical x,y and vertical dy (dy>0 => reveal older content).
pub fn export_wheel(x : Float, y : Float, dy : Float) -> Int {
  match session.val.engine {
    None => 0
    Some(eng) => eng.wheel_event(x.to_double(), y.to_double(), dy.to_double())
  }
}
```

`host_web/moon.pkg` link exports: add `"export_wheel"`.

Update `export_pointer` doc comment: phase `2=up`.

- [ ] **Step 4: Tests + wasm build**

```bash
moon test -p runtime
moon build --target wasm-gc --release host_web
git add runtime/engine.mbt runtime/engine_test.mbt host_web/main.mbt host_web/moon.pkg
git commit -m "feat(host): export_wheel and backlog keyboard scroll"
```

---

## Task 6: Host wiring — wheel, pointerup, blur (Svelte + js_glue)

**Files:**
- Modify: `apps/host-web/src/lib/gameSession.ts`
- Modify: `host_web/js_glue/boot.js`
- Modify: `apps/host-web/src/App.svelte` (status/error only if needed here)

- [ ] **Step 1: Types**

```ts
export_wheel?: (x: number, y: number, dy: number) => number;
export_pointer?: (x: number, y: number, phase: number) => number;
```

- [ ] **Step 2: Svelte `gameSession.ts`**

```ts
const onWheel = (ev: WheelEvent) => {
  if (!this.exports_?.export_wheel || !canvas) return;
  ev.preventDefault();
  const { x, y } = pointerToLogical(canvas, ev);
  // normalize: browser deltaY >0 often means scroll down content → reveal lower = newer → increase scroll_y
  // Spec: dy>0 => scroll_y decreases (older). Map browser deltaY so "wheel up" reveals older:
  // wheel up (deltaY < 0) → positive dy to engine.
  const dy = -ev.deltaY;
  this.exports_.export_wheel(x, y, dy);
  this.pointerDirty = true;
};

const onPointerUp = (ev: PointerEvent) => {
  if (!this.exports_?.export_pointer || !canvas) return;
  const { x, y } = pointerToLogical(canvas, ev);
  this.exports_.export_pointer(x, y, 2);
};

const onBlur = () => {
  this.ctrlHeld = false;
};
const onVis = () => {
  if (document.visibilityState === "hidden") this.ctrlHeld = false;
};

canvas.addEventListener("wheel", onWheel, { passive: false });
canvas.addEventListener("pointerup", onPointerUp);
window.addEventListener("blur", onBlur);
document.addEventListener("visibilitychange", onVis);
// remove on stop()
```

- [ ] **Step 3: Mirror in `boot.js`**

Same wheel sign mapping, phase 2, blur/visibility → `ctrlHeld = false`.

- [ ] **Step 4: Manual smoke note**

Cannot automate WebGPU here; record in commit body that D3 host path is wired.

- [ ] **Step 5: Build + commit**

```bash
cd apps/host-web && npm run build && cd ../..
git add apps/host-web/src/lib/gameSession.ts host_web/js_glue/boot.js
git commit -m "feat(host): wheel, pointerup, clear skip on blur"
```

---

## Task 7: Theme roles — scroll + slot solids/PNGs

**Files:**
- Modify: `apps/host-web/public/themes/amber_soft/theme.json`
- Modify: `apps/host-web/scripts/gen-amber-soft-theme.mjs` (if generates files)
- Modify: host solid fallbacks in `gameSession` / `webgpu_bridge` / `boot.js` as needed
- Copy theme into `host_web/js_glue` only if that path loads themes; else solids only for js_glue

- [ ] **Step 1: Extend theme.json**

```json
"ui.scroll_track": [36, 28, 32, 200],
"ui.scroll_thumb": [200, 140, 90, 240],
"ui.slot_empty": [40, 32, 36, 180],
"ui.slot_filled": [90, 56, 42, 220]
```

Add matching `roles` files or rely on solids-only (acceptable for MVP).

- [ ] **Step 2: Intern resource names in host_web if required** (same pattern as button roles in `main.mbt` / snapshot).

- [ ] **Step 3: Commit**

```bash
git add apps/host-web/public/themes/amber_soft/theme.json apps/host-web/scripts/gen-amber-soft-theme.mjs
git commit -m "feat(theme): scroll and slot role placeholders for Amber Soft"
```

---

## Task 8: Save/load slot icons + confirm contract tests

**Files:**
- Modify: `std_ui/modals.mbt` (`build_save_load`, `build_confirm`)
- Modify: `runtime/engine_test.mbt` / `std_ui/lib_test.mbt`

- [ ] **Step 1: Slot row visual**

For each slot index `i`, push an `Image` or `Panel`:

```mbt
@runtime.UiNode::Panel(
  resource="ui.slot_empty", // paint path: choose resource by VisiblePred
  ...
  visible=@runtime.VisiblePred::And(
    VisiblePred::ModeIs("save"), // or Always
    // need "slot empty" pred — use existing SlotOccupied inverted
  ),
)
```

If no `Not(SlotOccupied)` pred exists, add:

```mbt
// ui_types.mbt VisiblePred
Not(VisiblePred)
// eval: not inner.eval
```

Or two panels:

- `ui.slot_empty` visible when `!occupied` — requires `VisiblePred::SlotEmpty(i)` or `Not(SlotOccupied(i))`.

Implement `Not` or `SlotEmpty` (prefer `Not` for generality):

```mbt
Not(VisiblePred)
```

- [ ] **Step 2: Confirm tests**

```mbt
///|
test "confirm modal focuses No first" {
  // show confirm; focusables[0] is No action
}
```

Verify overwrite save / quit still use `pending_confirm` + same modal (no new parallel UI).

- [ ] **Step 3: Commit**

```bash
moon test -p runtime -p std_ui
git add runtime/ui_types.mbt std_ui/modals.mbt runtime/engine_test.mbt
git commit -m "feat(std_ui): slot empty/filled icons and confirm focus tests"
```

---

## Task 9: Host loading / error visible state

**Files:**
- Modify: `apps/host-web/src/App.svelte`
- Modify: `apps/host-web/src/app.css`
- Modify: `apps/host-web/src/lib/gameSession.ts` (status callbacks)
- Modify: `host_web/js_glue/boot.js` / `index.html` minimally for parity message

- [ ] **Step 1: Status model**

Ensure boot failures set `onStatus` with readable text (already partial). Add explicit stages:

- `loading wasm…` / `loading manifest…` / `loading assets…` / `running` / `error: …`

- [ ] **Step 2: UI**

In `App.svelte`, when status does not start with `running`, show a full-panel message (not only a thin bar). On error, keep message visible (no blank canvas assumption).

- [ ] **Step 3: Commit**

```bash
cd apps/host-web && npm run build && cd ../..
git add apps/host-web/src/App.svelte apps/host-web/src/app.css apps/host-web/src/lib/gameSession.ts
git commit -m "feat(host-web): visible loading and error states"
```

---

## Task 10: D1 — scale on runtime builtins

**Files:**
- Modify: `runtime/host.mbt` (`builtin_layer_show`, `builtin_layer_set` if present)
- Modify: tests under `runtime/` (or host test file)

- [ ] **Step 1: Failing test**

```mbt
///|
test "builtin layer.show accepts scale named arg" {
  let stage = Stage::new()
  let dir = Director::with_builtins()
  // call layer.show via director with Str("#:scale"), Float(0.5) packing used by lower
  // OR call builtin_layer_show if test-visible
  assert_eq(stage.layers[0].scale, 0.5)
}
```

Use the same `#:scale` packing convention as `std_commands` / IR named args.

- [ ] **Step 2: Implementation**

Mirror `std_commands/layer.mbt`:

- Parse `named_double(named, "scale")`.  
- On new layer: snap or tween Scale.  
- On existing: tween/snap scale without resetting other props incorrectly.

Also fix `layer.set` builtin if it exists without scale.

- [ ] **Step 3: Commit**

```bash
moon test -p runtime -p std_commands
git add runtime/host.mbt runtime/*test*
git commit -m "fix(runtime): layer scale on with_builtins host path"
```

---

## Task 11: D2 — mid-dissolve save/load semantics

**Context:** `dissolve_phase` / `dissolve_total` are **not** saved (see `stage.mbt`). Load restores `fade_remaining` only. Mid-dissolve save currently degrades.

**Files:**
- Modify: `runtime/engine_test.mbt` or `runtime/save_test.mbt`
- Modify: `docs/host-commands.md`, `docs/play-input.md` (one clear paragraph)
- Optionally: on `load`, explicitly `dissolve_phase = 0` and keep `fade_remaining` if any

- [ ] **Step 1: Test documenting current intentional behavior**

```mbt
///|
test "save during dissolve does not restore dual-phase" {
  // start dissolve; save JSON; load into fresh engine
  // assert dissolve_phase == 0 after load
  // fade_remaining may be 0 (if not saved) — assert documented outcome
}
```

If product wants better UX without format bump: on save during dissolve, write `fade_remaining` as remaining veil time and `fade_to` as 0 or 1 matching phase — **only if** existing fade fields can express it without v5. Prefer **document + hard clear** if ambiguous:

```mbt
// apply_save_game:
eng.stage.dissolve_phase = 0
eng.stage.dissolve_total = 0.0
// leave fade_* from save blob
```

- [ ] **Step 2: Docs sentence**

> Mid-dissolve save/load: dual-phase dissolve is not part of the save format; after load the veil is cleared (`dissolve_phase=0`). Authors should not rely on resuming an in-flight dissolve.

- [ ] **Step 3: Commit**

```bash
moon test -p runtime
git add runtime/save.mbt runtime/engine.mbt runtime/*test* docs/host-commands.md docs/play-input.md
git commit -m "fix(runtime): define mid-dissolve save/load behavior"
```

---

## Task 12: Docs (repo + Fumadocs)

**Files:**
- Modify: `docs/play-input.md` — pointer phase 2, wheel, backlog scroll, blur skip
- Modify: `docs/ui-moonbit.md` — ScrollView node, theme roles scroll/slot
- Modify: `docs/host-commands.md` — dissolve save note if not done in T11
- Modify: `apps/docs-site/content/zh/play-input.mdx`, `en/play-input.mdx`
- Add or extend UI page if present; else add short section under play-input / new `ui.mdx` both langs
- Modify: `README.md` Scope when ready (or leave for Task 13)

- [ ] **Step 1: Write repo docs** aligned with implementation (no aspirational APIs).

- [ ] **Step 2: Mirror key paragraphs into Fumadocs zh/en.**

- [ ] **Step 3: Build docs site**

```bash
cd apps/docs-site && npm run build && cd ../..
```

- [ ] **Step 4: Commit**

```bash
git add docs/play-input.md docs/ui-moonbit.md docs/host-commands.md apps/docs-site/content
git commit -m "docs: ScrollView, wheel input, and Q3 system UI notes"
```

---

## Task 13: D7 residual sweep + full verification (0.8 gate)

**Files:** varies; plus `.superpowers/sdd/` notes optional

- [ ] **Step 1: Build residual table** from `.superpowers/sdd/progress.md` Q1/Q2/Pointer notes.

For each item: **close** with commit hash or **move** to appendix with reason (out of Q3 / obsolete).

Known list to process:

| Item | Action |
|------|--------|
| sticky ctrlHeld | closed by Task 6 |
| scale builtins | Task 10 |
| mid-dissolve | Task 11 |
| pointer phase / hover on modal | verify still green; fix if regressed |
| Fumadocs lag | Task 12 |
| Manual WebGPU | Step 3 |
| menu save saved_at | fix if still broken |
| wasm not git-committed | **move out** (build artifact policy) |
| interactive CI WebGPU | **move out** (env); D6 manual only |

- [ ] **Step 2: Automated gates**

```bash
export CC=gcc
moon check
moon test
moon build --target wasm-gc --release host_web
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
cd apps/host-web && npm run build && cd ../..
cd apps/docs-site && npm run build && cd ../..
```

Expected: all exit 0.

- [ ] **Step 3: Manual D6 checklist** (human browser, WebGPU)

Record results in commit message or `.superpowers/sdd/q3-final-verify-report.md`:

1. Title → Start → >12 lines → H → wheel / drag content / drag bar / ↑↓ to oldest → Close/Esc  
2. Mouse Advance, choices, Esc menu, overwrite confirm defaults No  
3. dissolve + scale visible; Ctrl skip vs `@flow.wait`; blur clears skip  
4. Force error path shows message  

- [ ] **Step 4: README Scope**

Update README Q3 / 0.8 section when checklist passes; list non-goals still deferred to Q4+.

- [ ] **Step 5: Final commit**

```bash
git add README.md docs/ .superpowers/sdd/q3-final-verify-report.md
git commit -m "docs: Q3 0.8 verification and residual closeout"
```

---

## Spec coverage checklist

| Spec requirement | Task(s) |
|------------------|---------|
| `UiNode::ScrollView` vertical | 1 |
| CPU clip | 1 |
| scrollbar track/thumb | 1, 7 |
| wheel + sign | 2, 5, 6 |
| content pan + bar drag | 3 |
| pointer phase 2 | 3, 6 |
| pin newest on open | 2, 4 |
| backlog full ring | 4 |
| keyboard scroll | 5 |
| modal no Advance | 5 |
| confirm unified | 8 |
| slot icons | 7, 8 |
| theme roles | 7 |
| Host load/error | 9 |
| dual host | 6 |
| D1 scale builtins | 10 |
| D2 dissolve save | 11 |
| D3 blur skip | 6 |
| D5 docs | 12 |
| D6 manual | 13 |
| D7 sweep | 13 |
| 0.8 success criteria | 13 |

---

## Self-review notes (plan author)

1. **No nested ScrollView / virtualization** — out of scope; 100 Text rows OK.  
2. **Absolute vs VBox placement** for backlog — Task 4 prefers Fixed+absolute to avoid flow bugs.  
3. **Browser wheel sign** — Task 6 maps `dy = -event.deltaY` so engine `dy>0` still means reveal older; tests lock engine side.  
4. **D1** targets `runtime/host.mbt` builtins (demo/tests using `with_builtins`), not only `std_commands`.  
5. **D2** does not require save format v5 unless implementation chooses fade encoding; default is clear dissolve + document.
