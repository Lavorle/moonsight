# MoonSight Phase 3 — Screen Language & System UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a minimal Screen DSL + runtime that powers title / game menu / multi-slot save-load / settings (full WebGPU), plus D+B foundations (named negatives, audio hard-fail, BGM volume/fade).

**Architecture:** Keep the theater model. `- screen` declarations compile to `ScreenDef` trees (not narrative scenes). Engine holds `UiMode` + a modal screen stack with focus; menu open pauses narrative VM ticks. Actions are a closed enum. Prefs live outside save slots; slots remain JSON save v3 with slot headers. Renderer draws active screens above frozen stage layers.

**Tech Stack:** MoonBit (`moon test` / `moon check`), existing `script` → IR → `runtime` → `render` → `host_web` pipeline, JSON saves/prefs in `localStorage`, `moonsightc` native CLI.

**Spec:** `docs/superpowers/specs/2026-07-10-moonsight-phase3-screen-ui-design.md`

**Pinned defaults (from spec):**

| Item | Choice |
|------|--------|
| Screen carrier | `- screen` in `*.yuki` |
| Indent | 2 spaces |
| Controls | `vbox` / `hbox` / `fixed` / `text` / `button` |
| Actions | closed enum only |
| Save slots | default 6; `moonsight.json` `save_slots` clamp 1..20 |
| Esc | OpenMenu → show `game_menu`; Esc again → `return` one layer |
| Playing save | any Playing may save (game snapshot, not UI) |
| Project vs std screens | project same name **overrides** std |
| Dialogue UI | still hardcoded `UiLayout` (not screen-ized) |

---

## File map

| Path | Role |
|------|------|
| `script/lexer.mbt` | Named negative numbers after `=` |
| `script/lexer_test.mbt` | `x=-200` token tests |
| `script/ast.mbt` | `ScreenDecl`, `ScreenNode` AST |
| `script/parser.mbt` | Parse `- screen` + indented body |
| `script/parser_test.mbt` | Screen parse tests |
| `script/screen_ir.mbt` | **Create:** `ScreenDef` / `ScreenNode` / `ScreenAction` IR |
| `script/screen_lower.mbt` | **Create:** AST → Screen IR |
| `script/screen_lower_test.mbt` | **Create:** lower tests |
| `script/compile.mbt` | Return screens alongside `IrModule` |
| `script/resolve.mbt` | `ui.show` / `ui.hide` in `builtin_externs` |
| `runtime/screen.mbt` | **Create:** stack, focus, action exec helpers |
| `runtime/screen_test.mbt` | **Create:** stack/focus/action tests |
| `runtime/prefs.mbt` | **Create:** prefs struct + clamp + JSON |
| `runtime/prefs_test.mbt` | **Create:** prefs tests |
| `runtime/intent.mbt` | Optional `MenuUp` / `MenuDown` (or document host synthesis) |
| `runtime/engine.mbt` | UiMode, gate narrative, OpenMenu, tick screens/audio fade |
| `runtime/engine_test.mbt` | Menu gating + cold start |
| `runtime/save.mbt` | Slot header fields; optional bgm volume on audio state |
| `runtime/save_test.mbt` | Header round-trip |
| `runtime/stage.mbt` | bgm_volume / fade fields if not only on mixer |
| `audio/mixer.mbt` | BGM fade remaining, set_volume tick |
| `audio/mixer_test.mbt` | fade tests |
| `audio/backend.mbt` | Optional `SetBgmVolume` event |
| `std_commands/audio_cmd.mbt` | volume/fade named args |
| `std_commands/ui_cmd.mbt` | **Create:** `ui.show` / `ui.hide` |
| `std_commands/registry.mbt` | Register ui + audio |
| `std_commands/registry_test.mbt` | Registry alignment |
| `render/types.mbt` | Screen layout constants if needed |
| `render/snapshot.mbt` | Draw active screen widgets |
| `render/snapshot_test.mbt` | Button/text geometry assertions |
| `cmd/moonsightc/config.mbt` | `save_slots` field |
| `cmd/moonsightc/build.mbt` | Merge std screens; fail cleanup; wire screens into dist |
| `cmd/moonsightc/assets_check.mbt` | Clearer audio-vs-image messages if needed |
| `std_screens/*.yuki` | **Create:** title, game_menu, save_load, settings |
| `host_web/main.mbt` | Export prefs/slot helpers if needed; engine boot Title |
| `host_web/js_glue/boot.js` | Esc/arrows; prefs/slots; audio hard-fail; volume apply |
| `demo/game/*.yuki` | Cold-start compatible; optional override screen |
| `docs/*` | host-commands, subset, project-layout, screen-language, README |

---

### Task 1: Lexer — named negative numbers

**Files:**
- Modify: `script/lexer.mbt` (`LineScanner::scan_value`)
- Modify: `script/lexer_test.mbt`

**Context:** After `=`, `scan_value` only accepts digit-leading numbers, so `x=-200` emits `Minus` then junk or errors. Spec requires named negatives for layer and screen coords.

- [ ] **Step 1: Write the failing test**

Add to `script/lexer_test.mbt`:

```mbt
///|
test "lexer named negative int and float" {
  let toks = @script.lex_line(#|@layer.set "y" x=-200 y=-1.5 duration=0.5, file="t.yuki", line_no=1)
  // Expect Ident/At path + named values as IntLit(-200), FloatLit(-1.5)
  var saw_neg_int = false
  var saw_neg_float = false
  for t in toks {
    match t.kind {
      IntLit(n) => if n == -200 { saw_neg_int = true }
      FloatLit(f) => if f == -1.5 { saw_neg_float = true }
      _ => ()
    }
  }
  assert_true(saw_neg_int)
  assert_true(saw_neg_float)
}
```

(Adjust `lex_line` name to the package’s actual public lexer entry used by existing tests.)

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /mnt/nvme1n1p2/moonsight && moon test -p script -v 2>&1 | tail -40
```

Expected: FAIL — negative named values not tokenized as number lits.

- [ ] **Step 3: Implement minimal fix**

In `LineScanner::scan_value`, when peek is `-` and next is a digit, scan a signed number (reuse `scan_number` after consuming `-`, then negate; or extend `scan_number` to accept leading `-`).

Do **not** change bare unary minus elsewhere if tests break; only value-after-`=` path is required.

- [ ] **Step 4: Run tests**

```bash
moon test -p script
```

Expected: PASS including new test.

- [ ] **Step 5: Commit**

```bash
git add script/lexer.mbt script/lexer_test.mbt
git commit -m "fix(script): lex named negative numbers after '='"
```

---

### Task 2: Audio hard-fail at runtime (+ build message polish)

**Files:**
- Modify: `host_web/js_glue/boot.js` (BGM/SE load paths)
- Modify: `cmd/moonsightc/assets_check.mbt` (optional clearer errors)
- Test: manual notes + any existing missing_resource fixture remains green

**Context:** Textures already hard-fail in `applyManifest`. Audio still `console.warn` and continues. Build already fails if literal id missing from both maps — keep that; improve message to say image vs audio when possible.

- [ ] **Step 1: Document expected runtime behavior in a short comment test path**

In `boot.js`, locate `playBgm` / `playSe` (or equivalent) that warn on missing URL.

- [ ] **Step 2: Implement hard-fail**

When logical audio id has no resolvable URL or `HTMLAudioElement` errors on required load:

1. Call the same error surface as texture hard-fail (DOM message / throw that stops boot loop).
2. Log `audio load failed: {id}`.
3. Do **not** pretend playback succeeded.

For play-time missing id after successful boot (dynamic): surface error and stop advancing if that matches texture policy; minimum is visible error + no silent success.

- [ ] **Step 3: Optional build polish**

If `validate_literal_resources` only says `missing resource`, split:

```
error: missing audio `bgm_soft` referenced by script
error: missing image `bg_room` referenced by script
```

Use host op name from collection path (`audio.*` vs `layer.*`).

- [ ] **Step 4: Smoke**

```bash
export CC=gcc
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
# confirm build still ok
```

- [ ] **Step 5: Commit**

```bash
git add host_web/js_glue/boot.js cmd/moonsightc/assets_check.mbt
git commit -m "fix(host): hard-fail missing audio loads like textures"
```

---

### Task 3: BGM volume and fade

**Files:**
- Modify: `audio/mixer.mbt`, `audio/mixer_test.mbt`, `audio/backend.mbt` (if new events)
- Modify: `std_commands/audio_cmd.mbt`, `std_commands/registry_test.mbt`
- Modify: `runtime/stage.mbt` / `runtime/save.mbt` for `bgm_volume` (+ fade fields)
- Modify: `runtime/engine.mbt` to tick BGM fade
- Modify: `host_web/js_glue/boot.js` to apply volume each event / frame

**Semantics (spec §4.3):**

- `@audio.bgm "id" volume=0.8 fade=1.0`
- Output volume = logical × prefs.master × prefs.bgm (prefs may land Task 7; until then multiply by 1.0)
- `fade` linear over wall-clock seconds; fire-and-forget
- stop: empty/`None_` with optional `fade=`

- [ ] **Step 1: Failing mixer test**

```mbt
///|
test "bgm fade approaches target volume" {
  let q = @audio.QueueBackend::new()
  let m = @audio.Mixer::with_backend(q)
  m.play_bgm("a", volume=0.0)
  m.fade_bgm_to(1.0, 1.0) // or start_fade API chosen in impl
  m.tick(0.5)
  // volume mid ~0.5
  assert_true(m.bgm_volume > 0.4 && m.bgm_volume < 0.6)
  m.tick(0.5)
  assert_true(m.bgm_volume >= 0.99)
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
moon test -p audio
```

- [ ] **Step 3: Implement mixer fade state**

Suggested fields on `Mixer`:

```mbt
mut bgm_fade_to : Double?
mut bgm_fade_remaining : Double
```

`tick(dt)` advances linear. Emit `PlayBgm` or a new `SetBgmVolume(volume)` event so JS can update without restarting track. Prefer **SetBgmVolume** for mid-fade to avoid restart.

- [ ] **Step 4: Wire `cmd_audio_bgm`**

Parse positional resource + named `volume` / `fade` via same `#:name` split helper used by layers (`@runtime.split_host_args` or local copy).

- [ ] **Step 5: Engine ticks mixer**

In `Engine::tick`, after layer tweens (or with transitions): `@audio.global_mixer().tick(dt)` if global; or engine-owned mixer — **match existing architecture** (`global_mixer` today).

- [ ] **Step 6: Save**

Extend `AudioLogicState` with `bgm_volume : Double` and optional fade fields; load restores mixer.

- [ ] **Step 7: Tests green + commit**

```bash
moon test -p audio -p std_commands -p runtime
git add audio std_commands runtime host_web/js_glue/boot.js
git commit -m "feat(audio): BGM volume and linear fade"
```

---

### Task 4: Build failure must not leave a bad dist

**Files:**
- Modify: `cmd/moonsightc/build.mbt`

**Context:** Spec §4.6 — failed build must not leave partial playable `out_dir`.

- [ ] **Step 1: Identify write order**

Today: create out_dir, copy assets, write msb/manifest, etc. On `validate_literal_resources` failure, out_dir may already exist partial.

- [ ] **Step 2: Implement staging**

Pattern:

1. Build into `out_dir + ".tmp-moonsight-build"` (or sibling).
2. On full success, replace `out_dir` (rm + rename) or rename into place.
3. On failure, delete staging; leave previous `out_dir` intact if any.

- [ ] **Step 3: Manual check**

```bash
# force fail with missing asset project if fixture exists
moon run cmd/moonsightc --target native -- build script/testdata/missing_resource -o /tmp/ms-fail-out || true
# /tmp/ms-fail-out should not contain a bootable half tree
```

- [ ] **Step 4: Commit**

```bash
git add cmd/moonsightc/build.mbt
git commit -m "fix(moonsightc): stage dist so failed builds leave no partial out_dir"
```

---

### Task 5: Parse `- screen` into AST

**Files:**
- Modify: `script/ast.mbt` — add screen types to `ScriptUnit`
- Modify: `script/parser.mbt` — top decl `screen`
- Modify: `script/parser_test.mbt`

**AST (pinned):**

```mbt
pub(all) struct ScriptUnit {
  file : String
  externs : Array[ExternDecl]
  macros : Array[MacroDecl]
  scenes : Array[SceneDecl]
  screens : Array[ScreenDecl]
}

pub(all) struct ScreenDecl {
  name : String
  root_children : Array[ScreenNode]
  span : SourceSpan
}

pub(all) enum ScreenNode {
  VBox(x~ : Double?, y~ : Double?, children~ : Array[ScreenNode], span~ : SourceSpan)
  HBox(x~ : Double?, y~ : Double?, children~ : Array[ScreenNode], span~ : SourceSpan)
  Fixed(x~ : Double, y~ : Double, w~ : Double?, h~ : Double?, children~ : Array[ScreenNode], span~ : SourceSpan)
  Text(src~ : ScreenTextSrc, span~ : SourceSpan)
  Button(label~ : String, action~ : ScreenActionAst, span~ : SourceSpan)
}

pub(all) enum ScreenTextSrc {
  Literal(String)
  SlotLabel(Int)
  Pref(String)
}

// Action AST can be a structured enum or raw string+args; lower validates.
pub(all) enum ScreenActionAst {
  Return
  StartGame
  QuitToTitle
  ShowScreen(name~ : String, mode~ : String?) // mode: "save" | "load" | None
  HideScreen(name~ : String?)
  SaveSlot(Int)
  LoadSlot(Int)
  SetPref(key~ : String, value~ : Expr)
  AdjustPref(key~ : String, delta~ : Double)
  Noop
}
```

**Parse rules:**

- `- screen "name"` then body lines until next top-level `-` decl or EOF.
- Body is **indent-based** (2 spaces per level). Lines that look like:

```text
  vbox x=760 y=360:
    text "MoonSight"
    button "Start" action=start_game
```

Implementation options (pick one, document in code comment):

1. **Line classifier:** measure leading spaces; parse widget keyword + args; `:` opens child block until indent ≤ parent.
2. Reuse token lines but track indent from raw source lines.

Prefer scanning **raw source lines** for screen bodies if token stream loses indent (current lexer may strip leading spaces). If so, add `parse_screen_body(lines, start_idx)`.

- [ ] **Step 1: Failing parser test**

```mbt
///|
test "parse minimal title screen" {
  let src =
    #|- screen "title"
    #|  vbox:
    #|    text "MoonSight"
    #|    button "Start" action=start_game
    #|
  let unit = @script.parse_source(src, file="t.yuki")
  assert_eq(unit.screens.length(), 1)
  assert_eq(unit.screens[0].name, "title")
  // assert root has vbox with 2 children
}
```

- [ ] **Step 2: Run — FAIL**

```bash
moon test -p script
```

- [ ] **Step 3: Implement parse**

- Extend `parse_top_decl` for `Ident("screen")`.
- Existing scene-only unit construction must include `screens: []`.
- Macro expand / resolve: **pass screens through unchanged** (update `expand_macros` / `resolve_unit` struct copies).

- [ ] **Step 4: Tests PASS + commit**

```bash
moon test -p script
git add script/ast.mbt script/parser.mbt script/parser_test.mbt script/macro.mbt script/resolve.mbt
git commit -m "feat(script): parse - screen declarations into AST"
```

---

### Task 6: Screen IR + lower + compile surface

**Files:**
- Create: `script/screen_ir.mbt`, `script/screen_lower.mbt`, `script/screen_lower_test.mbt`
- Modify: `script/moon.pkg` (list new files if required by layout)
- Modify: `script/compile.mbt` — expose screens from pipeline
- Modify: `script/ir.mbt` or new — `CompileBundle { ir, screens }`

**Screen IR (runtime-facing, no spans required):**

```mbt
pub(all) struct ScreenDef {
  name : String
  root : SNode
}

pub(all) enum SNode {
  VBox(x~ : Double?, y~ : Double?, children~ : Array[SNode])
  HBox(x~ : Double?, y~ : Double?, children~ : Array[SNode])
  Fixed(x~ : Double, y~ : Double, w~ : Double?, h~ : Double?, children~ : Array[SNode])
  Text(ScreenText)
  Button(label~ : String, action~ : ScreenAction)
}

pub(all) enum ScreenText {
  Literal(String)
  SlotLabel(Int)
  Pref(String)
}

pub(all) enum ScreenAction {
  Return
  StartGame
  QuitToTitle
  ShowScreen(name~ : String, mode~ : String?)
  HideScreen(name~ : String?)
  SaveSlot(Int)
  LoadSlot(Int)
  SetPrefF(key~ : String, value~ : Double)
  SetPrefB(key~ : String, value~ : Bool)
  AdjustPref(key~ : String, delta~ : Double)
  Noop
}
```

- [ ] **Step 1: Lower test**

```mbt
///|
test "lower screen actions" {
  let src =
    #|- screen "title"
    #|  vbox:
    #|    button "Start" action=start_game
    #|    button "Load" action=show_screen("save_load", mode=load)
    #|
  let screens = @script.compile_screens(src, file="t.yuki")
  assert_eq(screens.length(), 1)
  // walk tree: StartGame + ShowScreen("save_load", Some("load"))
}
```

- [ ] **Step 2: Implement lower** — reject unknown action names with `CompileError` / resolve error.

- [ ] **Step 3: `compile_to_ir` still works for scene-only files** — screens default empty.

- [ ] **Step 4: Commit**

```bash
git add script/
git commit -m "feat(script): lower screen AST to ScreenDef IR"
```

---

### Task 7: Prefs + multi-slot save headers

**Files:**
- Create: `runtime/prefs.mbt`, `runtime/prefs_test.mbt`
- Modify: `runtime/save.mbt`, `runtime/save_test.mbt`
- Modify: `runtime/moon.pkg` if needed

**Prefs:**

```mbt
pub(all) struct Prefs {
  text_speed : Double    // default 1.0, clamp 0.25..3.0
  auto_mode : Bool       // default false
  master_volume : Double // 0..1
  bgm_volume : Double
  se_volume : Double
}

pub fn Prefs::default() -> Prefs
pub fn Prefs::clamp(self : Prefs) -> Prefs
pub fn Prefs::to_json_string(self : Prefs) -> String
pub fn Prefs::from_json_string(s : String) -> Prefs! // missing fields → defaults
pub fn Prefs::adjust(self : Prefs, key : String, delta : Double) -> Prefs
pub fn Prefs::set(self : Prefs, key : String, value : Value) -> Prefs
```

**Save header:** Add to `SaveGame` (still format_version 3 — additive fields loaders must tolerate):

```mbt
// optional fields with defaults for old blobs
saved_at : String  // ISO or empty
// scene already present
```

Host stores:

- `moonsight/save/{slot}` → full save JSON  
- `moonsight/prefs` → prefs JSON  
- Slot empty = missing key  

Also provide pure helpers:

```mbt
pub fn slot_label(saved : SaveGame?) -> String  // "Empty" or "\{scene} · \{saved_at}"
```

- [ ] **Step 1: Prefs tests** (defaults, clamp, adjust, round-trip JSON)

- [ ] **Step 2: Save header round-trip test**

- [ ] **Step 3: Implement**

- [ ] **Step 4: Commit**

```bash
git add runtime/prefs.mbt runtime/prefs_test.mbt runtime/save.mbt runtime/save_test.mbt
git commit -m "feat(runtime): prefs store and save slot headers"
```

---

### Task 8: Screen runtime — stack, focus, actions

**Files:**
- Create: `runtime/screen.mbt`, `runtime/screen_test.mbt`
- Modify: `runtime/engine.mbt` (wire later in Task 9 if cleaner split)

**Types:**

```mbt
pub(all) enum UiMode {
  Title
  Playing
  Menu
}

pub(all) struct ScreenInstance {
  name : String
  mode : String?  // save/load for save_load screen
  focus : Int     // index into focusable buttons (flattened)
}

pub(all) struct ScreenState {
  mut mode : UiMode
  mut stack : Array[ScreenInstance]
  defs : Map[String, @script.ScreenDef]
  mut prefs : Prefs
  save_slots : Int  // N
}
```

**API:**

```mbt
pub fn ScreenState::new(defs : Map[String, @script.ScreenDef], save_slots~ : Int = 6) -> ScreenState
pub fn ScreenState::show(self : ScreenState, name : String, mode? : String) -> Unit // push
pub fn ScreenState::return_(self : ScreenState) -> Unit // pop; if empty && was menu → Playing
pub fn ScreenState::activate(self : ScreenState, engine : Engine) -> Unit // run focused button action
pub fn ScreenState::focus_delta(self : ScreenState, delta : Int) -> Unit
pub fn ScreenState::focusables(self : ScreenState) -> Array[(String, ScreenAction)] // label+action, load-empty filtered
```

**Action execution** (needs engine callbacks — use a small trait or pass closures via `ScreenHost` struct):

```mbt
pub(open) trait ScreenHost {
  fn start_game(Self) -> Unit
  fn quit_to_title(Self) -> Unit
  fn save_slot(Self, Int) -> Unit
  fn load_slot(Self, Int) -> Unit
  fn slot_occupied(Self, Int) -> Bool
  fn apply_prefs(Self, Prefs) -> Unit
}
```

Implement trait on a test double first; Engine implements in Task 9.

- [ ] **Step 1: Unit tests** — push/pop, focus wrap, load empty not focusable, start_game called

- [ ] **Step 2: Implement**

- [ ] **Step 3: Commit**

```bash
git add runtime/screen.mbt runtime/screen_test.mbt
git commit -m "feat(runtime): screen stack, focus, and action dispatch"
```

---

### Task 9: Engine UiMode integration + `@ui.*` + Intent

**Files:**
- Modify: `runtime/engine.mbt`, `runtime/engine_test.mbt`, `runtime/intent.mbt`
- Create: `std_commands/ui_cmd.mbt`
- Modify: `std_commands/registry.mbt`, `script/resolve.mbt`, registry tests

**Engine changes:**

```mbt
pub(all) struct Engine {
  mut vm : Vm
  director : Director
  mut stage : Stage
  mut auto : Bool
  mut screens : ScreenState
  mut ir_entry : String  // for start_game
  // module/ir retained for restart
}
```

**Tick order (Phase 3):**

1. Map intent: if `screens.stack` non-empty OR `mode == Title`:
   - `OpenMenu` / Esc → `return_` one level (if stack non-empty); on Title ignore OpenMenu
   - `Advance` → `activate`
   - MenuUp/Down or Select → focus move
   - **Do not** run narrative VM / typewriter / wait skip rules for narrative
2. Else Playing:
   - `OpenMenu` → `show("game_menu")`, mode=Menu
   - existing Phase 2 tick path
3. Always: tick layer tweens only when Playing (or always freeze positions when Menu — **spec: freeze narrative**; still tick BGM fade)
4. When Menu: **do not** `run_until_wait`

**Cold start:** `Engine::from_ir` may start in `Title` with `show("title")` if def exists; host_web will call this. Provide:

```mbt
pub fn Engine::boot_title(self : Engine) -> Unit
pub fn Engine::start_game(self : Engine) -> Unit  // reset stage/vm to entry
pub fn Engine::quit_to_title(self : Engine) -> Unit
```

**Host commands:**

```mbt
// ui.show name [mode=save|load]
// ui.hide [name]
```

Register `ui.show`, `ui.hide` in `builtin_externs` + `standard_registry`.

- [ ] **Step 1: Engine test** — Playing + OpenMenu pauses VM IP; Advance activates Continue → resumes

- [ ] **Step 2: Implement**

- [ ] **Step 3: Intent** — either add `MenuUp`/`MenuDown` to `Intent` enum or document that host sends `Select(-1)`/`Select(-2)` — **prefer explicit:**

```mbt
pub(all) enum Intent {
  None_
  Advance
  Select(Int)
  SkipTyping
  OpenMenu
  ToggleAuto
  MenuUp
  MenuDown
}
```

- [ ] **Step 4: Commit**

```bash
git add runtime std_commands script/resolve.mbt script/resolve_test.mbt
git commit -m "feat(runtime): UiMode, OpenMenu gating, and ui host commands"
```

---

### Task 10: Render active screens

**Files:**
- Modify: `render/snapshot.mbt`, `render/types.mbt`, `render/snapshot_test.mbt`
- Modify: `runtime` StageView or pass `ScreenState` into `build_draw_list`

**Approach:**

Extend `build_draw_list` signature:

```mbt
pub fn build_draw_list(
  view : @runtime.StageView,
  layout : UiLayout,
  screens? : @runtime.ScreenState,
) -> DrawList
```

When `screens` has stack:

1. Draw layers from view as today  
2. Push semi-transparent full-screen quad (dim) if Menu  
3. Walk top screen def + instance focus: layout vbox/hbox/fixed; emit panel rects + glyphs for text/buttons  
4. Focused button: brighter bg or border (one clear visual)  
5. Skip dialogue box when `UiMode::Title` or stack non-empty  

Layout algorithm (minimal):

- Start cursor at (x,y) of root container (default y=200, x=center-ish 760)  
- Each button/text advances `y += line_height` (e.g. 64) in vbox  
- hbox advances x  

- [ ] **Step 1: Test** — StageView empty + screen with 2 buttons → draw list has ≥2 quads and glyphs

- [ ] **Step 2: Implement**

- [ ] **Step 3: Commit**

```bash
git add render/
git commit -m "feat(render): draw screen widgets and menu dim"
```

---

### Task 11: host_web + moonsightc wiring

**Files:**
- Modify: `host_web/main.mbt`, `host_web/js_glue/boot.js`
- Modify: `cmd/moonsightc/build.mbt`, `cmd/moonsightc/config.mbt`
- Create: `std_screens/title.yuki`, `game_menu.yuki`, `save_load.yuki`, `settings.yuki`

**std screens content** — implement exactly the four screens from the spec (buttons + actions). `save_load` can list 6 buttons `Slot 0` … with actions `save_slot(i)` / use `mode` from instance to pick save vs load at runtime (runtime maps button actions when mode is load to `load_slot`).

Simplest authoring approach for slots: generate focusables in runtime for `save_load` **or** write 6 buttons in DSL:

```text
- screen "save_load"
  vbox x=600 y=120:
    text "Save / Load"
    button "Slot 0" action=save_slot(0)
    ...
    button "Back" action=return
```

Runtime: if instance.mode is `load`, reinterpret `SaveSlot(i)` as `LoadSlot(i)` for activation (document this); empty slots skipped in focus list when mode=load.

**moonsightc:**

1. Read `save_slots` from config (default 6).  
2. Load `std_screens/*.yuki` from repo path relative to moonsightc (pin: `std_screens/` at module root).  
3. Merge screen defs: project overrides.  
4. Emit screens into dist — **options:** embed JSON `screens.json` next to `game.msb` for host load (YAGNI-friendly) **or** extend MSB. **Pinned for plan:** write `screens.json` (array of defs) via a simple JSON encoder for ScreenDef; host loads it at boot. Narrative stays `game.msb`.  
   - If JSON encoder for deep trees is painful in MoonBit, use a minimal custom text format — but prefer JSON.  

**boot.js:**

- Esc → OpenMenu intent  
- ArrowUp/Down → MenuUp/Down  
- Enter/Space/Z → Advance  
- Prefs load/save `moonsight/prefs`  
- Multi-slot already uses `saveSlot` variable — ensure UI can set slot index before save_json  
- Boot: if screens present, start Title not auto-run entry (call wasm `boot_title`)  
- Apply master×bgm×logical volume to Audio elements  

**host_web main.mbt:** export `boot_title`, `prefs_json`, `set_prefs_json`, ensure `export_frame` uses screen-aware draw list.

- [ ] **Step 1: Add std_screens files**

- [ ] **Step 2: build merges and writes screens.json**

- [ ] **Step 3: boot.js input + title boot**

- [ ] **Step 4: Manual**

```bash
export CC=gcc
moon build --target wasm-gc --release host_web
cp _build/wasm-gc/release/build/host_web/host_web.wasm host_web/js_glue/
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
# serve dist/demo — title → start → Esc menu
```

- [ ] **Step 5: Commit**

```bash
git add std_screens host_web cmd/moonsightc demo
git commit -m "feat: std screens, host menu input, and build merge"
```

---

### Task 12: Demo cold start + docs + full verification

**Files:**
- Modify: `demo/game/main.yuki` (keep narrative; entry still works after Start)
- Modify: `docs/host-commands.md`, `docs/moon-yuki-subset.md`, `docs/project-layout.md`, `README.md` / `README.mbt.md`
- Create: `docs/screen-language.md` (author-facing short guide)
- Update: `docs/project-layout.md` Phase notes

**Demo requirements:**

- After Start, existing intro path still plays (kinds, tweens, wait).  
- Optional: tiny custom screen override example (commented or `demo` only) — optional YAGNI.  
- Ensure `entrypoint` still valid for `start_game`.

**Docs must state:**

- Screen subset + actions  
- Prefs keys  
- Slot keys  
- Esc / arrows  
- D+B: negatives, audio fail, bgm fade  
- Non-goals: backlog, dialogue screen-ization  

- [ ] **Step 1: Write docs**

- [ ] **Step 2: Full suite**

```bash
export CC=gcc
moon check
moon test
moon run cmd/moonsightc --target native -- check demo/game
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Expected: all tests pass; build ok.

- [ ] **Step 3: Spec coverage checklist** (mark in commit message or `.superpowers/sdd` note)

| Spec item | Task |
|-----------|------|
| Screen DSL subset | 5–6 |
| Screen runtime stack/focus | 8–9 |
| Standard 4 screens | 11 |
| Multi-slot + prefs | 7, 11 |
| Cold start title | 9, 11–12 |
| WebGPU only | 10–11 |
| Named negatives | 1 |
| Audio hard-fail | 2 |
| BGM volume/fade | 3 |
| Build cleanup | 4 |
| demo + docs + tests | 12 |

- [ ] **Step 4: Commit**

```bash
git add demo docs README.md README.mbt.md
git commit -m "docs+demo: Phase 3 screen UI and system menu"
```

---

## Spec coverage self-check

| Requirement | Plan task |
|-------------|-----------|
| §1 Screen language + runtime + 4 screens + triad UX + cold start + WebGPU + D+B + demo/docs | Tasks 1–12 |
| §2 UiMode, stack, gating, Intent Esc | Task 9 |
| §3 Syntax, actions, overrides, 6 slots | Tasks 5–6, 11 |
| §4 Saves, prefs, BGM, audio fail, negatives, build cleanup | Tasks 1–4, 7 |
| §5 compile, render order, tests | Tasks 6, 10–12 |
| No backlog / DOM / dialogue screen-ize / confirm / screenshots | Not scheduled |

## Type consistency notes

- Use `ScreenDef` / `SNode` / `ScreenAction` names from Task 6 everywhere after.  
- `UiMode::{Title, Playing, Menu}` from Task 8.  
- Prefs keys: `text_speed`, `auto_mode`, `master_volume`, `bgm_volume`, `se_volume`.  
- Dist artifact: **`screens.json`** + `game.msb` (not only MSB) — host loads both.  
- `save_slots` in `moonsight.json` / `ProjectConfig`.

## Risk flags for implementers

1. **Indent parsing** is the hardest parser piece — if blocked, temporary escape: allow only flat `vbox` children at indent 2 with no nested containers beyond one level; still enough for std screens.  
2. **Macro/resolve** structs must thread `screens` or compile breaks.  
3. **Global mixer** vs engine-owned audio: keep global; prefs applied at host volume multiply.  
4. Do not rewrite dialogue UI in this plan.

---

## Execution handoff

Plan complete when committed to `docs/superpowers/plans/2026-07-10-moonsight-phase3-screen-ui.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — same session with executing-plans checkpoints  

Which approach?
