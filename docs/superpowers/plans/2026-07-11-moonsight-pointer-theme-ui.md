# Pointer Hit-Test, Theme System & Amber Soft UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Svelte-host mouse input, route all pointer hits through engine `LaidFocus`, add hover/cursor, and ship Amber Soft theme pack + demo/host shell polish.

**Architecture:** Host maps canvas coords → `export_pointer(x,y,phase)`; engine owns hit-test, slider click-to-ratio, miss→Advance (Playing only), and hover state. Paint emits stable logical `ui.*` roles including `*_hover`; host loads `public/themes/amber_soft/theme.json` textures with solid fallbacks. Keyboard intents stay on `export_frame`.

**Tech Stack:** MoonBit (`moon test` / `moon check` / `moon build --target wasm-gc`), Vite + Svelte 5 + TS (`apps/host-web`), WebGPU adapter, PNG theme assets (generated or hand-authored).

**Spec:** `docs/superpowers/specs/2026-07-11-moonsight-pointer-theme-ui-design.md`

**Pinned defaults:**

| Item | Choice |
|------|--------|
| Pointer API | `export_pointer(x, y, phase) -> hover_kind`; phase `0=move`, `1=down`, `3=leave` |
| Miss click | Playing + empty stack + gates pass → `Advance` (full canvas, not only dialogue box) |
| Slider click | Set pref from x-ratio on track; no drag |
| Hover vs focus | Focus resource wins; else hover resource |
| Theme path | `apps/host-web/public/themes/amber_soft/` |
| Dual host | Wire Svelte first; mirror pointer + theme load into `js_glue` in same plan |
| Same-frame key+pointer | On pointerdown, host sets `pendingIntent = 0` after `export_pointer` (or skip key intent that frame) |

---

## File map

| Path | Role |
|------|------|
| `runtime/ui_types.mbt` | `UiDrawOp.hovered`; hover kind helpers if needed |
| `runtime/ui_runtime.mbt` | `hover` index; `handle_pointer`→`Bool`; slider ratio; `pointer_hover` / leave; paint focus/hover/idle resources |
| `runtime/ui_test.mbt` | Pointer, slider click, hover paint tests |
| `runtime/engine.mbt` | `Engine::pointer_event` (gate + miss Advance) |
| `runtime/engine_test.mbt` | Engine-level pointer / wait gate tests |
| `render/snapshot.mbt` | New logical resource name constants |
| `host_web/main.mbt` | `export_pointer`, intern new ui roles |
| `host_web/moon.pkg` | Export `export_pointer` |
| `apps/host-web/src/lib/gameSession.ts` | Wire pointer; remove CHOICE_LAYOUT; cursor; theme boot |
| `apps/host-web/src/lib/theme.ts` | Load `theme.json`, apply solids/files to GPU |
| `apps/host-web/src/adapters/webgpu_bridge.js` | `registerTexture` / solid from theme; keep placeholders as last resort |
| `apps/host-web/src/App.svelte` + `app.css` | Amber Soft shell chrome |
| `apps/host-web/public/themes/amber_soft/**` | Full skin pack |
| `apps/host-web/scripts/gen-amber-soft-theme.mjs` | Generate PNG panels if no art |
| `host_web/js_glue/boot.js` + `webgpu_bridge.js` | Parity pointer + theme |
| `demo/game/ui/lib.mbt` | Title/demo branding polish |
| `demo/game/moonsight.json` | Optional `"theme": "amber_soft"` |
| `cmd/moonsightc/build.mbt` | Ensure themes copy with host dist (if not already via Vite public/) |
| `docs/play-input.md`, `docs/ui-moonbit.md` | Document pointer + theme |

---

### Task 1: `handle_pointer` returns hit + slider click ratio

**Files:**
- Modify: `runtime/ui_runtime.mbt`
- Modify: `runtime/ui_test.mbt`
- Modify: `runtime/ui_types.mbt` (only if helpers needed)

- [ ] **Step 1: Write failing tests**

Append to `runtime/ui_test.mbt`:

```mbt
///|
test "handle_pointer returns false on miss true on hit" {
  let app = UiApp::new()
  let mut n = 0
  let id = app.alloc_action(fn(_c : &Capabilities) { n = n + 1 })
  app.register_modal(
    "m",
    UiNode::VBox(
      x=Some(100.0),
      y=Some(200.0),
      children=[
        UiNode::Button(label="Hit", action_id=id, visible=VisiblePred::Always),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  let caps = FakeCaps::new()
  let c : &Capabilities = caps
  rt.show_modal("m")
  rt.sync_bind(UiBindCtx::empty())
  assert_false(rt.handle_pointer(c, 10.0, 10.0))
  assert_eq(n, 0)
  assert_true(rt.handle_pointer(c, 150.0, 220.0))
  assert_eq(n, 1)
}

///|
test "handle_pointer slider sets pref from x ratio" {
  let app = UiApp::new()
  app.register_modal(
    "settings",
    UiNode::Fixed(
      x=100.0,
      y=100.0,
      w=Some(400.0),
      h=Some(24.0),
      children=[
        UiNode::Slider(
          key="master_volume",
          x=0.0,
          y=0.0,
          w=400.0,
          h=24.0,
          visible=VisiblePred::Always,
        ),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  let caps = FakeCaps::new()
  let c : &Capabilities = caps
  rt.show_modal("settings")
  rt.sync_bind(UiBindCtx::empty())
  // Mid-track: origin (100,100), width 400 → x=300
  assert_true(rt.handle_pointer(c, 300.0, 112.0))
  let p = caps.prefs()
  assert_true(p.master_volume > 0.45 && p.master_volume < 0.55)
}
```

Confirm `walk_ui_node` places Fixed children at parent origin (read Fixed branch). Slider click must call `caps.set_pref_f` — FakeCaps already implements it.

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p moonsight/moonsight/runtime`

Expected: FAIL — `handle_pointer` still returns `Unit` / slider no-op.

- [ ] **Step 3: Implement**

In `runtime/ui_runtime.mbt`:

1. Change signature:

```mbt
pub fn UiRuntime::handle_pointer(
  self : UiRuntime,
  caps : &Capabilities,
  x : Double,
  y : Double,
) -> Bool {
  ...
  // on hit: ...; return true
  // end: return false
}
```

2. Slider branch:

```mbt
UiFocusTarget::Slider(key) => {
  let t = ((x - f.x.to_double()) / f.w.to_double()).clamp(0.0, 1.0)
  // Use a small helper:
  apply_slider_normalized(caps, key, t)
}
```

Add:

```mbt
fn apply_slider_normalized(caps : &Capabilities, key : String, t : Double) -> Unit {
  let t = if t < 0.0 { 0.0 } else if t > 1.0 { 1.0 } else { t }
  match key {
    "text_speed" => caps.set_pref_f(key, 0.25 + t * (3.0 - 0.25))
    "master_volume" | "bgm_volume" | "se_volume" => caps.set_pref_f(key, t)
    _ => ()
  }
}
```

(Use MoonBit clamp style consistent with repo — `if` chains if no `.clamp`.)

3. Update existing test `handle_pointer hits button and activates` to assert return values.

- [ ] **Step 4: Run tests**

Run: `moon test -p moonsight/moonsight/runtime`

Expected: PASS for new + updated pointer tests.

- [ ] **Step 5: Commit**

```bash
git add runtime/ui_runtime.mbt runtime/ui_test.mbt
git commit -m "feat(runtime): handle_pointer hit bool and slider click ratio"
```

---

### Task 2: Hover index + paint `*_hover` / `hovered`

**Files:**
- Modify: `runtime/ui_types.mbt` (`UiDrawOp` add `hovered : Bool`)
- Modify: `runtime/ui_runtime.mbt`
- Modify: `runtime/ui_test.mbt`
- Modify: all sites constructing `UiDrawOp` (grep `focused:` in `runtime/` and `render/`)
- Modify: `render/snapshot.mbt` (constants)

- [ ] **Step 1: Add resource constants**

In `render/snapshot.mbt` after existing ui lets:

```mbt
pub let ui_button_hover : String = "ui.button_hover"
pub let ui_choice_row : String = "ui.choice_row" // if not already only in paint strings
pub let ui_choice_row_focus : String = "ui.choice_row_focus"
pub let ui_choice_row_hover : String = "ui.choice_row_hover"
pub let ui_slider_track : String = "ui.slider_track"
pub let ui_slider_fill : String = "ui.slider_fill"
```

Note: `ui_choice_row` may already exist — extend, do not duplicate.

In `ui_runtime.mbt` local lets, add:

```mbt
let ui_res_button_hover : String = "ui.button_hover"
let ui_res_choice : String = "ui.choice_row"
let ui_res_choice_focus : String = "ui.choice_row_focus"
let ui_res_choice_hover : String = "ui.choice_row_hover"
let ui_res_slider_track : String = "ui.slider_track"
let ui_res_slider_fill : String = "ui.slider_fill"
```

- [ ] **Step 2: Write failing hover tests**

```mbt
///|
test "pointer_hover sets hover and paint uses button_hover" {
  let app = UiApp::new()
  let id = app.alloc_action(fn(_c : &Capabilities) { () })
  app.register_modal(
    "m",
    UiNode::VBox(
      x=Some(100.0),
      y=Some(200.0),
      children=[
        UiNode::Button(label="A", action_id=id, visible=VisiblePred::Always),
        UiNode::Button(label="B", action_id=id, visible=VisiblePred::Always),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("m")
  let bind = UiBindCtx::empty()
  rt.sync_bind(bind)
  // Default focus index 0; hover index 1
  assert_true(rt.pointer_hover(100.0 + 10.0, 200.0 + 64.0 + 10.0)) // second button row
  let ops = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind~)
  let mut found_hover = false
  for op in ops {
    if op.resource == "ui.button_hover" || op.hovered {
      found_hover = true
    }
  }
  assert_true(found_hover)
  rt.pointer_leave()
  // after leave, no hover resource on unfocused button
}
```

Tune Y using `ui_line_h` (64) geometry from `ui_runtime.mbt`.

- [ ] **Step 3: Implement hover state machine**

`UiRuntime` fields:

```mbt
mut hover : Int  // -1 = none; init -1 in from_app
```

Methods:

```mbt
/// Returns true if some focusable contains (x,y).
pub fn UiRuntime::pointer_hover(self : UiRuntime, x : Double, y : Double) -> Bool

pub fn UiRuntime::pointer_leave(self : UiRuntime) -> Unit {
  self.hover = -1
}

/// 0=none, 1=button, 2=choice, 3=slider
pub fn UiRuntime::hover_kind(self : UiRuntime) -> Int
```

`pointer_hover`: collect focusables, set `self.hover` to index or -1.

In `walk_ui_node` for Button / Choice / Slider paint:

```mbt
let focused = idx == st.focus_index
let hovered = (!focused) && (idx == st.hover_index)
// Pass hover_index via UiWalkState
let res = if focused {
  ui_res_button_focus
} else if hovered {
  ui_res_button_hover
} else {
  ui_res_button
}
```

Choice rows: use `ui.choice_row*` resources (not button).  
Slider track/fill: use `ui.slider_track` / `ui.slider_fill`.

Extend `UiWalkState`:

```mbt
hover_index : Int  // -1 if none
```

Set from `self.hover` when painting.

`UiDrawOp`:

```mbt
hovered : Bool
```

Update every `{ ... focused: false }` construction to `focused: false, hovered: false`.

- [ ] **Step 4: Run tests**

Run: `moon test -p moonsight/moonsight/runtime`  
Also: `moon test -p moonsight/moonsight/render` if snapshot tests construct `UiDrawOp`.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add runtime/ render/snapshot.mbt
git commit -m "feat(runtime): UI hover state and hover/choice/slider resources"
```

---

### Task 3: `Engine::pointer_event` (gates + miss → Advance)

**Files:**
- Modify: `runtime/engine.mbt`
- Modify: `runtime/engine_test.mbt`

- [ ] **Step 1: Write failing engine tests**

```mbt
///|
test "pointer miss advances dialogue when Playing" {
  // Build minimal engine with dialogue Yield + incomplete or complete text
  // Pattern: copy existing engine_test dialogue setup (from_ir + std_ui)
  ...
  eng.sync_ui_bind()
  let kind = eng.pointer_event(50.0, 50.0, phase=1) // down, empty HUD miss if no choices
  // After: typewriter completed or wait became Running — match Advance semantics
}

///|
test "pointer down ignored while wait_remaining" {
  ...
  eng.stage.wait_remaining = 1.0
  eng.pointer_event(100.0, 100.0, phase=1)
  // wait still Yield, text unchanged
}

///|
test "pointer hits choice while Choose" {
  ...
  // set choices, vm.wait = Choose
  eng.pointer_event(choice_x, choice_y, phase=1)
  // choice confirmed
}
```

Use real geometry from `std_ui` HUD (`hud_choice_x/y`) or register a simple HUD in the test app.

- [ ] **Step 2: Run to verify fail**

Run: `moon test -p moonsight/moonsight/runtime -v` (filter by test name if supported)

Expected: FAIL — `pointer_event` missing.

- [ ] **Step 3: Implement `Engine::pointer_event`**

```mbt
/// phase: 0=move, 1=down, 3=leave
/// returns hover_kind after event (0 none, 1 button, 2 choice, 3 slider)
pub fn Engine::pointer_event(
  self : Engine,
  x : Double,
  y : Double,
  phase~ : Int,
) -> Int {
  self.sync_ui_bind()
  if phase == 3 {
    self.ui.pointer_leave()
    return 0
  }
  if phase == 0 {
    ignore(self.ui.pointer_hover(x, y))
    return self.ui.hover_kind()
  }
  // phase == 1 down
  ignore(self.ui.pointer_hover(x, y))
  let caps : &Capabilities = self
  let ui_active = self.ui.stack_depth() > 0 || (self.ui.mode is Title)
  if ui_active {
    ignore(self.ui.handle_pointer(caps, x, y))
    return self.ui.hover_kind()
  }
  // Playing, no modal
  if self.stage.wait_remaining > 0.0 {
    return self.ui.hover_kind()
  }
  if self.ui.handle_pointer(caps, x, y) {
    return self.ui.hover_kind()
  }
  // Miss → Advance (same path as keyboard)
  self.apply_intent(Advance)
  // If Apply left VM Running, run until wait so one click advances a line
  if self.vm.wait is Running {
    self.vm.run_until_wait(self.director, self.stage)
  }
  self.ui.hover_kind()
}
```

**Important:** Match keyboard Advance behavior for typewriter (first click completes text). `apply_intent(Advance)` already does this — do **not** double-run unless tests show IP stuck. Prefer:

```mbt
// Mirror the non-skip portion of tick for a single Advance without dt side effects:
self.apply_intent(Advance)
if self.vm.wait is Running {
  self.vm.run_until_wait(self.director, self.stage)
}
self.maybe_record_backlog() // if that is how complete_text records — check engine
```

Read existing `apply_intent` + backlog hooks; keep parity with one `tick(Advance)` narrative effects **except** do not advance `wait_remaining` / tweens (host still calls `export_frame` same frame with `intent=0` for dt).

**Recommended host contract (lock in):**

1. `export_pointer(x,y,1)` handles UI activate + narrative Advance/choice  
2. Same frame `export_frame(0, dt, skip)` only advances clocks — **no second Advance**

Document this in `play-input.md` Task 10.

If `apply_intent` alone is insufficient for Choose miss→confirm focus, call the same branch as `tick`’s Choose+Advance.

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add runtime/engine.mbt runtime/engine_test.mbt
git commit -m "feat(runtime): Engine.pointer_event with miss-Advance and gates"
```

---

### Task 4: Wasm `export_pointer`

**Files:**
- Modify: `host_web/main.mbt`
- Modify: `host_web/moon.pkg`
- Modify: intern list near `load_msb` / init for new ui resource strings

- [ ] **Step 1: Add export**

```mbt
///|
/// Pointer path: logical pixels, phase 0=move 1=down 3=leave.
/// Returns hover_kind: 0 none, 1 button, 2 choice, 3 slider.
pub fn export_pointer(x : Float, y : Float, phase : Int) -> Int {
  let s = session.val
  match s.engine {
    None => 0
    Some(eng) => eng.pointer_event(x.to_double(), y.to_double(), phase~)
  }
}
```

- [ ] **Step 2: Register export in `host_web/moon.pkg`**

Add `"export_pointer"` next to `"export_frame"`.

- [ ] **Step 3: Intern new logical names** (same place as `ui.button`):

```mbt
ignore(s.resources.intern("ui.button_hover"))
ignore(s.resources.intern("ui.choice_row_focus"))
ignore(s.resources.intern("ui.choice_row_hover"))
ignore(s.resources.intern("ui.slider_track"))
ignore(s.resources.intern("ui.slider_fill"))
```

- [ ] **Step 4: Build wasm**

Run: `moon build -p moonsight/moonsight/host_web --target wasm-gc`

Expected: success; export present (optional: `wasm-objdump` / load in host).

- [ ] **Step 5: Commit**

```bash
git add host_web/main.mbt host_web/moon.pkg
git commit -m "feat(host_web): export_pointer for engine hit-test"
```

---

### Task 5: Svelte host — wire pointer, fix dead clicks, remove CHOICE_LAYOUT

**Files:**
- Modify: `apps/host-web/src/lib/gameSession.ts`
- Modify: `apps/host-web/src/lib/intents.ts` (if needed)
- Modify: HostExports type for `export_pointer`

- [ ] **Step 1: Diagnose dead clicks (mandatory before claiming fix)**

Temporarily log in `onPointerDown`:

```ts
console.info("[ptr]", ev.clientX, ev.clientY, pointerToLogical(canvas, ev));
```

Run demo (`./moonsight-demo.sh` or vite). Confirm events fire. If not: check canvas stacking / `pointer-events` / zero size. Fix root cause (CSS or bind order).

- [ ] **Step 2: Extend exports type**

```ts
export_pointer?: (x: number, y: number, phase: number) => number;
```

- [ ] **Step 3: Replace choice hit-test path**

Delete `CHOICE_LAYOUT` and `choiceRowAt`.

```ts
const HOVER_NONE = 0;
// ...

const onPointerMove = (ev: PointerEvent) => {
  if (!this.exports_?.export_pointer) return;
  const { x, y } = pointerToLogical(canvas, ev);
  const kind = this.exports_.export_pointer(x, y, 0) | 0;
  this.applyCursor(canvas, kind);
};

const onPointerDown = (ev: PointerEvent) => {
  const { x, y } = pointerToLogical(canvas, ev);
  if (this.exports_?.export_pointer) {
    const kind = this.exports_.export_pointer(x, y, 1) | 0;
    this.applyCursor(canvas, kind);
    this.pendingIntent = INTENT_NONE; // pointer consumed interaction
  } else {
    // fallback only if wasm old: Advance
    this.pendingIntent = INTENT_ADVANCE;
  }
};

const onPointerLeave = () => {
  this.exports_?.export_pointer?.(0, 0, 3);
  canvas.style.cursor = "default";
};

canvas.addEventListener("pointermove", onPointerMove);
canvas.addEventListener("pointerdown", onPointerDown);
canvas.addEventListener("pointerleave", onPointerLeave);
// unbind symmetrically
```

```ts
private applyCursor(canvas: HTMLCanvasElement, kind: number): void {
  canvas.style.cursor =
    kind === 1 || kind === 2 ? "pointer" : kind === 3 ? "ew-resize" : "default";
}
```

- [ ] **Step 4: Manual verify**

1. Title: mouse Start  
2. Dialogue: mouse advance  
3. Choices: mouse pick  
4. Keyboard still works  
5. Cursor changes on buttons  

- [ ] **Step 5: Commit**

```bash
git add apps/host-web/src/lib/gameSession.ts
git commit -m "feat(host-web): engine export_pointer path; drop CHOICE_LAYOUT"
```

---

### Task 6: Theme loader + Amber Soft solids/PNG pack

**Files:**
- Create: `apps/host-web/src/lib/theme.ts`
- Create: `apps/host-web/scripts/gen-amber-soft-theme.mjs`
- Create: `apps/host-web/public/themes/amber_soft/theme.json` + PNGs
- Modify: `apps/host-web/src/adapters/webgpu_bridge.js`
- Modify: `apps/host-web/src/lib/gameSession.ts` (boot call)
- Mirror: `host_web/js_glue/webgpu_bridge.js` fallback colors at minimum

- [ ] **Step 1: Write `theme.json`**

```json
{
  "id": "amber_soft",
  "display_name": "Amber Soft",
  "fallback_solids": {
    "ui.dialogue_box": [22, 16, 20, 220],
    "ui.nameplate": [48, 36, 40, 230],
    "ui.choice_row": [40, 30, 36, 200],
    "ui.choice_row_focus": [120, 72, 48, 240],
    "ui.choice_row_hover": [90, 56, 42, 230],
    "ui.button": [48, 36, 40, 220],
    "ui.button_focus": [120, 72, 48, 240],
    "ui.button_hover": [90, 56, 42, 230],
    "ui.menu_dim": [8, 6, 10, 150],
    "ui.slider_track": [36, 28, 32, 200],
    "ui.slider_fill": [200, 140, 90, 240]
  },
  "roles": {
    "ui.dialogue_box": { "file": "dialogue_box.png" },
    "ui.nameplate": { "file": "nameplate.png" },
    "ui.choice_row": { "file": "choice_row.png" },
    "ui.choice_row_focus": { "file": "choice_row_focus.png" },
    "ui.choice_row_hover": { "file": "choice_row_hover.png" },
    "ui.button": { "file": "button.png" },
    "ui.button_focus": { "file": "button_focus.png" },
    "ui.button_hover": { "file": "button_hover.png" },
    "ui.menu_dim": { "file": "menu_dim.png" },
    "ui.slider_track": { "file": "slider_track.png" },
    "ui.slider_fill": { "file": "slider_fill.png" }
  }
}
```

- [ ] **Step 2: Generator script**

`apps/host-web/scripts/gen-amber-soft-theme.mjs`: use `pngjs` or pure uncompressed PNG writer to emit rounded-rect panels matching fallback colors into `public/themes/amber_soft/`. Document:

```bash
node apps/host-web/scripts/gen-amber-soft-theme.mjs
```

If adding dependency is undesirable, embed a minimal PNG encoder in the script (no new package) or use ImageData + canvas in Node if available. Prefer **zero new runtime deps**.

- [ ] **Step 3: `theme.ts`**

```ts
export type ThemeManifest = {
  id: string;
  display_name: string;
  fallback_solids: Record<string, [number, number, number, number]>;
  roles: Record<string, { file?: string }>;
};

export async function loadTheme(
  baseUrl: string, // "/themes/amber_soft"
  registerSolid: (id: string, rgba: number[]) => void,
  registerImage: (id: string, url: string) => Promise<void>,
): Promise<ThemeManifest> {
  const res = await fetch(`${baseUrl}/theme.json`);
  if (!res.ok) throw new Error(`theme load failed: ${res.status}`);
  const manifest = (await res.json()) as ThemeManifest;
  for (const [role, rgba] of Object.entries(manifest.fallback_solids)) {
    registerSolid(role, rgba);
  }
  for (const [role, spec] of Object.entries(manifest.roles)) {
    if (spec.file) {
      try {
        await registerImage(role, `${baseUrl}/${spec.file}`);
      } catch (e) {
        console.warn("[theme] image failed, solid kept", role, e);
      }
    }
  }
  return manifest;
}
```

Expose `Gpu.makePlaceholderSolid` / image upload as `registerSolid` / `registerImage` from adapter (add thin exports if missing — grep `makePlaceholderSolid` / texture upload paths).

- [ ] **Step 4: Call after Gpu.init, before first frame**

```ts
await loadTheme("/themes/amber_soft", ...);
```

- [ ] **Step 5: Update default cold placeholders** in `webgpu_bridge.js` to Amber Soft solids (so flash before theme load is warm, not cold blue).

- [ ] **Step 6: Commit**

```bash
git add apps/host-web/public/themes apps/host-web/src/lib/theme.ts apps/host-web/scripts apps/host-web/src/adapters/webgpu_bridge.js apps/host-web/src/lib/gameSession.ts
git commit -m "feat(host-web): Amber Soft theme pack and loader"
```

---

### Task 7: Demo UI + Svelte shell visual polish

**Files:**
- Modify: `demo/game/ui/lib.mbt`
- Modify: `demo/game/moonsight.json` (optional `"theme": "amber_soft"`)
- Modify: `apps/host-web/src/App.svelte`
- Modify: `apps/host-web/src/app.css`

- [ ] **Step 1: Demo title modal**

Improve hierarchy in `demo/game/ui/lib.mbt`:

```mbt
// Title "MoonSight" large + subtitle "Demo" + existing buttons
// Keep Capabilities actions identical
```

Optional: `app.set_hud(...)` only if demo needs branded dialogue; default std_ui HUD is OK if theme art carries look.

- [ ] **Step 2: Host shell CSS**

- Background gradient warm ink  
- `#status` / `#hint`: softer cards, amber hairline border, lower opacity when `running`  
- Font stack with Noto Sans already loaded  
- Optional short title bar text "MoonSight"  

Update hint copy to mention mouse:

```
Click: advance / menus · click choices · Esc menu · …
```

- [ ] **Step 3: Rebuild demo + visual check**

```bash
# project-typical:
moon build -p moonsight/moonsight/host_web --target wasm-gc
# copy wasm into apps/host-web/public if script does
cd apps/host-web && npm run build
# or moonsight-demo.sh
```

Manual: title → play → menu looks Amber Soft.

- [ ] **Step 4: Commit**

```bash
git add demo/game/ui/lib.mbt demo/game/moonsight.json apps/host-web/src/App.svelte apps/host-web/src/app.css
git commit -m "feat(demo,host-web): Amber Soft shell and demo title polish"
```

---

### Task 8: js_glue parity

**Files:**
- Modify: `host_web/js_glue/boot.js`
- Modify: `host_web/js_glue/webgpu_bridge.js`

- [ ] **Step 1: Mirror Task 5 pointer wiring** in `boot.js` (same phase codes; remove `choiceRowAt` / `CHOICE_LAYOUT`).

- [ ] **Step 2: Warm solids** in js_glue `webgpu_bridge.js` + optional fetch theme if path exists; if theme fetch is heavy, solids-only parity is minimum — document Svelte as default full theme path.

- [ ] **Step 3: Smoke** old path still boots (if still used by any script).

- [ ] **Step 4: Commit**

```bash
git add host_web/js_glue/boot.js host_web/js_glue/webgpu_bridge.js
git commit -m "fix(js_glue): pointer export_pointer parity and warm UI solids"
```

---

### Task 9: Documentation

**Files:**
- Modify: `docs/play-input.md`
- Modify: `docs/ui-moonbit.md`
- Modify: `README.mbt.md` (input bullet + theme note)

- [ ] **Step 1: play-input.md**

Add section **Pointer**:

| Input | Effect |
|-------|--------|
| Click empty (Playing) | Advance (engine) |
| Click button / choice / slider | Hit-test activate |
| Move | Hover + cursor |
| Leave canvas | Clear hover |

Note: `export_pointer` then `export_frame(0,dt,skip)` same frame; no double Advance.

- [ ] **Step 2: ui-moonbit.md**

Add **Themes**: logical roles table; path `themes/amber_soft`; host resolves files/solids; paint focused/hovered.

- [ ] **Step 3: Commit**

```bash
git add docs/play-input.md docs/ui-moonbit.md README.mbt.md
git commit -m "docs: pointer hit-test and Amber Soft theme author notes"
```

---

### Task 10: Full verification

- [ ] **Step 1: Unit tests**

```bash
moon test -p moonsight/moonsight/runtime
moon test -p moonsight/moonsight/render
moon test -p moonsight/moonsight/std_ui
moon check
```

Expected: all green.

- [ ] **Step 2: Manual checklist (spec §8.2)**

1. Title mouse Start / Settings  
2. Dialogue mouse advance  
3. Choice mouse select  
4. Esc menu mouse buttons  
5. Slider click halves  
6. Hover + cursor  
7. Keyboard regression  
8. Timed `@flow.wait` ignores click advance  

- [ ] **Step 3: Spec status**

Set design doc status line to `Approved / Implemented` or leave for PR — optional commit:

```bash
git add docs/superpowers/specs/2026-07-11-moonsight-pointer-theme-ui-design.md
git commit -m "docs: mark pointer-theme UI design implemented"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| P0 mouse works on Svelte | 5 (+ 3–4) |
| Engine hit-test Button/Choice/Slider | 1, 3 |
| Delete CHOICE_LAYOUT | 5, 8 |
| Miss → Advance Playing | 3 |
| Hover + `*_hover` | 2 |
| Cursor map | 5 |
| Theme system + amber_soft pack | 6 |
| Full skin roles | 2, 6 |
| std_ui/demo/host visual | 2, 6, 7 |
| wait_remaining gate | 3 |
| js_glue not half-broken | 8 |
| Docs | 9 |
| Tests | 1–3, 10 |

## Placeholder / consistency self-check

- No TBD steps; phase codes and hover_kind codes are fixed (0/1/3 and 0–3).  
- `handle_pointer` → `Bool` used consistently in Tasks 1 and 3.  
- Theme directory pinned to `apps/host-web/public/themes/amber_soft/`.  
- Same-frame intent rule: pointer then `export_frame(0,…)`.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-11-moonsight-pointer-theme-ui.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — execute in this session with `executing-plans`, checkpoints between batches  

Which approach?
