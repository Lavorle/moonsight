# MoonSight Phase 4 — MoonBit UI Kernel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hard-coded dialogue/choice drawing and the Screen DSL path with a retained MoonBit UI kernel (base HUD + modal stack), `std_ui`, same-wasm game UI packages, and Capabilities + callbacks.

**Architecture:** New `runtime` UI types (`UiApp` / `UiRuntime` / `UiNode` / `UiDrawOp`) own layout, focus, hit-test, and paint requests. Engine routes input to modal stack or HUD vs narrative. `render` consumes `UiDrawOp` only for widgets (no `UiLayout` dialogue path). `std_ui` registers default HUD + four modals; optional project `ui_package` is linked into `host_web` wasm after std. Project `- screen` becomes a compile error; `screens.json` leaves the dist primary path.

**Tech Stack:** MoonBit (`moon test` / `moon check` / `moon build --target wasm-gc`), existing Engine / Stage / DrawList / `moonsightc` / `host_web` pipeline.

**Spec:** `docs/superpowers/specs/2026-07-10-moonsight-phase4-ui-kernel-design.md`

**Pinned defaults (from spec):**

| Item | Choice |
|------|--------|
| UI model | Retained `UiTree` + dual slots (HUD + modal stack) |
| Actions | Closed `Capabilities` + handler table callbacks |
| Button handlers | `action_id` → `(Capabilities) -> Unit` map on `UiApp` (no free-form host strings) |
| Build | Same wasm; `std_ui` always; optional `ui_package` via link workspace |
| Screen DSL | Hard error on `- screen`; no long-term lower compat |
| `@ui.show` / `@ui.hide` | Keep; map to `show_modal` / `hide_modal` |
| Widget MVP | VBox, HBox, Fixed, Spacer, Panel, Text, TextBind, Image, Button, ChoiceList, VisibleIf |
| Save | Narrative v3 + prefs; UI stack not saved |

---

## File map

| Path | Role |
|------|------|
| `runtime/ui_types.mbt` | **Create:** `UiNode`, `TextBindSrc`, `VisiblePred`, `UiDrawOp`, `ModalInstance`, canvas metrics helpers |
| `runtime/ui_app.mbt` | **Create:** `UiApp` builder, handler registry, `set_hud` / `register_modal` |
| `runtime/ui_runtime.mbt` | **Create:** `UiRuntime` — stack, focus, layout, hit-test, paint, input |
| `runtime/ui_caps.mbt` | **Create:** `Capabilities` trait (+ optional read-only `UiBindCtx`) |
| `runtime/ui_test.mbt` | **Create:** layout/focus/modal/bind tests with fake caps |
| `runtime/engine.mbt` | Wire `UiRuntime` instead of `ScreenState` + ScreenDef; input gating |
| `runtime/engine_test.mbt` | Cold start, menu gate, HUD choice, `@ui.show` |
| `runtime/screen.mbt` | **Remove or gut** after migration (delete ScreenDef path) |
| `runtime/screen_test.mbt` | Replace with `ui_test` coverage or delete |
| `runtime/moon.pkg` | Export new UI modules; drop script ScreenDef dependency when unused |
| `render/snapshot.mbt` | Consume `UiDrawOp` / painted lists; delete dialogue + `emit_screen_node` hard paths |
| `render/types.mbt` | Shrink `UiLayout` → canvas metrics (keep canvas_w/h + default font advances) |
| `render/snapshot_test.mbt` | Assert dialogue only via UI ops; modal paint |
| `std_ui/moon.pkg` | **Create:** package |
| `std_ui/lib.mbt` | **Create:** `register(app)` |
| `std_ui/hud.mbt` | **Create:** default dialogue/choice HUD |
| `std_ui/modals.mbt` | **Create:** title, game_menu, save_load, settings |
| `std_screens/*.yuki` | **Delete** after `std_ui` works |
| `script/parser.mbt` / `ast.mbt` / `compile.mbt` | Reject `- screen` with migration message |
| `script/screen_*.mbt` | Delete or leave unreferenced then delete |
| `script/*_test.mbt` | Remove screen lower tests; add reject test |
| `std_commands/ui_cmd.mbt` | Keep; still queue `UiHostOp` (Engine drains to `UiRuntime`) |
| `host_web/moon.pkg` | Import `std_ui`; drop `load_screens_json` export when unused |
| `host_web/main.mbt` | Init `UiApp` + `std_ui.register`; boot via UiRuntime |
| `host_web/js_glue/boot.js` | Stop requiring `screens.json`; always `boot_title` after narrative load |
| `cmd/moonsightc/config.mbt` | `ui_package` field |
| `cmd/moonsightc/build.mbt` | Link workspace; no screens.json primary; reject project screens |
| `cmd/moonsightc/ui_link.mbt` | **Create:** generate link dir for game UI + host |
| `demo/game/moonsight.json` | Optional `ui_package` |
| `demo/game/ui/*` | **Optional sample** override package |
| `docs/ui-moonbit.md` | **Create** author guide |
| `docs/screen-language.md` | Mark obsolete → point to ui-moonbit |
| `README.md` / other docs | Phase 4 scope |

---

## Task 1: UI types + UiApp handler registry (TDD)

**Files:**
- Create: `runtime/ui_types.mbt`
- Create: `runtime/ui_app.mbt`
- Create: `runtime/ui_test.mbt` (first tests)
- Modify: `runtime/moon.pkg` if new files need nothing extra (same package)

**Context:** Handlers are stored by `action_id` so nodes stay data-like and tests can invoke handlers without real Engine.

- [ ] **Step 1: Write failing tests**

Add to `runtime/ui_test.mbt`:

```mbt
///|
test "ui app registers modal and hud" {
  let app = @runtime.UiApp::new()
  app.set_hud(
    @runtime.UiNode::Text(lit="hud", x=0.0, y=0.0, visible=@runtime.VisiblePred::Always),
  )
  app.register_modal(
    "title",
    @runtime.UiNode::VBox(
      x=Some(10.0),
      y=Some(20.0),
      children=[
        @runtime.UiNode::Button(label="Start", action_id=0, visible=@runtime.VisiblePred::Always),
      ],
    ),
  )
  assert_true(app.hud is Some(_))
  assert_true(app.modals.contains("title"))
}

///|
test "ui app button helper assigns action id and runs handler" {
  let app = @runtime.UiApp::new()
  let mut called = false
  let node = app.button("Go", fn(_caps : &@runtime.Capabilities) { called = true })
  guard node is @runtime.UiNode::Button(action_id~, ..) else { fail("button") }
  // Fake caps double will be Task 2; for now invoke via app.call_handler if exposed for test
  app.debug_call_handler(action_id, FakeCaps::new())
  assert_true(called)
}
```

Use a minimal `FakeCaps` defined in the test file once `Capabilities` exists (Step 3 if needed — if trait not yet present, test only action_id allocation first).

Minimal first test if trait ordering is hard:

```mbt
///|
test "button allocates monotonic action ids" {
  let app = @runtime.UiApp::new()
  let a = app.alloc_action(fn(_c : &@runtime.Capabilities) { () })
  let b = app.alloc_action(fn(_c : &@runtime.Capabilities) { () })
  assert_true(b == a + 1)
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd /mnt/nvme1n1p2/moonsight && moon test -p runtime -v 2>&1 | tail -50
```

Expected: FAIL — `UiApp` / types missing.

- [ ] **Step 3: Implement types + UiApp**

`runtime/ui_types.mbt` (core shapes):

```mbt
///|
pub(all) enum TextBindSrc {
  Literal(String)
  DialogueName
  DialogueBody
  Pref(String)
  SlotLabel(Int)
  Var(String)
} derive(Debug, Eq)

///|
pub(all) enum VisiblePred {
  Always
  Never
  HasText
  HasChoices
  PrefBool(String)
  SlotOccupied(Int)
  ModeIs(String)
} derive(Debug, Eq)

///|
pub(all) enum UiNode {
  VBox(x~ : Double?, y~ : Double?, children~ : Array[UiNode])
  HBox(x~ : Double?, y~ : Double?, children~ : Array[UiNode])
  Fixed(x~ : Double, y~ : Double, w~ : Double?, h~ : Double?, children~ : Array[UiNode])
  Spacer(w~ : Double, h~ : Double)
  Panel(resource~ : String, x~ : Double, y~ : Double, w~ : Double, h~ : Double, visible~ : VisiblePred)
  Text(src~ : TextBindSrc, x~ : Double, y~ : Double, font_size~ : Double, visible~ : VisiblePred)
  Image(resource~ : String, x~ : Double, y~ : Double, w~ : Double, h~ : Double, visible~ : VisiblePred)
  Button(label~ : String, action_id~ : Int, visible~ : VisiblePred)
  ChoiceList(x~ : Double, y~ : Double, w~ : Double, line_h~ : Double, visible~ : VisiblePred)
} derive(Debug)

///|
pub(all) struct UiDrawOp {
  kind : Int // 0=sprite, 1=glyph-run marker handled by paint path
  resource : String
  x : Float
  y : Float
  w : Float
  h : Float
  opacity : Float
  z : Int
  /// Optional label text for button/text (paint expands to glyphs)
  text : String?
  font_size : Float
  focused : Bool
} derive(Debug)
```

`runtime/ui_caps.mbt`:

```mbt
///|
pub(open) trait Capabilities {
  fn start_game(Self) -> Unit
  fn quit_to_title(Self) -> Unit
  fn show_modal(Self, String, mode~ : String?) -> Unit
  fn return_modal(Self) -> Unit
  fn hide_modal(Self, name~ : String?) -> Unit
  fn save_slot(Self, Int) -> Unit
  fn load_slot(Self, Int) -> Unit
  fn slot_occupied(Self, Int) -> Bool
  fn slot_label(Self, Int) -> String
  fn set_pref_f(Self, String, Double) -> Unit
  fn set_pref_b(Self, String, Bool) -> Unit
  fn adjust_pref(Self, String, Double) -> Unit
  fn confirm_choice(Self, Int) -> Unit
  fn advance(Self) -> Unit
  fn prefs(Self) -> Prefs
}
```

`runtime/ui_app.mbt`:

```mbt
///|
pub(all) struct UiApp {
  mut hud : UiNode?
  mut modals : Map[String, UiNode]
  mut handlers : Map[Int, (Capabilities) -> Unit]
  mut next_action_id : Int
}

pub fn UiApp::new() -> UiApp {
  { hud: None, modals: {}, handlers: {}, next_action_id: 0 }
}

pub fn UiApp::set_hud(self : UiApp, root : UiNode) -> Unit {
  self.hud = Some(root)
}

pub fn UiApp::register_modal(self : UiApp, name : String, root : UiNode) -> Unit {
  self.modals[name] = root
}

pub fn UiApp::alloc_action(
  self : UiApp,
  handler : (Capabilities) -> Unit,
) -> Int {
  let id = self.next_action_id
  self.next_action_id = id + 1
  self.handlers[id] = handler
  id
}

pub fn UiApp::button(
  self : UiApp,
  label : String,
  handler : (Capabilities) -> Unit,
) -> UiNode {
  let id = self.alloc_action(handler)
  Button(label~, action_id=id, visible=Always)
}

pub fn UiApp::invoke(
  self : UiApp,
  action_id : Int,
  caps : &Capabilities,
) -> Unit {
  match self.handlers.get(action_id) {
    None => ()
    Some(h) => h(caps)
  }
}
```

Adjust MoonBit fn-type / trait object syntax to whatever the toolchain accepts (match existing `ScreenHost` trait style in `runtime/screen.mbt`).

- [ ] **Step 4: Run tests — expect PASS**

```bash
moon test -p runtime
```

- [ ] **Step 5: Commit**

```bash
git add runtime/ui_types.mbt runtime/ui_app.mbt runtime/ui_caps.mbt runtime/ui_test.mbt
git commit -m "feat(runtime): add UiApp, UiNode types, and Capabilities trait"
```

---

## Task 2: UiRuntime — stack, focus, layout, paint ops

**Files:**
- Create: `runtime/ui_runtime.mbt`
- Modify: `runtime/ui_test.mbt`
- Modify: `runtime/ui_types.mbt` if `LaidOut` helpers needed

**Context:** Port semantics from `ScreenState` (show/return/focus/activate) but walk `UiNode` and emit `Array[UiDrawOp]`. ChoiceList expands from bind context (options length) into focusable rows.

- [ ] **Step 1: Failing tests**

```mbt
///|
struct FakeCaps {
  mut started : Bool
  mut slots : Array[Bool]
  mut prefs : Prefs
} derive(Debug)

// impl Capabilities for FakeCaps — start_game sets started=true, etc.

///|
test "modal show return and activate start_game" {
  let app = UiApp::new()
  let start_id = app.alloc_action(fn(c : &Capabilities) { c.start_game() })
  app.register_modal(
    "title",
    VBox(x=Some(0.0), y=Some(0.0), children=[
      Button(label="Start", action_id=start_id, visible=Always),
    ]),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  let caps = FakeCaps::new()
  rt.show_modal("title")
  assert_eq(rt.stack_depth(), 1)
  rt.activate(&caps)
  assert_true(caps.started)
  rt.return_modal()
  assert_eq(rt.stack_depth(), 0)
}

///|
test "vbox layout stacks buttons vertically" {
  let app = UiApp::new()
  app.register_modal(
    "m",
    VBox(x=Some(100.0), y=Some(200.0), children=[
      Button(label="A", action_id=0, visible=Always),
      Button(label="B", action_id=1, visible=Always),
    ]),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("m")
  let ops = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty())
  // Expect two button panels with y increasing by line height (~56-64)
  assert_true(ops.length() >= 2)
}
```

- [ ] **Step 2: Run — FAIL**

```bash
moon test -p runtime -v 2>&1 | tail -40
```

- [ ] **Step 3: Implement UiRuntime**

Required API (names may match style of existing code):

```text
UiRuntime {
  app: UiApp
  mut mode: UiMode          // reuse existing UiMode enum from screen.mbt or move to ui_types
  mut stack: Array[ModalInstance { name, mode?, focus }]
  mut save_slots: Int
  mut prefs: Prefs          // keep prefs on runtime (migrate from ScreenState)
}

from_app(app, save_slots) -> UiRuntime
show_modal(name, mode?)
return_modal()
hide_modal(name?)
focus_delta(caps, delta)
activate(caps)
handle_pointer(caps, x, y)  // hit-test focusables; activate
paint_modal(canvas, bind) -> Array[UiDrawOp]
paint_hud(canvas, bind) -> Array[UiDrawOp]   // only caller decides when to show
focusables_top(bind) -> Array[(action_kind, action_id or choice_index)]
```

**Layout rules (match Phase 3 screen geometry constants):**
- Default button: w=400, h=52, line_h=64, font 30
- VBox/HBox flow children; Fixed absolute
- Focus ring: `focused=true` on matching button/choice row → resource `ui.button_focus` vs `ui.button`
- `VisiblePred` evaluation uses `UiBindCtx { has_text, has_choices, prefs, occupied[], modal_mode?, vars }`
- `ChoiceList`: for each option label from bind, one focusable row; activate → `caps.confirm_choice(i)`
- Load mode filtering for slot buttons: if button handler is save/load slot, **std_ui** should use VisibleIf(SlotOccupied) for load mode rows OR runtime skips focus for nodes with `VisiblePred::SlotOccupied` false

**Paint:** emit `UiDrawOp` sprites for Panel/Button/Image and text-bearing ops for Text/Button labels (render expands glyphs later).

Move `UiMode` into `ui_types.mbt` if that avoids circular deps; keep `Title|Playing|Menu`.

- [ ] **Step 4: Tests PASS**

```bash
moon test -p runtime
```

- [ ] **Step 5: Commit**

```bash
git add runtime/ui_runtime.mbt runtime/ui_test.mbt runtime/ui_types.mbt
git commit -m "feat(runtime): UiRuntime modal stack, focus, layout, paint ops"
```

---

## Task 3: Engine implements Capabilities; dual-path input

**Files:**
- Modify: `runtime/engine.mbt`
- Modify: `runtime/engine_test.mbt`
- Modify: `runtime/host.mbt` or stage ui ops drain
- Keep `ScreenState` temporarily **or** replace field `screens` with `ui: UiRuntime` in one step if tests updated together

**Recommended:** Replace `Engine.screens : ScreenState` with `Engine.ui : UiRuntime` + keep `prefs`/`save_slots`/`slot_blobs` accessors. Update all references in one task to avoid dual stacks.

- [ ] **Step 1: Failing engine tests**

```mbt
///|
test "boot_title shows title modal via UiRuntime" {
  let ir = @script.compile_to_ir(
    #|- scene "entrypoint"
    #|  @sys.nop
    ,
    file="t.yuki",
  )
  let app = @runtime.UiApp::new()
  let _ = app.button("Start", fn(c) { c.start_game() })
  // register full title tree
  app.register_modal("title", /* vbox with Start button using app.button */)
  let eng = @runtime.Engine::from_ir_with_ui(ir, entry="entrypoint", app~)
  eng.boot_title()
  assert_true(eng.ui.mode is @runtime.UiMode::Title)
  assert_eq(eng.ui.stack_depth(), 1)
}

///|
test "menu open pauses narrative advance" {
  // Playing, show game_menu, Advance should not consume dialogue yield
}
```

Adapt to existing compile helpers in `engine_test.mbt`.

- [ ] **Step 2: Run — FAIL** (no `from_ir_with_ui` yet)

- [ ] **Step 3: Wire Engine**

```text
Engine::from_ir(..., app~: UiApp = UiApp::new())
  ui = UiRuntime::from_app(app, save_slots)
  mode Playing, empty stack (tests)
boot_title: if modals contains "title" -> Title + show_modal("title") else Playing
impl Capabilities for Engine:
  start_game / quit_to_title — port from current methods
  show_modal -> ui.show_modal
  return_modal -> ui.return_modal
  save_slot/load_slot — existing slot_blobs + save_json
  confirm_choice / advance — existing methods
  prefs — ui.prefs

tick routing:
  drain_ui_ops -> show_modal/hide_modal
  if stack non-empty OR mode Title: tick_ui (focus/activate/OpenMenu=return)
  else: existing narrative apply_intent + playing ticks

OpenMenu when Playing empty stack: show_modal("game_menu")
```

Remove calls to `ScreenState::activate` / `focusables` with `ScreenAction`.

Update `save.mbt` / prefs paths that read `eng.screens.prefs` → `eng.ui.prefs`.

- [ ] **Step 4:**

```bash
moon test -p runtime
```

Fix all broken refs to `.screens`.

- [ ] **Step 5: Commit**

```bash
git add runtime/engine.mbt runtime/engine_test.mbt runtime/save.mbt runtime/*.mbt
git commit -m "feat(runtime): Engine Capabilities and UiRuntime input gating"
```

---

## Task 4: render consumes UiDrawOp; remove dialogue hard path

**Files:**
- Modify: `render/snapshot.mbt`
- Modify: `render/snapshot_test.mbt`
- Modify: `render/types.mbt`
- Modify: `host_web/main.mbt` (`export_frame` build_draw_list call site)

- [ ] **Step 1: Failing test**

```mbt
///|
test "dialogue box not emitted without ui draw ops" {
  let st = @runtime.Stage::new()
  st.set_text("Hero", "Hello")
  let view = /* StageView from stage */
  let dl = @render.build_draw_list(view, @render.UiLayout::default_fhd(), ui_ops=[])
  var has_dialogue = false
  for s in dl.sprites {
    if s.resource == @render.ui_dialogue_box {
      has_dialogue = true
    }
  }
  assert_false(has_dialogue)
}

///|
test "ui draw ops emit button sprite" {
  let ops = [
    @runtime.UiDrawOp::{
      kind: 0,
      resource: @render.ui_button,
      x: 10.0, y: 20.0, w: 400.0, h: 52.0,
      opacity: 1.0, z: 3000,
      text: Some("Start"),
      font_size: 30.0,
      focused: false,
    },
  ]
  let dl = @render.build_draw_list_with_ui_ops(/* empty view */, layout, ops)
  assert_true(dl.sprites.length() >= 1)
}
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implement**

1. Change `build_draw_list*` signature:
   - Remove `screens? : ScreenState` and `occupied_slots?`
   - Add `ui_ops? : Array[UiDrawOp]` (or split hud_ops + modal_ops already merged by Engine)
2. Delete dialogue/nameplate/choice block that uses `view.text` / `view.choices` + `UiLayout` dialogue fields
3. Delete `emit_screen_node` / `resolve_screen_text` ScreenDef path
4. For each `UiDrawOp`: push sprite; if `text` Some, run existing glyph layout helper
5. Dim veil: either a dedicated op from UiRuntime when menu open, or Engine prepends dim op — **pin: UiRuntime.paint_modal prepends dim when mode Menu or stack_depth>1**
6. Shrink `UiLayout` fields used only for dialogue — keep canvas_w/h, default font metrics for glyph path; leave unused fields only if too churny (prefer delete dead fields and fix compile errors)

Host frame path:

```text
ops = []
if modal: ops.append(ui.paint_modal(...))
else if Playing: ops.append(ui.paint_hud(...))
build_draw_list(view, layout, ui_ops=ops)
```

Bind ctx from Engine: text present, choices, prefs, slot occupied array, modal mode.

- [ ] **Step 4:**

```bash
moon test -p render -p runtime
```

- [ ] **Step 5: Commit**

```bash
git add render/ host_web/main.mbt
git commit -m "feat(render): paint UiDrawOp only; remove hard-coded dialogue UI"
```

---

## Task 5: std_ui package — default HUD + four modals

**Files:**
- Create: `std_ui/moon.pkg`
- Create: `std_ui/lib.mbt`
- Create: `std_ui/hud.mbt`
- Create: `std_ui/modals.mbt`
- Optional tests: `std_ui` blackbox if package is testable; else engine integration tests

`std_ui/moon.pkg`:

```mbt
import {
  "moonsight/moonsight/runtime",
}
```

- [ ] **Step 1: Integration test in runtime or host style**

In `runtime/engine_test.mbt` (or new `std_ui` test via engine):

```mbt
///|
test "std_ui title start_game reaches playing" {
  let ir = @script.compile_to_ir(#|- scene "entrypoint"
#|  Hero:Hi
, file="d.yuki")
  let app = @runtime.UiApp::new()
  @std_ui.register(app)  // only if runtime tests can import std_ui — else construct equivalent in test
  ...
}
```

If `runtime` must not import `std_ui` (dependency direction), put integration test under a small package or test via `host_web` later; unit-test trees by exporting builders:

```mbt
// std_ui/lib.mbt
pub fn register(app : @runtime.UiApp) -> Unit {
  app.set_hud(build_hud(app))
  app.register_modal("title", build_title(app))
  app.register_modal("game_menu", build_game_menu(app))
  app.register_modal("save_load", build_save_load(app))
  app.register_modal("settings", build_settings(app))
}
```

**HUD geometry** (port from `UiLayout::default_fhd` numbers):

```text
canvas 1920x1080
dialogue panel: x=48 y=756 w=1824 h=324 resource ui.dialogue_box
nameplate: x=80 y=788 w=360 h=48
body TextBind DialogueBody at text origin
ChoiceList above box (y≈556)
VisibleIf HasText / HasChoices
```

**Modals:** port labels/actions from `std_screens/*.yuki` using `app.button` + Capabilities.

save_load: for i in 0..5 (or dynamic save_slots — **pin:** build 20 max buttons with VisibleIf always for first N is hard without runtime slot count in tree). **Pin:** `build_save_load(app, slots=6)` fixed 6 matching default; Engine/runtime save_slots still clamps; if config ≠ 6, Task 7 may pass slots into register. For Phase 4.0 use **6 buttons** like current std yuki; read `save_slots` from app if you add `app.save_slots` field set before register.

- [ ] **Step 2: Implement std_ui**

- [ ] **Step 3: host_web imports std_ui and registers on init**

```mbt
// host_web/main.mbt init
let app = @runtime.UiApp::new()
@std_ui.register(app)
engine = Engine::from_ir_with_ui(..., app~)
```

Remove `load_screens_json` body or make it no-op returning 0 for brief JS compat, then Task 7 cleans JS.

- [ ] **Step 4:**

```bash
moon check
moon test
```

- [ ] **Step 5: Commit**

```bash
git add std_ui/ host_web/ runtime/
git commit -m "feat(std_ui): default HUD and system modals on UiApp"
```

---

## Task 6: Cut Screen DSL — parser error + remove IR path

**Files:**
- Modify: `script/parser.mbt` (or compile entry)
- Modify: `script/parser_test.mbt` / new test
- Delete or stop exporting: `script/screen_ir.mbt`, `screen_lower.mbt`, related tests
- Modify: `script/compile.mbt` if it merges screens
- Modify: `cmd/moonsightc/build.mbt` — stop `merge_project_screens` / `screens.json`
- Delete: `std_screens/*.yuki` when std_ui complete
- Delete: `runtime/screen.mbt` if fully replaced

- [ ] **Step 1: Failing test**

```mbt
///|
test "parser rejects screen declarations with migration message" {
  let src =
    #|- screen "title"
    #|  vbox:
    #|    button "X" action=noop
  try {
    ignore(@script.compile_to_ir(src, file="bad.yuki"))
    fail("expected error")
  } catch {
    e => {
      let msg = /* stringify diagnostic */
      assert_true(msg.contains("screen") || msg.contains("UiApp") || msg.contains("MoonBit UI"))
    }
  }
}
```

Use the package’s real error API (`Diag`, raise, etc. — mirror existing compile error tests).

- [ ] **Step 2: Implement reject**

When parser sees top-level `- screen`, emit diagnostic:

```text
`- screen` was removed in Phase 4; define UI in a MoonBit ui package (see docs/ui-moonbit.md)
```

- [ ] **Step 3: Remove screens.json emission from moonsightc**

In `build.mbt`, delete merge/write screens.json; update any check path.

- [ ] **Step 4: Delete dead screen IR files and tests; fix `moon test`**

- [ ] **Step 5: Commit**

```bash
git add script/ cmd/moonsightc/ runtime/ std_screens/
git commit -m "feat!: remove Screen DSL path; reject - screen in projects"
```

---

## Task 7: moonsightc ui_package link workspace

**Files:**
- Create: `cmd/moonsightc/ui_link.mbt`
- Modify: `cmd/moonsightc/config.mbt` — parse `ui_package`
- Modify: `cmd/moonsightc/build.mbt` — invoke link + wasm build
- Modify: `host_web/js_glue/boot.js` — no screens.json required; always boot_title
- Modify: `host_web/moon.pkg` / exports list

**Pinned link strategy:**

```text
moonsightc build <game> -o <out>:
  1. compile yuki -> game.msb (unchanged narrative)
  2. read ui_package path relative to game root (optional)
  3. write link workspace under <out>/.link/ or repo _build/link/<slug>/:
       - moon.mod name = moonsight/moonsight (or moonsight/game_host)
       - packages: copy or path-depend engine packages is heavy;
         PRACTICAL PIN for v1:
         a) Always build in-repo host_web + std_ui (default product).
         b) If ui_package set: copy project ui/*.mbt into
            `host_web/generated_game_ui/` (gitignored) with moon.pkg
            importing runtime, export `pub fn register(app)` wrapping user
            module OR user package is the copied sources with required
            `register` symbol.
         c) host_web/main.mbt calls:
              @std_ui.register(app)
              @generated_game_ui.register(app)  // empty stub when no package
         d) When no ui_package, generated_game_ui/lib.mbt is:
              pub fn register(_app) { () }
  4. moon build --target wasm-gc --release host_web
  5. copy wasm + js_glue to out (existing)
  6. do not write screens.json
```

Empty stub package committed as `host_web/generated_game_ui/` with no-op `register`, overwritten on build when `ui_package` present (document that `generated_game_ui` is build output — prefer writing under `_build/` and pointing moon.pkg is harder). **Pin:** keep `host_web/game_ui_stub/` always no-op in git; moonsightc copies user sources over `host_web/.game_ui_overlay/` which is gitignored and imported only if present — simplest robust approach:

**Final pin for implementer:**

1. Commit `std_ui` + `host_web` calling only `@std_ui.register(app)`.
2. Add optional second call via **conditional source generation**: moonsightc writes `host_web/game_ui_register.mbt` (gitignored) either no-op or `pub fn register_game_ui(app) { @game_ui.register(app) }` and path-maps game package.

If MoonBit cannot path-map outside module easily, **copy** project `ui/*.mbt` into `host_web/_project_ui/` (gitignored) as package `project_ui` with:

```mbt
// moon.pkg
import { "moonsight/moonsight/runtime" }
```

and `host_web` imports `project_ui` always; default stub:

```mbt
pub fn register(_app : @runtime.UiApp) -> Unit { () }
```

moonsightc replaces stub content with project files when `ui_package` set.

- [ ] **Step 1: config parse test** (native moonsightc tests if any; else manual)

`moonsight.json`:

```json
{ "ui_package": "ui", "save_slots": 6 }
```

- [ ] **Step 2: Implement copy/stub + build hook**

- [ ] **Step 3: boot.js**

```javascript
// After load_msb / load_source:
// remove hard dependency on screens.json
if (typeof exports_.boot_title === "function") {
  exports_.boot_title();
}
// keep prefs/slots hydration
```

Remove export `load_screens_json` when unused (update moon.pkg exports).

- [ ] **Step 4: Build demo**

```bash
export CC=gcc
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
# serve and smoke title → start
```

- [ ] **Step 5: Commit**

```bash
git add cmd/moonsightc/ host_web/ .gitignore
git commit -m "feat(moonsightc): link project ui package into host wasm"
```

Add to `.gitignore`:

```
host_web/_project_ui/
host_web/game_ui_register.mbt
```

(if those paths used)

---

## Task 8: Demo sample ui override + docs + full verification

**Files:**
- Create: `docs/ui-moonbit.md`
- Modify: `docs/screen-language.md` (obsolete banner)
- Modify: `docs/project-layout.md`, `docs/host-commands.md`, `docs/moon-yuki-subset.md`, `README.md`
- Optional: `demo/game/ui/lib.mbt` + `moonsight.json` `ui_package`
- Remove leftover screens from demo if any

- [ ] **Step 1: Write `docs/ui-moonbit.md`**

Contents must include:
- Dual surface model
- `register` / `set_hud` / `register_modal`
- Capabilities table
- TextBind / VisibleIf
- `ui_package` in moonsight.json
- Migration from `- screen`
- `@ui.show` / `@ui.hide` still work

- [ ] **Step 2: Optional demo override**

`demo/game/ui/lib.mbt`:

```mbt
pub fn register(app : @runtime.UiApp) -> Unit {
  // override title label only by re-registering title modal
  app.register_modal("title", /* custom tree */)
}
```

- [ ] **Step 3: Full verification**

```bash
cd /mnt/nvme1n1p2/moonsight
export CC=gcc
moon check
moon test
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
# manual: title, start, dialogue HUD, choice, Esc menu, save/load, settings
```

Expected: all tests green; playable demo without `screens.json`.

- [ ] **Step 4: Commit**

```bash
git add docs/ demo/ README.md
git commit -m "docs: MoonBit UI authoring guide and Phase 4 scope"
```

---

## Task 9: Cleanup dead ScreenState / exports / registry alignment

**Files:** any remaining references to `ScreenDef`, `ScreenAction`, `load_screens_json`, `std_screens`

- [ ] **Step 1:** `rg -n "ScreenDef|ScreenAction|screens\.json|std_screens|load_screens_json|emit_screen_node" --glob '!_build/**' --glob '!docs/superpowers/**'`

- [ ] **Step 2:** Delete or update every hit outside historical specs.

- [ ] **Step 3:**

```bash
moon test
moon check
```

- [ ] **Step 4: Commit**

```bash
git commit -am "chore: remove residual Screen DSL symbols"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| runtime/ui kernel | 1–2 |
| HudSlot + ModalStack | 2–3 |
| Capabilities + callbacks | 1, 3, 5 |
| std_ui defaults | 5 |
| Same-wasm game UI | 7 |
| render decouple dialogue | 4 |
| Cut `- screen` / screens.json | 6–7 |
| Keep `@ui.show`/`hide` | 3 (drain ops) |
| demo + docs + tests | 8–9 |
| prefs/slots/save unchanged | 3 (port), 5 |

---

## Risk notes for implementers

1. **MoonBit fn types in Map** — if `(Capabilities) -> Unit` cannot be stored, use `trait Handler { fn run(Self, &Capabilities) }` objects or integer opcodes for std only (avoid; prefer fn).  
2. **Do not keep dual ScreenState + UiRuntime** past Task 3 — double input bugs.  
3. **generated project UI** must be gitignored so builds do not dirty the tree unexpectedly; stub stays committed.  
4. **Choice focus:** prefer ChoiceList + `confirm_choice` so Stage.choice_focus stays in sync (update Stage selected index when HUD moves focus).  
5. **YAGNI:** no slider, no theme files, no second wasm.

---

## Self-review (plan author)

- Spec §1–8 mapped to tasks 1–9.  
- No TBD steps; link strategy pinned to copy-in `_project_ui` stub pattern.  
- Types consistent: `UiApp` / `UiRuntime` / `Capabilities` / `UiDrawOp` / `UiBindCtx`.  
- TDD order on core kernel; integration after.  
