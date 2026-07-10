# MoonSight Phase 2 — Layer & Presentation Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden Phase 1 layer/presentation debt: wire `LayerKind`, linear property tweens, real `flow.wait` timing, save format v3 (with mid-tween restore), resource diagnostics, and updated demo/docs.

**Architecture:** Keep the theater model. Layers hold current values plus per-property tweens; `Engine::tick(dt)` advances tweens, overlay fade, and timed waits. Host commands are fire-and-forget for animation; scripts synchronize with `@flow.wait`. Named host args are preserved through lower via `#:name` marker values so `kind=` / `duration=` work.

**Tech Stack:** MoonBit (`moon test` / `moon check`), existing `script` → IR → `runtime` → `render` → `host_web` pipeline, JSON saves, `moonsightc` native CLI.

**Spec:** `docs/superpowers/specs/2026-07-10-moonsight-phase2-layers-design.md`

**Pinned defaults (from spec §8):**

| Item | Choice |
|------|--------|
| Default `kind` if omitted | `character` |
| Ease | linear only |
| Named-arg wire format | `Str("#:<name>")` then value (see Task 1) |
| z-tie order | stable by original index in `layers` after kind+z sort |
| Single-arg `layer.show` | keep; empty resource, kind=character |
| Timed wait + Advance | ignore Advance while `wait_remaining > 0` |
| Fade clock | wall-clock `fade_remaining` seconds for whole transition |
| Save | write v3; read v2 + v3 |

---

## File map

| Path | Role |
|------|------|
| `script/lower.mbt` | Preserve named args as `#:name` + value |
| `script/lower_test.mbt` | Named-arg lower tests |
| `script/resolve.mbt` | Add `layer.set` to `builtin_externs` |
| `script/resolve_test.mbt` | Extern list includes `layer.set` |
| `runtime/stage.mbt` | `LayerTween`, tweens, `pending_hide`, wait/fade fields, sort, tick helpers |
| `runtime/stage_test.mbt` | Tween / sort / hide-fade tests |
| `runtime/engine.mbt` | Tick tweens/wait; swallow intents during timed wait |
| `runtime/engine_test.mbt` | Wait + tween integration |
| `runtime/host.mbt` | Arg split helper; builtins match std_commands semantics |
| `runtime/save.mbt` | format v3 + v2 compat load |
| `runtime/save_test.mbt` | v3 round-trip, v2 load, version reject |
| `std_commands/layer.mbt` | show/hide/move/set with kind + duration |
| `std_commands/flow.mbt` | `flow.wait` sets `wait_remaining` |
| `std_commands/trans.mbt` | Align fade to `fade_remaining` |
| `std_commands/registry.mbt` | Register `layer.set` |
| `std_commands/registry_test.mbt` | Command tests |
| `render/snapshot.mbt` | Consume kind+z ordered layers (if sort only in Stage, minimal change) |
| `render/snapshot_test.mbt` | Ordering assertion if needed |
| `cmd/moonsightc/build.mbt` (+ helpers) | Literal resource validation at build |
| `host_web/js_glue/boot.js` | Texture load failure → hard error surface |
| `demo/game/*.yuki` | kind, duration, wait |
| `docs/host-commands.md`, `docs/moon-yuki-subset.md`, `README.mbt.md` | Phase 2 docs |

---

### Task 1: Preserve named host arguments in lower

**Files:**
- Modify: `script/lower.mbt` (`lower_arg` / `lower_args`)
- Modify: `script/lower_test.mbt`

**Context:** Today `Named(name, e)` drops the name and only emits the value, so `kind=background` is indistinguishable from a bare string. Phase 2 needs names at the host.

**Wire format (pinned):** for each named arg, emit two `IrValue`s:

1. `Str("#:<name>")` — marker (`#:` prefix is reserved; scripts should not use this as a normal string literal)
2. the lowered value

Flags stay as today (`Str(flagname)` without `#:`).

- [ ] **Step 1: Write the failing test**

Add to `script/lower_test.mbt`:

```mbt
///|
test "lower preserves named host args as marker pairs" {
  let src =
    #|- scene "s"
    #|@layer.show "bg" "bg_room" kind=background duration=0.4
    #|
  let ir = @script.compile_to_ir(src, file="named.yuki")
  let ops = ir.scenes["s"].ops
  guard ops[0] is Host(name="layer.show", args~) else { fail("layer.show") }
  // id, resource, #:kind, background, #:duration, 0.4
  assert_true(args.length() >= 6)
  guard args[0] is Str("bg") else { fail("id") }
  guard args[1] is Str("bg_room") else { fail("res") }
  guard args[2] is Str("#:kind") else { fail("kind marker") }
  guard args[3] is Str("background") else { fail("kind val") }
  guard args[4] is Str("#:duration") else { fail("dur marker") }
  guard args[5] is Float(0.4) else { fail("dur val") }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /mnt/nvme1n1p2/moonsight && moon test -p script
```

Expected: FAIL on marker assertions (currently values only, names lost).

- [ ] **Step 3: Implement named-arg emission**

In `script/lower.mbt`, replace `lower_args` / `lower_arg` so named args emit pairs:

```mbt
fn lower_args(args : Array[Arg]) -> Array[IrValue] {
  let out : Array[IrValue] = []
  for a in args {
    match a {
      Positional(e) => out.push(lower_expr(e))
      Named(name~, e) => {
        out.push(Str("#:\{name}"))
        out.push(lower_expr(e))
      }
      Flag(name) => out.push(Str(name))
    }
  }
  out
}
```

Remove the old `lower_arg` if unused, or keep only for other call sites. **Do not change** `lower_jump_if` / `lower_choice` special flatteners unless tests break — they already handle `Named` explicitly before `lower_args`.

- [ ] **Step 4: Run tests**

```bash
moon test -p script
```

Expected: PASS (including new test). Fix any tests that assumed named values without markers.

- [ ] **Step 5: Commit**

```bash
git add script/lower.mbt script/lower_test.mbt
git commit -m "feat(script): preserve named host args as #:name pairs"
```

---

### Task 2: Host arg split helper + LayerTween types on Stage

**Files:**
- Modify: `runtime/value.mbt` or `runtime/host.mbt` (prefer `host.mbt` for split helper)
- Modify: `runtime/stage.mbt`
- Modify: `runtime/stage_test.mbt`

- [ ] **Step 1: Write failing tests for tween helpers and sort**

Append to `runtime/stage_test.mbt`:

```mbt
///|
test "tick_layer_tweens eases opacity linearly" {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="y",
    layer=@runtime.LayerKind::Character,
    resource="char_y",
    z=10,
    opacity=0.0,
  )
  st.start_layer_tween(id="y", prop=@runtime.TweenProp::Opacity, to=1.0, duration=1.0)
  st.tick_layer_tweens(0.25)
  assert_eq(st.layers[0].opacity, 0.25)
  st.tick_layer_tweens(0.75)
  assert_eq(st.layers[0].opacity, 1.0)
  assert_eq(st.layers[0].tweens.length(), 0)
}

///|
test "snapshot_layers sorts by kind then z" {
  let st = @runtime.Stage::new()
  st.show_layer(id="c", layer=@runtime.LayerKind::Character, resource="c", z=0)
  st.show_layer(id="b", layer=@runtime.LayerKind::Background, resource="b", z=5)
  st.show_layer(id="e", layer=@runtime.LayerKind::Effect, resource="e", z=0)
  let snap = st.snapshot_layers()
  assert_eq(snap[0].id, "b")
  assert_eq(snap[1].id, "c")
  assert_eq(snap[2].id, "e")
}

///|
test "pending_hide removes layer after opacity tween" {
  let st = @runtime.Stage::new()
  st.show_layer(id="y", layer=@runtime.LayerKind::Character, resource="c", z=1, opacity=1.0)
  st.begin_hide_layer(id="y", duration=0.5)
  st.tick_layer_tweens(0.5)
  assert_eq(st.layers.length(), 0)
}
```

- [ ] **Step 2: Run tests — expect FAIL (missing APIs)**

```bash
moon test -p runtime
```

- [ ] **Step 3: Extend `LayerState` and Stage APIs in `runtime/stage.mbt`**

Add types and fields (keep `derive` where possible; empty tweens default on construct):

```mbt
///|
pub(all) enum TweenProp {
  X
  Y
  Opacity
} derive(Debug, Eq, ToJson, FromJson)

///|
/// One in-flight linear property animation (`from` is always current at start).
pub(all) struct LayerTween {
  prop : TweenProp
  to : Double
  remaining : Double
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct LayerState {
  id : String
  kind : LayerKind
  resource : String
  z : Int
  x : Double
  y : Double
  opacity : Double
  visible : Bool
  tweens : Array[LayerTween]
  pending_hide : Bool
} derive(Debug, Eq, ToJson, FromJson)
```

Update every `LayerState { ... }` literal in the repo to include `tweens: []`, `pending_hide: false`.

Add Stage fields:

```mbt
  /// Seconds left for timed @flow.wait; 0 means not in timed wait.
  mut wait_remaining : Double
  /// Wall-clock seconds left for overlay fade to `fade_to` (0 = done / snap).
  // Replace or reinterpret fade_duration: set fade_remaining on Stage.
  mut fade_remaining : Double
```

Prefer **renaming semantics**: keep field name `fade_duration` only if all call sites update; cleaner to add `fade_remaining` and stop using “seconds per unit”. Spec wants wall-clock remaining — implement `fade_remaining` and migrate `trans.fade` + engine in Task 4–5. For this task, add `wait_remaining: 0.0` and `fade_remaining: 0.0` on Stage; leave old `fade_duration` until Task 4 if needed for compile, then remove.

Implement:

```mbt
pub fn Stage::start_layer_tween(
  self : Stage,
  id~ : String,
  prop~ : TweenProp,
  to~ : Double,
  duration~ : Double,
) -> Unit

pub fn Stage::tick_layer_tweens(self : Stage, dt : Double) -> Unit

pub fn Stage::begin_hide_layer(
  self : Stage,
  id~ : String,
  duration~ : Double,
) -> Unit
```

**Semantics:**

- `start_layer_tween`: find layer; if `duration <= 0`, set property immediately and clear that prop’s tween; else replace any tween with same `prop`, push `{ prop, to, remaining: duration }`.
- `tick_layer_tweens`: for each layer/tween, linear step toward `to` using `dt/remaining` of **remaining distance**, then `remaining -= dt`; at `remaining <= 0` snap to `to` and drop tween. After ticks, remove layers with `pending_hide && opacity <= 0` (or no opacity tween and pending_hide with opacity 0).
- `begin_hide_layer`: if duration<=0, `hide_layer`; else set `pending_hide=true`, start opacity tween to 0.

**`snapshot_layers`:** sort by `(kind_rank, z, index)` where rank: Background=0, Character=1, Effect=2, UI=3, Overlay=4.

**`show_layer`:** initialize `tweens: []`, `pending_hide: false`. Optional later: duration parameter — can wait for std_commands to call tween after show.

- [ ] **Step 4: Add `split_host_args` in `runtime/host.mbt`**

```mbt
///|
/// Split flattened host args: positional values + named map from `#:key` markers.
pub fn split_host_args(
  args : Array[Value],
) -> (Array[Value], Map[String, Value]) {
  let pos : Array[Value] = []
  let named : Map[String, Value] = {}
  var i = 0
  while i < args.length() {
    match args[i] {
      Str(s) =>
        if s.starts_with("#:") && i + 1 < args.length() {
          let key = s.substring(start=2) // adjust to MoonBit string API used in repo
          named[key] = args[i + 1]
          i = i + 2
        } else {
          pos.push(args[i])
          i = i + 1
        }
      _ => {
        pos.push(args[i])
        i = i + 1
      }
    }
  }
  (pos, named)
}
```

Use the project’s actual string prefix/slice API (`s.has_prefix`, `s.drop`, etc. — check existing code). Add a tiny unit test in `runtime` if there is a host test file; otherwise cover via std_commands tests later.

- [ ] **Step 5: Fix compile fallout**

```bash
moon check
moon test -p runtime
```

Update `render/snapshot_test.mbt` and any LayerState literals. Expected: new stage tests PASS.

- [ ] **Step 6: Commit**

```bash
git add runtime/stage.mbt runtime/stage_test.mbt runtime/host.mbt render/
git commit -m "feat(runtime): layer tweens, kind-aware sort, host named-arg split"
```

---

### Task 3: Engine — tick tweens, timed wait, input policy

**Files:**
- Modify: `runtime/engine.mbt`
- Modify: `runtime/engine_test.mbt`
- Modify: `std_commands/flow.mbt` (minimal: set `wait_remaining`)

- [ ] **Step 1: Failing engine tests**

```mbt
///|
test "flow.wait duration resumes after real time" {
  let src =
    #|- scene "s"
    #|@flow.wait 0.5
    #|@var.set "done" true
    #|
  let ir = @script.compile_to_ir(src, file="wait.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s", director=@std_commands.standard_registry())
  eng.tick(None_, dt=0.0)
  // After first run should be Yield with wait_remaining ~ 0.5
  assert_true(eng.vm.wait == Yield)
  assert_true(eng.stage.wait_remaining > 0.0)
  // Advance must not skip
  eng.tick(Advance, dt=0.1)
  assert_true(eng.vm.wait == Yield)
  assert_true(eng.stage.get_var("done") == None_)
  eng.tick(None_, dt=0.5)
  assert_true(eng.stage.get_var("done") == Bool(true) || eng.vm.wait == Halted || eng.vm.wait == Running)
  // After enough time, var set
  eng.tick(None_, dt=0.1)
  assert_true(eng.stage.get_var("done") == Bool(true))
}

///|
test "layer opacity tween advances on engine tick" {
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(
      #|- scene "s"
      #|@flow.yield
      #|
      ,
      file="t.yuki",
    ),
    entry="s",
  )
  eng.stage.show_layer(id="y", layer=Character, resource="c", z=1, opacity=0.0)
  eng.stage.start_layer_tween(id="y", prop=Opacity, to=1.0, duration=1.0)
  eng.tick(None_, dt=0.5)
  assert_eq(eng.stage.layers[0].opacity, 0.5)
}
```

Adjust assertions to match exact VM halt/return behavior of the demo IR.

- [ ] **Step 2: Run — expect FAIL** (`wait_remaining` never set / not ticked)

- [ ] **Step 3: Update `cmd_flow_wait` in `std_commands/flow.mbt`**

```mbt
pub fn cmd_flow_wait(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [t, ..] =>
      match @runtime.value_as_double(t) {
        Some(sec) => {
          if sec > 0.0 {
            stage.wait_remaining = sec
          } else {
            stage.wait_remaining = 0.0
          }
          Yield
        }
        None => Error("flow.wait: expected numeric time")
      }
    [] => {
      stage.wait_remaining = 0.0
      Yield
    }
  }
}
```

Note: bare wait leaves `wait_remaining = 0` and relies on Advance → Running (existing Yield path). Timed wait uses remaining > 0.

- [ ] **Step 4: Update `Engine::tick` / `apply_intent` / add `tick_wait`**

Order (match spec §4):

```mbt
pub fn Engine::tick(self : Engine, intent : Intent, dt? : Double = 1.0 / 60.0) -> Unit {
  let effective = self.effective_intent(intent)
  // Timed wait: swallow Advance/Select/SkipTyping
  let gated =
    if self.stage.wait_remaining > 0.0 {
      match effective {
        Advance | SkipTyping | Select(_) => None_
        other => other
      }
    } else {
      effective
    }
  self.apply_intent(gated)
  self.tick_wait(dt)
  if self.vm.wait is Running {
    self.vm.run_until_wait(self.director, self.stage)
  }
  self.tick_transitions(dt)
  self.stage.tick_layer_tweens(dt)
  self.tick_typewriter(dt)
}

fn Engine::tick_wait(self : Engine, dt : Double) -> Unit {
  if self.stage.wait_remaining > 0.0 {
    let left = self.stage.wait_remaining - dt
    if left <= 0.0 {
      self.stage.wait_remaining = 0.0
      if self.vm.wait is Yield {
        self.vm.wait = Running
      }
    } else {
      self.stage.wait_remaining = left
    }
  }
}
```

**Typewriter interaction:** while `wait_remaining > 0`, do not complete text via Advance (already gated). Prefer not starting timed wait mid-typewriter in demo.

- [ ] **Step 5: Tests pass**

```bash
moon test -p runtime -p std_commands
```

- [ ] **Step 6: Commit**

```bash
git add runtime/engine.mbt runtime/engine_test.mbt std_commands/flow.mbt
git commit -m "feat(runtime): timed flow.wait and engine tween tick"
```

---

### Task 4: Overlay fade wall-clock + `trans.fade`

**Files:**
- Modify: `runtime/engine.mbt` (`tick_transitions`)
- Modify: `std_commands/trans.mbt`
- Modify: `std_commands/registry_test.mbt`, `runtime/engine_test.mbt` (fade tests)

- [ ] **Step 1: Update fade tests** to assert wall-clock behavior: duration `0.5` from 0→1 reaches ~1.0 after 0.5s total, not “0.5s per unit”.

- [ ] **Step 2: Implement**

On `trans.fade` with duration `d > 0`:

- set `overlay_opacity = from` (if from provided)
- `fade_to = to`
- `fade_remaining = d`

`tick_transitions`:

```mbt
fn Engine::tick_transitions(self : Engine, dt : Double) -> Unit {
  let target = self.stage.fade_to
  let cur = self.stage.overlay_opacity
  if cur == target {
    self.stage.fade_remaining = 0.0
    return
  }
  let rem = self.stage.fade_remaining
  if rem <= 0.0 || dt <= 0.0 {
    self.stage.overlay_opacity = target
    self.stage.fade_remaining = 0.0
    return
  }
  let step_t = if dt < rem { dt } else { rem }
  let frac = step_t / rem
  self.stage.overlay_opacity = cur + (target - cur) * frac
  self.stage.fade_remaining = rem - step_t
  if self.stage.fade_remaining <= 1e-12 {
    self.stage.overlay_opacity = target
    self.stage.fade_remaining = 0.0
  }
}
```

Remove dependency on old `fade_duration` rate semantics; delete field or keep unused temporarily then remove in same commit to avoid dual clocks.

- [ ] **Step 3: `moon test -p runtime -p std_commands`** — PASS

- [ ] **Step 4: Commit**

```bash
git commit -am "fix(runtime): wall-clock overlay fade_remaining"
```

---

### Task 5: std_commands layer.show / move / hide / set

**Files:**
- Modify: `std_commands/layer.mbt`
- Modify: `std_commands/registry.mbt`
- Modify: `std_commands/registry_test.mbt`
- Modify: `script/resolve.mbt`, `script/resolve_test.mbt`
- Modify: `runtime/host.mbt` builtins to stay consistent for engines without std_commands

- [ ] **Step 1: Failing registry tests**

```mbt
test "layer.show respects kind and duration opacity" {
  let reg = @std_commands.standard_registry()
  let stage = @runtime.Stage::new()
  // Simulate lowered args: id, res, #:kind, character, #:duration, 0.4, and opacity target via #:opacity
  let args = [
    Str("y"),
    Str("char_y"),
    Str("#:kind"),
    Str("character"),
    Str("#:opacity"),
    Float(1.0),
    Str("#:duration"),
    Float(0.4),
  ]
  ignore(reg.call("layer.show", stage, args))
  assert_true(stage.layers[0].kind == Character)
  assert_eq(stage.layers[0].opacity, 0.0) // new layer starts 0 when duration>0
  stage.tick_layer_tweens(0.4)
  assert_eq(stage.layers[0].opacity, 1.0)
}

test "layer.set errors on missing id" {
  let reg = @std_commands.standard_registry()
  let stage = @runtime.Stage::new()
  let r = reg.call("layer.set", stage, [Str("nope"), Str("#:opacity"), Float(1.0)])
  guard r is Error(_) else { fail("expected error") }
}
```

Use actual `Director` call API (`register_fn` / invoke) as in existing `registry_test.mbt`.

- [ ] **Step 2: Implement parsers in `layer.mbt`**

Shared helpers:

```mbt
fn parse_kind(v : @runtime.Value) -> @runtime.LayerKind? {
  match v {
    Str(s) => {
      let k = s.to_lower() // or manual case fold
      match k {
        "background" => Some(Background)
        "character" => Some(Character)
        "effect" => Some(Effect)
        "ui" => Some(UI)
        "overlay" => Some(Overlay)
        _ => None
      }
    }
    _ => None
  }
}
```

**`cmd_layer_show`:**

1. `(pos, named) = split_host_args(args)`
2. Require `pos[0]` id Str, `pos[1]` resource Str (or single-arg form)
3. `kind` from named `"kind"` or default **Character**
4. `z/x/y/opacity` from named keys if present; else positional `pos[2..]` as z,x,y,opacity (legacy)
5. `duration` from named or 0
6. If layer exists: apply z/kind/resource immediately; for each of x,y,opacity that is “specified”, either snap or tween
7. If new + duration>0: create with target x,y,z,resource,kind, **opacity current=0**, tween opacity to target (default 1.0)
8. If new + duration==0: full target immediately

**`cmd_layer_move`:** id + x + y positionals; optional `#:duration`.

**`cmd_layer_hide`:** id; optional `#:duration` → `begin_hide_layer`.

**`cmd_layer_set`:** id required; named `x`/`y`/`opacity`/`duration`; error if id missing.

- [ ] **Step 3: Register `layer.set`**

`registry.mbt` + `standard_host_names` + `script/resolve.mbt` `builtin_externs` + resolve_test list.

- [ ] **Step 4: Mirror critical behavior in `runtime/host.mbt` builtins** (engines without std_commands still used in some tests). At least default kind=Character and split_host_args for show.

- [ ] **Step 5: Tests**

```bash
moon test -p std_commands -p script -p runtime
```

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(std_commands): layer kind, duration tweens, layer.set"
```

---

### Task 6: Save format v3

**Files:**
- Modify: `runtime/save.mbt`
- Modify: `runtime/save_test.mbt`

- [ ] **Step 1: Failing tests**

```mbt
test "save blob is format_version 3" {
  let eng = load_min_demo_engine()
  eng.tick(None_)
  let game = @runtime.parse_save_game(eng.save())
  assert_eq(game.format_version, 3)
}

test "save roundtrip restores tweens and wait_remaining" {
  // show layer, start tween, set wait_remaining, save, load, assert fields
}

test "load v2 save still works" {
  let eng = load_min_demo_engine()
  let v2 = #|{"format_version":2,...minimal valid v2...}|
  eng.load(v2)
  // kind default character for layers without kind if needed
}
```

Update reject message test: expected versions are 2 or 3; unknown 99 still fails.

- [ ] **Step 2: Implement `SaveGame` v3**

```mbt
pub let save_format_version : Int = 3

pub(all) struct SaveGame {
  format_version : Int
  // ... existing fields ...
  layers : Array[LayerState]  // now includes tweens + pending_hide
  fade_to : Double
  fade_remaining : Double
  wait_remaining : Double
  // keep wait: WaitKind
}
```

**`parse_save_game` / `reject_unsupported_version`:**

- Accept `format_version` in `{2, 3}`
- Reject others
- For v2 JSON missing new fields: either custom decode path or make new fields optional with defaults

Practical approach in MoonBit:

1. Peek version from JSON
2. If 2: decode with a `SaveGameV2` struct (copy of old fields), map into live engine via `apply_save_game_v2`
3. If 3: decode `SaveGame` fully

**`Engine::save`:** always write v3 including `fade_to`, `fade_remaining`, `wait_remaining`, full `LayerState`.

**`apply_save_game`:** restore those Stage fields.

- [ ] **Step 3: Tests pass**

```bash
moon test -p runtime
```

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(runtime): save format v3 with tweens and wait"
```

---

### Task 7: moonsightc literal resource validation

**Files:**
- Modify: `cmd/moonsightc/build.mbt` and/or new `cmd/moonsightc/assets_check.mbt`
- Add: `script/testdata` or `cmd` fixture project missing a resource
- Modify: docs if CLI error message documented

- [ ] **Step 1: Define collection strategy**

After compile IR (or while parsing AST), collect string literals that appear as:

- 2nd positional of `layer.show` host ops
- args of `audio.bgm` / `audio.se`

From IR: scan all scenes’ `Host` ops for those names; for `layer.show`, take first two Str positionals after stripping `#:` pairs (use same split logic or duplicate lightweight scan on `IrValue`).

- [ ] **Step 2: After `collect_asset_manifest`, validate**

```mbt
for id in referenced_resources {
  if !resources.contains(id) && !audio.contains(id) {
    println("error: missing resource `\{id}` referenced by script")
    return 1
  }
}
```

UI-only ids not referenced in scripts need not exist. Empty resource `""` skip.

- [ ] **Step 3: Manual / scripted check**

```bash
# create temp project or use a tiny fixture under script/testdata
moon run cmd/moonsightc --target native -- build path/to/bad_project -o /tmp/out
# expect exit 1 and error line
```

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(moonsightc): fail build on missing literal resources"
```

---

### Task 8: host_web resource load errors

**Files:**
- Modify: `host_web/js_glue/boot.js` (`applyManifest`)

- [ ] **Step 1: Change texture failure from warn-and-continue to fail**

```javascript
} catch (e) {
  console.error("texture failed", id, path, e);
  throw new Error(`MoonSight: failed to load texture '${id}' from '${path}': ${e}`);
}
```

Surface error in the existing boot error UI if present (search `boot.js` for error display); at minimum throw so `init` rejects and user sees console + any catch banner.

- [ ] **Step 2: Manual smoke** (optional in CI): break a path and confirm non-silent failure.

- [ ] **Step 3: Commit**

```bash
git commit -am "fix(host_web): hard-fail missing texture loads"
```

---

### Task 9: Demo + documentation

**Files:**
- Modify: `demo/game/main.yuki`, `demo/game/scenes/intro.yuki` if needed
- Modify: `docs/host-commands.md`, `docs/moon-yuki-subset.md`, `README.mbt.md`

- [ ] **Step 1: Update demo script**

```yuki
- scene "intro"
@layer.show "bg" "bg_room" kind=background
@layer.show "y" "char_y" kind=character z=10 x=-200 opacity=0
@layer.set "y" x=200 opacity=1.0 duration=0.5
@audio.bgm "bgm_soft"
@trans.fade 1.0 0.0 0.5
@flow.wait 0.5
y:Welcome to MoonSight.
# ... rest with kind= on later shows, hide with duration optional
```

- [ ] **Step 2: Rebuild demo**

```bash
export CC=gcc
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Expected: exit 0.

- [ ] **Step 3: Update docs**

- `host-commands.md`: document kind, duration, layer.set, flow.wait timing, input table, save v3
- `moon-yuki-subset.md`: Phase 2 notes; named args
- `README.mbt.md`: Phase 2 scope blurb; keep Phase 1 out-of-scope list updated

- [ ] **Step 4: Commit**

```bash
git commit -am "docs+demo: Phase 2 layer presentation features"
```

---

### Task 10: Full verification

- [ ] **Step 1: Run full suite**

```bash
export CC=gcc
moon check
moon test
moon run cmd/moonsightc --target native -- check demo/game
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Expected: all green; build ok.

- [ ] **Step 2: Spec coverage checklist (manual)**

| Spec requirement | Task |
|------------------|------|
| LayerKind via show | 5 |
| x/y/opacity tween | 2, 3, 5 |
| fire-and-forget + flow.wait | 3 |
| linear ease | 2 |
| pending_hide | 2, 5 |
| kind then z sort | 2 |
| trans.fade hardened | 4 |
| no dissolve | (explicit non-work) |
| wait timed + no skip | 3 |
| save v3 + v2 read | 6 |
| build resource check | 7 |
| runtime fetch fail | 8 |
| demo/docs/tests | 9–10 |

- [ ] **Step 3: Final commit if any fixups**

```bash
git status
# commit residual fixes if needed
```

---

## Self-review (plan vs spec)

| Spec item | Covered? |
|-----------|----------|
| §1 kind + tween + wait + save + diagnostics + demo | Tasks 2–9 |
| §2 Engine tick order | Task 3 |
| §3 API including layer.set, default character, wait input | Tasks 1, 3, 5 |
| §4 v3 save, v2 compat, build+runtime diagnostics | Tasks 6–8 |
| §5 tests | Each task TDD |
| Named args prerequisite (spec assumes kind=/duration=) | **Task 1** (required; was a Phase 1 gap) |
| No editor/timeline/dissolve | Not scheduled |

**Type names locked:** `TweenProp`, `LayerTween`, `wait_remaining`, `fade_remaining`, `#:name` markers, `split_host_args`, `start_layer_tween`, `tick_layer_tweens`, `begin_hide_layer`.

**Note for implementers:** MoonBit string APIs (`starts_with` / `to_lower` / substring) may differ slightly — match patterns already used in the repo (`script` / `runtime`). Director invoke API in tests must copy `registry_test.mbt` style, not invent a new one.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-10-moonsight-phase2-layers.md`.

Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — execute tasks in this session with executing-plans checkpoints  

Which approach?
