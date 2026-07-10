# MoonSight Q1 — 可认真玩 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Reach product gate **0.5**：session backlog, hold-to-skip, save/title confirm, prefs→mixer gains (no double multiply in JS), settings Slider, richer slot labels, and documented input/wait semantics.

**Architecture:** Engine owns `BacklogStore`, `pending_confirm`, and `skip_held` tick behavior; `audio.Mixer` multiplies logical volume by prefs gains and re-emits volume; `std_ui` adds `backlog` / `confirm` modals and Slider-based settings; host tracks Ctrl hold and H→backlog, extends intent codes for left/right/backlog.

**Tech Stack:** MoonBit (`moon test` / `moon check` / `moon build --target wasm-gc`), existing Engine / UiRuntime / std_ui / host_web / js_glue.

**Spec:** `docs/superpowers/specs/2026-07-11-moonsight-q1-playable-design.md`  
**Roadmap:** `docs/superpowers/specs/2026-07-11-moonsight-roadmap-design.md`

**Pinned defaults (from spec):**

| Item | Choice |
|------|--------|
| Backlog | Ring buffer capacity 100; session-only; clear on start/load/title |
| Skip | `tick(..., skip_held~)`; Ctrl hold; does not skip `wait_remaining`; no auto-choice; burst max 8 |
| Confirm | `OverwriteSave(i)`, `QuitToTitle`; default focus No |
| Volume | `out = logical * master * channel`; mixer source of truth; JS stops re-multiplying |
| Slider | New `UiNode::Slider`; MenuLeft/Right adjust |
| Save format | Stay v3; backlog not in save |

---

## File map

| Path | Role |
|------|------|
| `audio/mixer.mbt` | Pref gains fields; `apply_prefs` / `set_pref_gains`; `output_*` use gains; re-emit volume on apply |
| `audio/mixer_test.mbt` | Pref multiply + re-emit tests |
| `runtime/backlog.mbt` | **Create:** `BacklogEntry`, `BacklogStore` |
| `runtime/backlog_test.mbt` | **Create:** ring overflow, push, clear |
| `runtime/intent.mbt` | Add `MenuLeft`, `MenuRight`, `OpenBacklog` |
| `runtime/engine.mbt` | Backlog + confirm + skip_held + sync mixer prefs + slot_labels bind |
| `runtime/engine_test.mbt` | Integration tests for skip/confirm/backlog/prefs wire |
| `runtime/ui_caps.mbt` | `confirm_yes` / `confirm_no` / `request_quit_to_title` (if not folded into existing) |
| `runtime/ui_types.mbt` | `UiNode::Slider`; `UiBindCtx.slot_labels`; optional `ConfirmMessage` bind |
| `runtime/ui_runtime.mbt` | Layout/paint/focus for Slider; left/right on focused slider |
| `runtime/ui_test.mbt` | Slider focus/adjust tests |
| `runtime/stage.mbt` | Optional complete edge hook doc only — prefer Engine observe |
| `std_ui/modals.mbt` | backlog, confirm, settings sliders, game_menu History + Title confirm |
| `std_ui/lib.mbt` | register new modals |
| `std_ui/lib_test.mbt` | register contains backlog/confirm |
| `render/gpu.mbt` | intent codes 7/8/9 (+ document) |
| `host_web/main.mbt` | `export_frame` pass `skip_held` |
| `host_web/js_glue/boot.js` | ctrlHeld; H backlog; arrows left/right; volume path no double prefs |
| `docs/play-input.md` | **Create** |
| `docs/host-commands.md` / `docs/draw-list-pack.md` / `docs/ui-moonbit.md` / `README.md` | Cross-links + Q1 scope |
| `demo/game/main.yuki` | Optional one-line tip: H history, Ctrl skip |

---

## Task 1: Mixer prefs gains (TDD)

**Files:**
- Modify: `audio/mixer.mbt`
- Modify: `audio/mixer_test.mbt`

- [x] **Step 1: Write failing tests**

Append to `audio/mixer_test.mbt`:

```mbt
///|
test "output volume multiplies master and channel prefs" {
  let q = QueueBackend::new()
  let m = Mixer::with_backend((q : &AudioBackend))
  m.set_pref_gains(master=0.5, bgm=0.5, se=1.0)
  m.play_bgm("bgm_soft", volume=1.0)
  guard q.get(0) is Some(PlayBgm(volume~, ..)) else { fail("PlayBgm") }
  // 1.0 * 0.5 * 0.5 = 0.25
  assert_true(volume > 0.24 && volume < 0.26)
  m.play_se("click", volume=1.0)
  guard q.get(1) is Some(PlaySe(volume=se_vol, ..)) else { fail("PlaySe") }
  // 1.0 * 0.5 * 1.0 = 0.5
  assert_true(se_vol > 0.49 && se_vol < 0.51)
}

///|
test "apply_prefs re-emits SetBgmVolume when bgm playing" {
  let q = QueueBackend::new()
  let m = Mixer::with_backend((q : &AudioBackend))
  m.play_bgm("bgm_soft", volume=1.0)
  let _ = q.take()
  m.set_pref_gains(master=0.5, bgm=1.0, se=1.0)
  // Expect a volume event reflecting 0.5
  assert_true(q.len() >= 1)
  guard q.get(q.len() - 1) is Some(SetBgmVolume(volume~)) else {
    fail("SetBgmVolume")
  }
  assert_true(volume > 0.49 && volume < 0.51)
}
```

- [x] **Step 2: Run tests — expect FAIL**

```bash
cd /mnt/nvme1n1p2/moonsight && export CC=gcc && moon test -p audio -v 2>&1 | tail -40
```

Expected: FAIL — `set_pref_gains` missing or volumes still 1.0.

- [x] **Step 3: Implement**

In `audio/mixer.mbt`:

1. Add to `Mixer`:
   - `mut pref_master : Double` (default 1.0)
   - `mut pref_bgm : Double`
   - `mut pref_se : Double`
2. Replace `output_bgm_volume` / `output_se_volume` to multiply and clamp 0..1.
3. Add:

```mbt
pub fn Mixer::set_pref_gains(
  self : Mixer,
  master~ : Double,
  bgm~ : Double,
  se~ : Double,
) -> Unit {
  self.pref_master = clamp01(master)
  self.pref_bgm = clamp01(bgm)
  self.pref_se = clamp01(se)
  // If BGM playing, push updated output volume to backend.
  if self.bgm is Some(_) {
    self.backend.set_bgm_volume(output_bgm_volume(self, self.bgm_volume))
  }
}
```

Update all `output_bgm_volume(volume)` call sites to pass `self` if they become methods.

Keep `Mixer::new` / `with_backend` initializing prefs to 1.0.

- [x] **Step 4: Run tests — expect PASS**

```bash
export CC=gcc && moon test -p audio
```

- [x] **Step 5: Commit**

```bash
git add audio/mixer.mbt audio/mixer_test.mbt
git commit -m "feat(audio): multiply mixer output by prefs gains"
```

---

## Task 2: Engine sync prefs → mixer

**Files:**
- Modify: `runtime/engine.mbt`
- Modify: `runtime/engine_test.mbt` (or prefs path tests)

- [x] **Step 1: Write failing test**

```mbt
///|
test "set_pref volume updates global mixer gains" {
  @audio.reset_global_mixer()
  let q = @audio.QueueBackend::new()
  @audio.install_mixer(@audio.Mixer::with_backend((q : &@audio.AudioBackend)))
  let ir = /* minimal IR via existing test helpers — same as other engine tests */
  // Prefer: reuse pattern from engine_test that builds Engine with director.
  // After eng constructed:
  let caps : &Capabilities = eng
  caps.set_pref_f("master_volume", 0.5)
  caps.set_pref_f("bgm_volume", 0.5)
  @audio.global_mixer().play_bgm("x", volume=1.0)
  // Drain or inspect last PlayBgm volume == 0.25
}
```

Use the same IR/engine fixture style as existing `engine_test.mbt` tests (copy a minimal `from_ir` setup).

- [x] **Step 2: Run — expect FAIL** (mixer still 1.0 output)

- [x] **Step 3: Implement**

Add helper on Engine:

```mbt
fn Engine::sync_mixer_prefs(self : Engine) -> Unit {
  let p = self.ui.prefs
  @audio.global_mixer().set_pref_gains(
    master=p.master_volume,
    bgm=p.bgm_volume,
    se=p.se_volume,
  )
}
```

Call from:
- `set_pref_f` / `set_pref_b` / `adjust_pref` (after prefs mutate)
- `set_prefs_json` success path
- `from_ir` end (defaults)
- after `load` if auto/prefs unchanged (prefs are not in save — still sync current)

- [x] **Step 4: Tests PASS**

```bash
export CC=gcc && moon test -p runtime
```

- [x] **Step 5: Commit**

```bash
git add runtime/engine.mbt runtime/engine_test.mbt
git commit -m "feat(runtime): sync prefs volumes into global mixer"
```

---

## Task 3: BacklogStore + record complete lines

**Files:**
- Create: `runtime/backlog.mbt`
- Create: `runtime/backlog_test.mbt` (or section in engine_test)
- Modify: `runtime/engine.mbt`
- Modify: `runtime/moon.pkg` only if files need listing (same package — usually auto)

- [x] **Step 1: Failing unit tests for store**

```mbt
///|
test "backlog ring drops oldest at capacity" {
  let b = BacklogStore::new(capacity=3)
  b.push(speaker=Some("a"), text="1")
  b.push(speaker=None, text="2")
  b.push(speaker=Some("c"), text="3")
  b.push(speaker=None, text="4")
  assert_eq(b.len(), 3)
  assert_eq(b.get(0).text, "2")
  assert_eq(b.get(2).text, "4")
}

///|
test "backlog clear empties" {
  let b = BacklogStore::new(capacity=10)
  b.push(speaker=None, text="x")
  b.clear()
  assert_eq(b.len(), 0)
}
```

- [x] **Step 2: Implement `BacklogStore`**

```mbt
pub(all) struct BacklogEntry {
  speaker : String?
  text : String
} derive(Debug, Eq)

pub(all) struct BacklogStore {
  mut entries : Array[BacklogEntry]
  capacity : Int
}

pub fn BacklogStore::new(capacity~ : Int = 100) -> BacklogStore { ... }
pub fn BacklogStore::push(self, speaker~ : String?, text~ : String) -> Unit
pub fn BacklogStore::clear(self) -> Unit
pub fn BacklogStore::len(self) -> Int
pub fn BacklogStore::get(self, i : Int) -> BacklogEntry  // 0 = oldest
```

- [x] **Step 3: Engine field + record + clear**

```mbt
// Engine:
mut backlog : BacklogStore
mut backlog_fingerprinted : String  // last recorded full_text+speaker key to dedupe
```

On typewriter complete edge and `complete_text` path inside `apply_intent` / `tick_typewriter`:

```mbt
fn Engine::maybe_record_backlog(self : Engine) -> Unit {
  match self.stage.text {
    Some({ complete: true, full_text~, speaker~, .. }) => {
      if full_text.length() == 0 { return }
      let key = "\{speaker}-\{full_text}" // speaker None → use "-"
      if key == self.backlog_last_key { return }
      self.backlog_last_key = key
      self.backlog.push(speaker~, text=full_text)
    }
    _ => ()
  }
}
```

Call at end of `tick_typewriter` and after `complete_text` in `apply_intent`.

Clear backlog + last key in: `start_game`, `quit_to_title`, successful `load_slot` / `load`.

- [x] **Step 4: Integration test**

Play one dialogue line to complete via Advance; assert `eng.backlog.len() >= 1`.

- [x] **Step 5: Commit**

```bash
git add runtime/backlog.mbt runtime/backlog_test.mbt runtime/engine.mbt runtime/engine_test.mbt
git commit -m "feat(runtime): session backlog ring for completed dialogue"
```

---

## Task 4: skip_held burst semantics

**Files:**
- Modify: `runtime/engine.mbt`
- Modify: `runtime/engine_test.mbt`
- Modify: `host_web/main.mbt` (signature later can wait Task 9; tests call MoonBit API directly)

- [x] **Step 1: Failing tests**

```mbt
///|
test "skip_held completes typewriter then advances yield" {
  // Engine with one line Yield dialogue (existing fixture style)
  eng.tick(Intent::None_, skip_held=true)
  // text complete
  eng.tick(Intent::None_, skip_held=true)
  // advanced past yield
  assert_true(/* vm progressed or text cleared / next state */)
}

///|
test "skip_held does not skip timed wait" {
  eng.stage.wait_remaining = 1.0
  eng.vm.wait = Yield
  let ip0 = eng.vm.ip
  eng.tick(Intent::None_, skip_held=true, dt=0.0)
  assert_eq(eng.vm.ip, ip0)
  assert_true(eng.stage.wait_remaining > 0.0)
}

///|
test "skip_held does not auto-select choices" {
  // set Choose wait with 2 options
  eng.tick(Intent::None_, skip_held=true)
  assert_true(eng.vm.wait is Choose)
  assert_true(eng.stage.choices is Some(_))
}
```

- [x] **Step 2: Change `Engine::tick` signature**

```mbt
pub fn Engine::tick(
  self : Engine,
  intent : Intent,
  dt? : Double = 1.0 / 60.0,
  skip_held~ : Bool = false,
) -> Unit
```

All existing call sites keep default `skip_held=false`.

- [x] **Step 3: Implement skip path (Playing only)**

After gated intent application, if `skip_held` and playing and `wait_remaining <= 0`:

```mbt
let mut bursts = 0
while skip_held && bursts < 8 {
  // if typewriter incomplete → complete_text; maybe_record; break or continue
  // if Yield and complete → wait=Running; run_until_wait; bursts += 1
  // if Choose / Halted → break
  // if wait_remaining > 0 → break
}
```

Reuse `apply_intent(SkipTyping)` for one complete/advance step inside the loop to avoid divergence.

Constant: `let skip_burst_max : Int = 8`.

- [x] **Step 4: Tests PASS + full runtime package**

```bash
export CC=gcc && moon test -p runtime
```

- [x] **Step 5: Commit**

```bash
git add runtime/engine.mbt runtime/engine_test.mbt
git commit -m "feat(runtime): skip_held burst advance with wait gate"
```

---

## Task 5: Confirm dialogs (save overwrite + quit title)

**Files:**
- Modify: `runtime/ui_caps.mbt`
- Modify: `runtime/engine.mbt`
- Modify: `runtime/engine_test.mbt`
- Modify: `runtime/ui_types.mbt` (optional ConfirmMessage)
- Modify: `std_ui/modals.mbt`
- Modify: `std_ui/lib.mbt`

- [x] **Step 1: Types + failing tests**

```mbt
pub(all) enum ConfirmKind {
  OverwriteSave(Int)
  QuitToTitle
} derive(Debug, Eq)

// Engine:
mut pending_confirm : ConfirmKind?
```

Tests:

```mbt
test "save_slot occupied opens confirm without overwriting" {
  // save slot 0 once, mutate stage, save_slot(0) again
  // assert pending_confirm is Some(OverwriteSave(0))
  // assert slot blob still first save (parse scene or marker var)
}

test "confirm_yes overwrites save" { ... }

test "confirm_no cancels" { ... }

test "request_quit_to_title requires confirm_yes" { ... }
```

- [x] **Step 2: Capabilities**

```mbt
fn confirm_yes(Self) -> Unit
fn confirm_no(Self) -> Unit
fn request_quit_to_title(Self) -> Unit
```

Implement on Engine:
- `save_slot`: if occupied → `pending_confirm = OverwriteSave(i)`; `show_modal("confirm")`; return. Else write immediately.
- `confirm_yes`: match pending → perform; clear; `return_modal` if top is confirm.
- `confirm_no`: clear pending; return_modal.
- `request_quit_to_title`: set QuitToTitle pending + show confirm.
- Keep `quit_to_title` as the actual teardown (called from confirm_yes only for that kind).

- [x] **Step 3: std_ui confirm modal + game_menu**

`build_confirm`:

```mbt
VBox(
  children=[
    Text(Literal("Confirm")),
    Text(Literal("Are you sure?")), // or bind ConfirmMessage later
    button("No", confirm_no),   // register first so focus 0 = No
    button("Yes", confirm_yes),
  ],
)
```

`register(app)` → `register_modal("confirm", ...)`.

`build_game_menu`: Title button → `request_quit_to_title` instead of `quit_to_title`.

Save buttons can keep `save_slot` (engine gates).

- [x] **Step 4: Tests PASS**

```bash
export CC=gcc && moon test -p runtime -p std_ui
```

- [x] **Step 5: Commit**

```bash
git add runtime/ std_ui/
git commit -m "feat(runtime,std_ui): confirm overwrite save and quit to title"
```

---

## Task 6: Backlog modal UI + OpenBacklog

**Files:**
- Modify: `runtime/intent.mbt`
- Modify: `runtime/ui_types.mbt` / `ui_runtime.mbt` / bind for backlog lines
- Modify: `runtime/engine.mbt` (`tick_ui` / Playing OpenBacklog)
- Modify: `std_ui/modals.mbt`
- Modify: `render/gpu.mbt` intent codes

**Approach for listing entries without ScrollView:**  
Expose up to 12 most recent lines as `Text` nodes rebuilt each paint **or** bind via new `TextBindSrc::BacklogLine(Int)` reading from Engine through bind ctx:

```mbt
// UiBindCtx:
backlog_lines : Array[String]  // preformatted "Name: text" newest last
```

`sync_ui_bind` fills from `self.backlog` (last 12).

- [x] **Step 1: Intent + code**

```mbt
// intent.mbt
MenuLeft
MenuRight
OpenBacklog
```

Codes (freeze in docs):
- 7 MenuLeft
- 8 MenuRight  
- 9 OpenBacklog  
- 10+n Select (unchanged)

Update `intent_from_code` / `intent_to_code` + pack_test.

- [x] **Step 2: Playing path**

```mbt
if effective is OpenBacklog {
  self.ui.show_modal("backlog")
  ...
  return
}
```

Esc still pops (return_modal) including backlog.

- [x] **Step 3: std_ui `build_backlog`**

Title + up to 12 `Text` with `BacklogLine(i)` or Literals updated only via bind resolve.

Close button → `return_modal`.

game_menu: **History** → `show_modal("backlog")`.

- [x] **Step 4: Tests**

- OpenBacklog pushes modal name backlog  
- After dialogue, bind lines non-empty when painted/synced  

- [x] **Step 5: Commit**

```bash
git commit -m "feat: backlog modal and OpenBacklog intent"
```

---

## Task 7: UiNode::Slider + settings

**Files:**
- Modify: `runtime/ui_types.mbt`
- Modify: `runtime/ui_runtime.mbt`
- Modify: `runtime/ui_test.mbt`
- Modify: `std_ui/modals.mbt` (`build_settings`)

- [x] **Step 1: Failing test**

```mbt
test "slider is focusable and MenuRight adjusts pref" {
  let app = UiApp::new()
  // tree with one Slider key=master_volume
  let ui = UiRuntime::from_app(app, save_slots=6)
  ui.prefs = Prefs::default()
  ui.show_modal("settings") // or push custom
  // focus slider, apply MenuRight via ui path with FakeCaps/Engine
  assert_true(ui.prefs.master_volume > 1.0 - 1e-6 || adjusted)
}
```

More concrete: unit-test layout collects `UiFocusTarget::Slider(key)` and a function `apply_slider_delta(caps, key, +0.1)`.

- [x] **Step 2: Types**

```mbt
// UiNode
Slider(
  key~ : String,
  x~ : Double,
  y~ : Double,
  w~ : Double,
  h~ : Double,
  visible~ : VisiblePred,
)

// UiFocusTarget
Slider(String)  // prefs key
```

- [x] **Step 3: Layout/paint**

- Track rect + fill width = `w * pref_normalized`  
  - volume keys: value is already 0..1  
  - text_speed: `(v - 0.25) / (3.0 - 0.25)`  
- Focus: use button_focus resource or brighter fill  
- z same as widgets  

- [x] **Step 4: Input**

In `tick_ui` / `UiRuntime` when focus is Slider:
- `MenuLeft` → `adjust_pref(key, -step)`
- `MenuRight` → `adjust_pref(key, +step)`
- steps: volume 0.1, text_speed 0.25

When Playing narrative, MenuLeft/Right no-op (or ignore).

- [x] **Step 5: rebuild settings modal** with Sliders for master/bgm/se/text_speed; keep auto on/off buttons.

- [x] **Step 6: Commit**

```bash
git commit -m "feat(ui): Slider widget and settings volume sliders"
```

---

## Task 8: Slot labels via bind

**Files:**
- Modify: `runtime/ui_types.mbt` (`UiBindCtx.slot_labels`)
- Modify: `runtime/engine.mbt` (`sync_ui_bind`)
- Modify: `runtime/ui_types.mbt` `TextBindSrc::resolve` for SlotLabel
- Modify: `std_ui/modals.mbt` if button labels should show SlotLabel text
- Modify: tests for `slot_label` format

- [x] **Step 1: Improve `Engine` slot_label formatting** (already exists — enhance):

```mbt
// empty: "Slot {i} (empty)"
// occupied with saved_at: "Slot {i} · {saved_at}"
// occupied without: "Slot {i} · saved"
```

- [x] **Step 2: `UiBindCtx.slot_labels : Array[String]`** filled in `sync_ui_bind` length = save_slots.

- [x] **Step 3: `TextBindSrc::SlotLabel(i)`** resolves `bind.slot_labels[i]` if in range.

- [x] **Step 4: save_load modal** — use Text SlotLabel under each button or set button label via rebuild (simplest: Text nodes with SlotLabel for each slot).

- [x] **Step 5: Commit**

```bash
git commit -m "feat(runtime,std_ui): show save slot timestamps in labels"
```

---

## Task 9: Host wiring (skip hold, H, arrows, no double volume)

**Files:**
- Modify: `host_web/main.mbt`
- Modify: `host_web/js_glue/boot.js`
- Modify: `docs/draw-list-pack.md` intent table
- Copy glue to dist is build-time

- [x] **Step 1: export_frame**

```mbt
pub fn export_frame(intent_code : Int, dt_ms : Float, skip_held~ : Int = 0) -> Int {
  ...
  eng.tick(intent, dt~, skip_held=skip_held != 0)
}
```

MoonBit export: if default args not exportable, use third `Int` parameter required from JS:

```mbt
pub fn export_frame(intent_code : Int, dt_ms : Float, skip_held : Int) -> Int
```

- [x] **Step 2: boot.js**

```js
let ctrlHeld = false;
window.addEventListener("keydown", (ev) => {
  if (ev.key === "Control") { ctrlHeld = true; ev.preventDefault(); return; }
  if (ev.key === "h" || ev.key === "H") {
    if (!ev.ctrlKey) { pendingIntent = INTENT_OPEN_BACKLOG; /* 9 */ }
  }
  if (ev.key === "ArrowLeft") pendingIntent = INTENT_MENU_LEFT; // 7
  if (ev.key === "ArrowRight") pendingIntent = INTENT_MENU_RIGHT; // 8
  // remove one-shot INTENT_SKIP on Control keydown as sole skip path
});
window.addEventListener("keyup", (ev) => {
  if (ev.key === "Control") ctrlHeld = false;
});

// frame():
exports_.export_frame(intent, dt, ctrlHeld ? 1 : 0);
```

- [x] **Step 3: Volume double-multiply fix**

`effectiveBgmVolume` / `effectiveSeVolume`: return `clampVolume(logical)` only (mixer already applied prefs).  
Keep JS `prefs` object for UI display sync from `prefs_json()`.

When prefs change in-engine, mixer emits SetBgmVolume — flushAudio already handles.

- [x] **Step 4: Manual smoke** (document in task report)

```bash
export CC=gcc
moon build --target wasm-gc --release host_web
# moonsightc build demo → serve dist/demo
# Ctrl hold skip; H backlog; overwrite save confirm; volume slider
```

- [x] **Step 5: Commit**

```bash
git commit -m "feat(host): skip hold, backlog key, slider arrows; fix volume prefs path"
```

---

## Task 10: Docs + demo tip + gate verification

**Files:**
- Create: `docs/play-input.md`
- Modify: `docs/host-commands.md`, `docs/ui-moonbit.md`, `docs/draw-list-pack.md`, `README.md`, `README.mbt.md`
- Optional: `demo/game/main.yuki` tip line
- Optional: improve 1–2 compiler diagnostics

- [x] **Step 1: Write `docs/play-input.md`**

Contents:
- Intent table + codes
- skip_held vs SkipTyping
- wait_remaining gate
- Default keys
- Confirm / backlog behavior summary

- [x] **Step 2: README Scope**

Add Q1 / 0.5 bullets; move backlog/confirm/skip off "out of scope through Phase 4" list appropriately.

- [x] **Step 3: Full verify**

```bash
export CC=gcc
moon check
moon test
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Expected: all green; dist has no regressions.

- [x] **Step 4: Commit**

```bash
git commit -m "docs: Q1 play-input semantics and 0.5 scope"
```

- [x] **Step 5: Final gate checklist**

- [x] Backlog records completed lines; H / History opens; Esc closes  
- [x] Ctrl hold skips yields; timed wait blocked  
- [x] Overwrite save + quit title confirm (default No)  
- [x] Volume prefs audible / event volume changes  
- [x] Settings sliders keyboard adjustable  
- [x] Slot labels show saved_at when present  
- [x] `moon test` full green  

---

## Spec coverage (self-check)

| Spec requirement | Task |
|------------------|------|
| Backlog ring 100, session clear | 3, 6 |
| Skip hold, wait gate, no auto-choice, burst 8 | 4, 9 |
| Confirm overwrite + quit title | 5 |
| Prefs → mixer | 1, 2, 9 (JS) |
| Slider settings | 7 |
| Slot metadata labels | 8 |
| Docs / diagnostics | 10 |
| Non-goals (scroll, dissolve, save backlog) | not scheduled |

## Placeholder scan

No TBD steps; host export third arg is explicit; intent codes 7–9 frozen here and in Task 6.

## Type / API consistency

- `Engine::tick(..., skip_held~: Bool = false)`
- `ConfirmKind::{OverwriteSave(Int), QuitToTitle}`
- Intent: `MenuLeft` `MenuRight` `OpenBacklog`
- Codes: 7 / 8 / 9
- Modal names: `"backlog"`, `"confirm"`
- `Mixer::set_pref_gains(master~, bgm~, se~)`
