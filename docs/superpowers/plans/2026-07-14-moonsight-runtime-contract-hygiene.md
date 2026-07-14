# MoonSight Runtime Contract Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use TDD for each behavior change.

**Goal:** Align five runtime contracts on `main` so docs, MoonBit authority, and Web Host consumption match: menu presentation clocks, audio session clear, grapheme typewriter, glyph atlas growth, and observable VM instruction budget.

**Architecture:** Keep Stage/Engine as narrative authority. Refactor `Engine::tick` so Playing+modal still advances presentation clocks while freezing narrative Advance. Add `Mixer::clear_playback_session` on title/start boundaries. Implement grapheme boundary helpers in `runtime` and use them for reveal/prefix/save clamp. Grow `GlyphAtlas` with a generation counter and teach Host to rebuild the GPU texture. Instrument `Vm::run_until_wait` exhaustion counters without hard-halting.

**Tech Stack:** MoonBit (`moon test` / `moon check --target all` / `moon build --target wasm-gc`), existing `runtime` / `audio` / `render` / `host_web` / `apps/host-web`, Node host tests (`npm test`).

**Design (authoritative):**  
`docs/superpowers/specs/2026-07-14-moonsight-runtime-contract-hygiene-design.md`

**Hard gates:**

1. Integration base = current `main`. Do **not** implement on `.worktrees/1.1-native-desktop` unless rebasing that branch later as a separate merge concern.
2. Formal 1.0 W1/D1/C1 evidence matrix is **read-only**.
3. Save format stays **v5 write / v2–v5 read** — no format bump; only clamp `visible_chars` to grapheme boundaries on load.
4. Default `moonsightc build` / Web package path must remain green after every task.

**Pinned decisions (from design):**

| ID | Choice |
|----|--------|
| H1 | Modal keeps wait / fade / dissolve / tween / typewriter; Title UI-only |
| H2 | `clear_playback_session` on `quit_to_title` / `start_game` / `boot_title`; load still `apply_logic` |
| H3 | `visible_chars` = grapheme-aligned UTF-16 end index; reveal by grapheme |
| H4 | Square grow ×2 to MAX 4096; full repack; `generation++`; terminal 0×0 non-pending if cell > MAX |
| H5 | Exhaustion observable + next-frame retry; no halt; no default player modal |
| `se_seq` on clear | Increment by **1** once per `clear_playback_session` (session boundary marker) |

---

## File map

| Path | Role |
|------|------|
| `runtime/engine.mbt` | H1 tick split; H2 call clear on boot/start/quit; H3 prefix/typewriter; optional H5 export helpers |
| `runtime/engine_test.mbt` | H1 / H2 / H3 integration tests |
| `runtime/stage.mbt` | H3 `reveal_chars` → grapheme semantics; load path clamp if text restored here |
| `runtime/stage_test.mbt` | H3 unit tests for reveal |
| `runtime/grapheme.mbt` | **Create:** boundary / advance / clamp helpers |
| `runtime/grapheme_test.mbt` | **Create:** ASCII/CJK/combining/ZWJ fixtures |
| `runtime/save.mbt` | H3 clamp `visible_chars` when decoding TextBlock |
| `runtime/save_test.mbt` | H3 clamp on load fixture |
| `runtime/vm.mbt` | H5 budget fields + counters in `run_until_wait` |
| `runtime/vm_test.mbt` | H5 exhaustion tests |
| `audio/mixer.mbt` | H2 `clear_playback_session` |
| `audio/mixer_test.mbt` | H2 unit tests |
| `render/glyph_atlas.mbt` | H4 grow / generation / terminal overflow |
| `render/snapshot_test.mbt` or `render/glyph_atlas` tests | H4 tests (extend existing atlas tests) |
| `host_web/main.mbt` | H4 export width/height/generation; `moon.pkg` exports list |
| `host_web/moon.pkg` | Add wasm exports for atlas dimensions/generation |
| `apps/host-web/src/lib/gameSession.ts` | H4 dynamic atlas size + generation rebuild |
| `apps/host-web/src/adapters/webgpu_bridge.js` | Already takes `atlasSize`; ensure callers pass live size |
| `apps/host-web/src/lib/graphemeFixtures.test.mjs` | **Create:** parity fixtures vs documented boundaries (optional if Node-only fixtures duplicated in mbt tests) |
| `docs/play-input.md` | H1 typewriter-under-menu sentence |
| `docs/host-commands.md` | H1 modal clocks; H2 session clear; H5 budget note |
| `docs/slug-text.md` or `docs/ui-moonbit.md` | H3 grapheme reveal note (whichever already discusses typewriter) |
| `CHANGELOG.md` | Unreleased hygiene bullets (honest behavior fixes) |

---

## Task 1: H1 — Menu presentation clocks

**Files:**
- Modify: `runtime/engine.mbt` (`Engine::tick` ~531–603)
- Modify: `runtime/engine_test.mbt`
- Modify: `docs/play-input.md`, `docs/host-commands.md` (can wait until Task 6 if comments updated here)

- [ ] **Step 1: Write failing tests**

Append to `runtime/engine_test.mbt`:

```mbt
///|
test "H1 wait countdown continues while game_menu open" {
  let src =
    #|- scene "s"
    #|@flow.wait 0.5
    #|@var.set "done" true
    #|
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(src, file="h1-wait.yuki"),
    entry="s",
    director=@std_commands.standard_registry(),
  )
  // Register a minimal game_menu so OpenMenu pushes a modal.
  eng.ui.app.register_modal(
    "game_menu",
    @runtime.UiNode::VBox(x=Some(100.0), y=Some(100.0), children=[
      @runtime.UiNode::Button(
        label="Close",
        action_id=0,
        visible=@runtime.VisiblePred::Always,
      ),
    ]),
  )
  eng.tick(None_, dt=0.0)
  assert_true(eng.stage.wait_remaining > 0.4)
  eng.tick(OpenMenu, dt=0.0)
  assert_true(eng.ui.stack_depth() > 0)
  let before = eng.stage.wait_remaining
  eng.tick(None_, dt=0.2)
  assert_true(eng.stage.wait_remaining < before - 0.15)
  eng.tick(None_, dt=0.4)
  // Wait finished under menu; var may already be set via run_until_wait.
  assert_true(eng.stage.wait_remaining <= 0.0)
}

///|
test "H1 fade clock continues while modal open" {
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(
      #|- scene "s"
      #|@flow.yield
      #|
      ,
      file="h1-fade.yuki",
    ),
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.ui.app.register_modal(
    "game_menu",
    @runtime.UiNode::VBox(x=Some(0.0), y=Some(0.0), children=[]),
  )
  eng.tick(None_, dt=0.0)
  eng.stage.fade_to = 1.0
  eng.stage.fade_remaining = 0.5
  eng.tick(OpenMenu, dt=0.0)
  eng.tick(None_, dt=0.2)
  assert_true(eng.stage.fade_remaining < 0.35)
  assert_true(eng.stage.fade_remaining > 0.2)
}

///|
test "H1 layer tween continues while modal open" {
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(
      #|- scene "s"
      #|@flow.yield
      #|
      ,
      file="h1-tween.yuki",
    ),
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.ui.app.register_modal(
    "game_menu",
    @runtime.UiNode::VBox(x=Some(0.0), y=Some(0.0), children=[]),
  )
  eng.tick(None_, dt=0.0)
  // Force a layer + opacity tween if helpers exist; otherwise use stage API
  // matching existing "layer opacity tween advances on engine tick" test setup.
  // Copy the layer setup from that test, then OpenMenu, tick, assert opacity moved.
}

///|
test "H1 skip_held does not burst under modal" {
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(
      #|- scene "s"
      #|@text.begin "A" "line one"
      #|@flow.yield
      #|@text.begin "A" "line two"
      #|@flow.yield
      #|
      ,
      file="h1-skip.yuki",
    ),
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.ui.app.register_modal(
    "game_menu",
    @runtime.UiNode::VBox(x=Some(0.0), y=Some(0.0), children=[]),
  )
  eng.tick(None_, dt=0.0)
  eng.tick(OpenMenu, dt=0.0)
  let text_before = match eng.stage.text {
    Some(t) => t.full_text
    None => ""
  }
  eng.tick(None_, dt=0.05, skip_held=true)
  let text_after = match eng.stage.text {
    Some(t) => t.full_text
    None => ""
  }
  assert_eq(text_before, text_after)
}
```

For the layer-tween test, **copy the exact layer setup** from existing test `"layer opacity tween advances on engine tick"` in the same file (do not invent a different Stage API).

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd /mnt/nvme1n1p2/moonsight && export CC=gcc
moon test -p moonsight/moonsight/runtime -v 2>&1 | tail -60
```

Expected: H1 wait/fade tests FAIL because modal early-return freezes clocks.

- [ ] **Step 3: Implement `Engine::tick` split**

Replace the single `ui_active` early-return block with Title vs modal vs Playing paths per design §3.3.

Concrete structure to land in `runtime/engine.mbt`:

```mbt
pub fn Engine::tick(
  self : Engine,
  intent : Intent,
  dt? : Double = 1.0 / 60.0,
  skip_held? : Bool = false,
) -> Unit {
  if intent is Rollback {
    self.rollback_latest()
    return
  }

  // Title: UI only (no narrative presentation clocks required).
  if self.ui.mode is Title {
    self.tick_ui(intent)
    @audio.global_mixer().tick(dt)
    self.drain_ui_ops()
    return
  }

  // Playing + modal stack: menu input + presentation clocks; no narrative Advance.
  if self.ui.stack_depth() > 0 {
    self.tick_ui(intent)
    self.tick_wait(dt)
    if self.vm.wait is Running {
      self.vm.run_until_wait(self.director, self.stage)
    }
    self.relocalize_new_presentation()
    self.enforce_completed_effects()
    self.drain_ui_ops()
    self.tick_transitions(dt)
    self.stage.tick_layer_tweens(dt)
    self.tick_typewriter(dt)
    @audio.global_mixer().tick(dt)
    return
  }

  // Playing, empty stack — existing narrative path.
  let effective = self.effective_intent(intent)
  if effective is OpenMenu {
    self.ui.show_modal("game_menu")
    // Fall through into modal presentation for this frame via re-entry pattern:
    // after show_modal, stack non-empty — call shared presentation helper OR
    // duplicate the modal presentation ticks once then return.
    self.tick_wait(dt)
    if self.vm.wait is Running {
      self.vm.run_until_wait(self.director, self.stage)
    }
    self.relocalize_new_presentation()
    self.enforce_completed_effects()
    self.drain_ui_ops()
    self.tick_transitions(dt)
    self.stage.tick_layer_tweens(dt)
    self.tick_typewriter(dt)
    @audio.global_mixer().tick(dt)
    return
  }
  if effective is OpenBacklog {
    self.ui.show_modal("backlog")
    self.tick_wait(dt)
    if self.vm.wait is Running {
      self.vm.run_until_wait(self.director, self.stage)
    }
    self.relocalize_new_presentation()
    self.enforce_completed_effects()
    self.drain_ui_ops()
    self.tick_transitions(dt)
    self.stage.tick_layer_tweens(dt)
    self.tick_typewriter(dt)
    @audio.global_mixer().tick(dt)
    return
  }

  // ... remainder of existing Playing path unchanged
  // (wait gate, apply_intent, skip_burst only when stack empty, etc.)
}
```

**Prefer** extracting a private `fn Engine::tick_presentation(self, dt)` used by modal and OpenMenu/OpenBacklog paths to avoid triple duplication.

Update the doc comment on `tick` (remove “layer tweens only while Playing” / freeze wording).

- [ ] **Step 4: Run tests — expect PASS**

```bash
export CC=gcc
moon test -p moonsight/moonsight/runtime 2>&1 | tail -40
```

Expected: all runtime tests PASS including new H1 tests.

- [ ] **Step 5: Commit**

```bash
git add runtime/engine.mbt runtime/engine_test.mbt
git commit -m "$(cat <<'EOF'
fix: keep presentation clocks running under system menus

Modal UI no longer freezes wait, fade/dissolve, layer tweens, or typewriter.
Title remains UI-only; narrative Advance stays gated while menus are open.
EOF
)"
```

---

## Task 2: H2 — Audio session clear

**Files:**
- Modify: `audio/mixer.mbt`
- Modify: `audio/mixer_test.mbt`
- Modify: `runtime/engine.mbt` (`boot_title`, `start_game`, `quit_to_title`)
- Modify: `runtime/engine_test.mbt` (optional integration)

- [ ] **Step 1: Write failing mixer tests**

Append to `audio/mixer_test.mbt`:

```mbt
///|
test "clear_playback_session stops bgm and clears se" {
  let q = QueueBackend::new()
  let m = Mixer::with_backend((q : &AudioBackend))
  m.set_pref_gains(master=0.8, bgm=0.7, se=0.6)
  m.play_bgm("bgm_soft", volume=1.0)
  m.play_se("click", volume=1.0)
  let _ = q.take() // drain play events if take exists; else ignore
  m.fade_bgm_to(0.0, 1.0, stop=true)
  m.clear_playback_session()
  assert_true(m.bgm is None)
  assert_true(m.se is None)
  assert_true(m.bgm_fade_to is None)
  // prefs preserved
  assert_true(m.pref_master > 0.79 && m.pref_master < 0.81)
  assert_true(m.pref_bgm > 0.69 && m.pref_bgm < 0.71)
  // backend received StopBgm
  let mut saw_stop = false
  for i in 0..<q.len() {
    if q.get(i) is Some(StopBgm) {
      saw_stop = true
    }
  }
  assert_true(saw_stop)
}

///|
test "clear_playback_session is idempotent" {
  let m = Mixer::new()
  m.clear_playback_session()
  m.clear_playback_session()
  assert_true(m.bgm is None)
}
```

If `QueueBackend::take` does not exist, use only `len`/`get` after clear (StopBgm should appear after prior PlayBgm). Check `audio/mixer_test.mbt` for existing drain helpers and match them.

If `pref_master` is not publicly readable, assert via behavior: after clear + `play_bgm` + `set_pref_gains` re-emit, or add a test-only read. Prefer asserting through `output` events rather than exposing prefs if they are private — in that case only assert `bgm`/`se`/StopBgm and document prefs via “set_pref_gains still multiplies after clear”.

- [ ] **Step 2: Run — expect FAIL**

```bash
export CC=gcc
moon test -p moonsight/moonsight/audio -v 2>&1 | tail -30
```

Expected: FAIL — `clear_playback_session` missing.

- [ ] **Step 3: Implement mixer API**

In `audio/mixer.mbt`:

```mbt
///|
/// Hard-stop logical playback for a session boundary (title / new game).
/// Preserves preference gains and the installed backend.
pub fn Mixer::clear_playback_session(self : Mixer) -> Unit {
  self.clear_fade()
  self.stop_bgm()
  self.se = None
  self.se_volume = 1.0
  self.se_seq = self.se_seq + 1
}
```

- [ ] **Step 4: Wire Engine entry points**

At the **start** of `boot_title`, `start_game`, and `quit_to_title`:

```mbt
@audio.global_mixer().clear_playback_session()
```

At the **end** of each (after stage/vm updates as applicable):

```mbt
self.sync_mixer_prefs()
```

`boot_title` currently does not rebuild stage — still clear audio + sync prefs.

- [ ] **Step 5: Integration test (engine)**

```mbt
///|
test "H2 quit_to_title clears global mixer bgm" {
  @audio.reset_global_mixer()
  let q = @audio.QueueBackend::new()
  @audio.install_mixer(@audio.Mixer::with_backend((q : &@audio.AudioBackend)))
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(
      #|- scene "s"
      #|@flow.yield
      #|
      ,
      file="h2.yuki",
    ),
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.ui.app.register_modal(
    "title",
    @runtime.UiNode::VBox(x=Some(0.0), y=Some(0.0), children=[]),
  )
  @audio.global_mixer().play_bgm("bgm_soft", volume=1.0)
  eng.quit_to_title()
  assert_true(@audio.global_mixer().bgm is None)
  @audio.reset_global_mixer()
}
```

If `Mixer.bgm` is not public, assert via QueueBackend `StopBgm` after quit.

- [ ] **Step 6: Run tests PASS + commit**

```bash
export CC=gcc
moon test -p moonsight/moonsight/audio -p moonsight/moonsight/runtime 2>&1 | tail -40
git add audio/mixer.mbt audio/mixer_test.mbt runtime/engine.mbt runtime/engine_test.mbt
git commit -m "$(cat <<'EOF'
fix: clear logical audio on title and new-game boundaries

Stop BGM, cancel fades, and reset SE state while preserving preference
gains so quit-to-title and start_game cannot leave ghost playback.
EOF
)"
```

---

## Task 3: H3 — Grapheme typewriter

**Files:**
- Create: `runtime/grapheme.mbt`
- Create: `runtime/grapheme_test.mbt`
- Modify: `runtime/stage.mbt` (`reveal_chars`, `complete_text` unchanged semantics for complete)
- Modify: `runtime/engine.mbt` (`visible_text_prefix`, `tick_typewriter` comments)
- Modify: `runtime/save.mbt` (clamp on decode)
- Modify: `runtime/save_test.mbt`, `runtime/stage_test.mbt`

- [ ] **Step 1: Write failing grapheme unit tests**

Create `runtime/grapheme_test.mbt`:

```mbt
///|
test "grapheme boundaries ascii" {
  let b = grapheme_boundaries("ab")
  assert_eq(b, [0, 1, 2])
}

///|
test "grapheme boundaries cjk" {
  let s = "你好"
  let b = grapheme_boundaries(s)
  assert_eq(b.length(), 3) // 0, end of 你, end of 好
  assert_eq(b[0], 0)
  assert_eq(b[b.length() - 1], s.length())
}

///|
test "combining accent is one grapheme" {
  // e + combining acute
  let s = "e\u{0301}"
  let b = grapheme_boundaries(s)
  assert_eq(b.length(), 2) // 0 and full length
  assert_eq(advance_visible_utf16(s, 0, 1), s.length())
}

///|
test "zwj family emoji is one grapheme" {
  // Family: man+ZWJ+woman+ZWJ+girl+ZWJ+boy — use the same scalar sequence as
  // apps/host-web graphemeProgress tests where possible.
  let s = "👨‍👩‍👧‍👦"
  let b = grapheme_boundaries(s)
  assert_eq(b.length(), 2)
  assert_eq(advance_visible_utf16(s, 0, 1), s.length())
}

///|
test "clamp floors to boundary" {
  let s = "👨‍👩‍👧‍👦X"
  let mid = 2 // almost certainly inside the cluster for UTF-16
  let c = clamp_to_grapheme_boundary(s, mid)
  assert_true(c == 0 || c == grapheme_boundaries(s)[1])
  // mid inside first cluster must clamp to 0 or first end — never mid if mid not boundary
  let bounds = grapheme_boundaries(s)
  let mut is_bound = false
  for b in bounds {
    if b == mid {
      is_bound = true
    }
  }
  if !is_bound {
    assert_true(c != mid)
  }
}
```

Adjust emoji literal if the toolchain rejects it — use `\u{...}` sequences.

- [ ] **Step 2: Run — expect FAIL**

```bash
export CC=gcc
moon test -p moonsight/moonsight/runtime -v 2>&1 | tail -40
```

Expected: FAIL — missing grapheme helpers.

- [ ] **Step 3: Implement `runtime/grapheme.mbt`**

Practical Extended Grapheme Cluster **subset** (document limits in file header):

```mbt
///|
/// Grapheme boundary helpers (UAX #29 practical subset).
///
/// Supports: scalar bases, common combining marks, regional-indicator pairs,
/// ZWJ emoji sequences. Not a full ICU segmenter; Hangul jamo complex
/// sequences are best-effort.

///|
pub fn grapheme_boundaries(text : String) -> Array[Int] {
  // Iterate text by Char / code unit consistent with String.length().
  // Emit [0, end1, end2, ..., text.length()].
  // Algorithm sketch:
  // - Walk scalars with their UTF-16 widths (c.utf16_len() if available, else 1).
  // - Start cluster at each base; extend while:
  //   * combining mark (Mn/Me ranges — hardcode common blocks), or
  //   * ZWJ then another emoji extender, or
  //   * second Regional Indicator after a first RI
  // - Push end index after each cluster.
  ...
}

///|
pub fn grapheme_count(text : String) -> Int {
  let b = grapheme_boundaries(text)
  if b.length() == 0 {
    0
  } else {
    b.length() - 1
  }
}

///|
pub fn clamp_to_grapheme_boundary(text : String, utf16 : Int) -> Int {
  let b = grapheme_boundaries(text)
  let mut best = 0
  for x in b {
    if x <= utf16 {
      best = x
    }
  }
  best
}

///|
pub fn advance_visible_utf16(
  text : String,
  current_utf16 : Int,
  grapheme_delta : Int,
) -> Int {
  if grapheme_delta <= 0 {
    return clamp_to_grapheme_boundary(text, current_utf16)
  }
  let b = grapheme_boundaries(text)
  // Find largest boundary <= current; move grapheme_delta steps forward.
  ...
}

///|
pub fn visible_prefix(text : String, visible_utf16 : Int) -> String {
  let end = clamp_to_grapheme_boundary(text, visible_utf16)
  if end <= 0 {
    ""
  } else if end >= text.length() {
    text
  } else {
    text.unsafe_substring(start=0, end=end)
  }
}
```

Use existing `Char`/`utf16_len` patterns from `runtime/locale.mbt` if present.

- [ ] **Step 4: Wire Stage + Engine + Save**

`Stage::reveal_chars` — keep the name for call-site stability, change body:

```mbt
pub fn Stage::reveal_chars(self : Stage, n : Int) -> Unit {
  if n <= 0 {
    return
  }
  match self.text {
    None => ()
    Some(t) => {
      if t.complete {
        return
      }
      let next = advance_visible_utf16(t.full_text, t.visible_chars, n)
      let len = t.full_text.length()
      let visible = if next >= len { len } else { next }
      self.text = Some({
        ..t,
        visible_chars: visible,
        complete: visible >= len,
      })
    }
  }
}
```

`visible_text_prefix` in engine → call `visible_prefix` / `clamp_to_grapheme_boundary`.

On save decode of `TextBlock`, after reading `visible_chars`:

```mbt
visible_chars: clamp_to_grapheme_boundary(full_text, raw_visible)
```

- [ ] **Step 5: Stage/engine/save tests**

```mbt
///|
test "H3 typewriter reveal does not split combining mark" {
  // text.begin with combining sequence; tick_typewriter or reveal_chars(1);
  // visible prefix length == full combining cluster length
}

///|
test "H3 load clamps mid-cluster visible_chars" {
  // Craft minimal save JSON or use Engine::save after forcing a bad visible_chars
  // if tests can mutate TextBlock; assert after load visible_chars is boundary.
}
```

- [ ] **Step 6: Host fixture parity (lightweight)**

Add `apps/host-web/src/lib/graphemeBoundaries.fixture.json` **or** a small test in `graphemeProgress.test.mjs` that documents expected ends for the same strings as `grapheme_test.mbt`. MoonBit remains runtime authority; Host test is documentation/parity, not a second engine.

- [ ] **Step 7: PASS + commit**

```bash
export CC=gcc
moon test -p moonsight/moonsight/runtime 2>&1 | tail -50
git add runtime/grapheme.mbt runtime/grapheme_test.mbt runtime/stage.mbt runtime/engine.mbt runtime/save.mbt runtime/save_test.mbt runtime/stage_test.mbt apps/host-web/src/lib/graphemeProgress.test.mjs
git commit -m "$(cat <<'EOF'
fix: advance typewriter on grapheme cluster boundaries

Keep visible_chars as a grapheme-aligned UTF-16 end index, clamp on load,
and share boundary helpers so dialogue reveal never splits ZWJ or marks.
EOF
)"
```

---

## Task 4: H4 — Glyph atlas growth + Host rebuild

**Files:**
- Modify: `render/glyph_atlas.mbt`
- Modify: `render/snapshot_test.mbt` (atlas tests section)
- Modify: `host_web/main.mbt`, `host_web/moon.pkg`
- Modify: `apps/host-web/src/lib/gameSession.ts`
- Modify: `apps/host-web/src/lib/wasm.ts` (HostExports types if present)
- Modify: `apps/host-web/src/adapters/webgpu_bridge.js` only if needed for resize API

- [ ] **Step 1: Write failing atlas tests**

Replace/extend `"glyph atlas oversized cell is zero placeholder"` behavior and add:

```mbt
///|
test "H4 shelf overflow grows atlas and bumps generation" {
  let atlas = GlyphAtlas::new(width=64, height=64)
  let g0 = atlas.generation
  // Fill with many 32x32 cells until shelf would overflow old size.
  for i in 0..<8 {
    let ch = Char::from_int(0x41 + i) // 'A'.. 
    let _ = atlas.get_or_queue(ch, 32, cell_w=32, cell_h=32)
  }
  assert_true(atlas.width >= 128 || atlas.height >= 128)
  assert_true(atlas.generation > g0)
}

///|
test "H4 cell larger than MAX is terminal non-pending" {
  let atlas = GlyphAtlas::new(width=64, height=64)
  // Force MAX path: either set max via test helper or queue cell_w=5000
  let e = atlas.get_or_queue('Z', 64, cell_w=5000, cell_h=5000)
  assert_eq(e.atlas_w, 0)
  assert_eq(e.atlas_h, 0)
  assert_true(!e.pending)
  let e2 = atlas.get_or_queue('Z', 64, cell_w=5000, cell_h=5000)
  assert_true(!e2.pending)
  // Must not grow pending_queue unboundedly
  assert_true(atlas.pending_queue.length() <= 1)
}
```

Expose `generation` on `GlyphAtlas` as `mut generation : Int` default 0, readable in tests.

- [ ] **Step 2: Run — expect FAIL**

```bash
export CC=gcc
moon test -p moonsight/moonsight/render -v 2>&1 | tail -40
```

- [ ] **Step 3: Implement grow in `get_or_queue`**

Constants:

```mbt
let atlas_max_edge : Int = 4096
```

When shelf cannot place cell and `width < atlas_max_edge`:

1. `new_edge = min(atlas_max_edge, max(width * 2, next_pow2(cell need)))`  
2. Set `width = height = new_edge`  
3. `generation += 1`  
4. Clear `entries`, reset cursors, rebuild by re-queueing **all previously known (ch,size)** pairs plus the new glyph (keep a side list `all_keys` or rebuild from entries before clear)  
5. Return the new entry for `ch`

When cell edge > `atlas_max_edge` **or** still cannot fit after at max:

```mbt
{ atlas_x: 0, atlas_y: 0, atlas_w: 0, atlas_h: 0, pending: false }
```

Do **not** push terminal overflows onto `pending_queue`.

Update old test `"glyph atlas oversized cell is zero placeholder"`: cell 64 on 32×32 atlas should **grow** (not permanent 0×0) if 64 ≤ 4096. Change that test to expect growth **or** replace with the H4 terminal test for cell > MAX.

- [ ] **Step 4: Export from `host_web`**

In `host_web/main.mbt`:

```mbt
pub fn atlas_width() -> Int { session.val.atlas.width }
pub fn atlas_height() -> Int { session.val.atlas.height }
pub fn atlas_generation() -> Int { session.val.atlas.generation }
```

Add to `host_web/moon.pkg` `link.wasm-gc.exports` list: `atlas_width`, `atlas_height`, `atlas_generation`.

- [ ] **Step 5: Host `gameSession.ts`**

```typescript
// Module state
let lastAtlasGeneration = -1;
let atlasEdge = 1024;

function ensureAtlasTexture(exports_: HostExports): number {
  const gen = exports_.atlas_generation?.() ?? 0;
  const w = exports_.atlas_width?.() ?? 1024;
  const h = exports_.atlas_height?.() ?? 1024;
  const edge = Math.max(w, h);
  if (gen !== lastAtlasGeneration || edge !== atlasEdge) {
    lastAtlasGeneration = gen;
    atlasEdge = edge;
    // Force GPU atlas recreate: call bridge with empty full texture of edge×edge
    Gpu.rasterizeGlyphToAtlas(" ", 1, 0, 0, 1, 1, edge); // or dedicated resizeAtlas(edge)
  }
  return edge;
}

function flushPendingGlyphs(exports_: HostExports): void {
  const edge = ensureAtlasTexture(exports_);
  // ... existing loop, pass `edge` instead of 1024
  // Skip when atlasW/H <= 0 without treating as hard failure retry storm
}
```

Extend `HostExports` with optional `atlas_width?: () => number` etc.

If `webgpu_bridge.js` only grows when `entry.width < atlasSize`, calling with larger `atlasSize` already recreates — confirm by reading `rasterizeGlyphToAtlas` (~833). Prefer a clear `resizeGlyphAtlas(edge)` export if recreate-on-stamp is fragile.

- [ ] **Step 6: Host unit test (optional thin)**

If pure functions are extractable, test generation change updates cached edge. Otherwise rely on MoonBit tests + manual smoke.

- [ ] **Step 7: Build wasm + host tests + commit**

```bash
export CC=gcc
moon test -p moonsight/moonsight/render
moon build --target wasm-gc --release host_web
cd apps/host-web && npm test && npx tsc --noEmit && cd ../..
git add render/glyph_atlas.mbt render/snapshot_test.mbt host_web/main.mbt host_web/moon.pkg apps/host-web/src/lib/gameSession.ts apps/host-web/src/lib/wasm.ts apps/host-web/src/adapters/webgpu_bridge.js
git commit -m "$(cat <<'EOF'
feat: grow glyph atlas on overflow with host texture rebuild

Double square atlas size up to 4096, repack glyphs under a generation
counter, and teach the Web host to resize instead of spinning on 0×0.
EOF
)"
```

---

## Task 5: H5 — VM budget observability

**Files:**
- Modify: `runtime/vm.mbt`
- Modify: `runtime/vm_test.mbt`
- Optional: `host_web/main.mbt` exports for diagnostics (not required for player UI)

- [ ] **Step 1: Write failing tests**

```mbt
///|
test "H5 budget exhaustion increments counter without halt" {
  // Build a Vm with many Nop ops or use budget=2 on a longer linearized scene.
  // Prefer: compile a scene with many @var.set in a row without yield, or
  // construct Vm fields if tests can.
  let src = build_long_var_set_scene(30) // helper that emits 30 var sets
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(src, file="h5.yuki"),
    entry="s",
    director=@std_commands.standard_registry(),
  )
  // Call run_until_wait with tiny budget via test hook OR
  // eng.vm.run_until_wait(..., budget=2)
  eng.vm.run_until_wait(eng.director, eng.stage, budget=2)
  assert_true(!eng.vm.halted)
  assert_true(eng.vm.budget_exhaustions >= 1)
  assert_true(eng.vm.last_budget_exhausted)
  eng.vm.run_until_wait(eng.director, eng.stage, budget=10000)
  // eventually completes; last flag cleared when exit is not exhaustion
}
```

If `run_until_wait` is hard to invoke with custom budget from tests, add:

```mbt
pub fn Vm::run_until_wait_with_budget(
  self : Vm,
  director : Director,
  stage : Stage,
  budget : Int,
) -> Unit {
  self.run_until_wait(director, stage, budget~)
}
```

Or simply make the optional `budget~` already public (it is).

- [ ] **Step 2: Run — expect FAIL** (missing fields)

- [ ] **Step 3: Implement**

Add to `Vm`:

```mbt
mut budget_exhaustions : Int
mut last_budget_exhausted : Bool
```

Initialize to `0` / `false` in `from_module` / constructors.

In `run_until_wait` loop:

```mbt
self.last_budget_exhausted = false
var steps = 0
for _ in 0..<budget {
  ...
  steps = steps + 1
  // existing op execution
}
// If exited because for-loop completed without wait leaving Running break:
if self.wait is Running && !self.halted {
  // still running means budget spent
  self.budget_exhaustions = self.budget_exhaustions + 1
  self.last_budget_exhausted = true
}
```

Careful: if loop breaks early on Yield, do **not** count exhaustion. Only when the for-loop ends with `wait == Running` and not halted.

Optional Engine helpers:

```mbt
pub fn Engine::vm_budget_exhaustions(self) -> Int { self.vm.budget_exhaustions }
pub fn Engine::vm_budget_exhausted_last_frame(self) -> Bool { self.vm.last_budget_exhausted }
```

- [ ] **Step 4: PASS + commit**

```bash
export CC=gcc
moon test -p moonsight/moonsight/runtime 2>&1 | tail -40
git add runtime/vm.mbt runtime/vm_test.mbt runtime/engine.mbt
git commit -m "$(cat <<'EOF'
feat: observe VM instruction budget exhaustion without halting

Count frame budget hits and expose last-frame flags so long scripts can
continue next frame while authors can diagnose hot loops.
EOF
)"
```

---

## Task 6: Docs, changelog, full regression

**Files:**
- Modify: `docs/play-input.md`
- Modify: `docs/host-commands.md`
- Modify: `docs/ui-moonbit.md` and/or `docs/slug-text.md` (typewriter grapheme note)
- Modify: `CHANGELOG.md` under `[1.0.0] - Unreleased` or a Hygiene subsection

- [ ] **Step 1: Update docs**

`docs/play-input.md` — under presentation clocks:

- State explicitly that **typewriter continues while modals are open**.  
- Keep wait/fade/dissolve language; ensure no leftover “freeze presentation on menu”.

`docs/host-commands.md` — modal row for `flow.wait` already says countdown continues; add:

- Quit to Title / Start: **logical audio session cleared** (BGM stop, SE cleared; prefs kept).  
- VM: frame instruction budget may span frames; exhaustion is diagnostic only.

Grapheme: one short paragraph — reveal advances by grapheme cluster; `visible_chars` is UTF-16 end index on a boundary.

Atlas: optional one-liner in draw/slug docs — atlas may grow to 4096.

- [ ] **Step 2: CHANGELOG**

```markdown
### Fixed
- System menus no longer pause wait, fade/dissolve, layer tweens, or typewriter clocks.
- Quit-to-title and new game hard-stop logical BGM/SE (preference volumes preserved).
- Typewriter reveal follows grapheme clusters; mid-cluster save values clamp on load.
- Glyph atlas grows instead of spinning on zero-sized pending slots (max 4096).

### Added
- VM instruction-budget exhaustion counters for diagnostics (no player halt).
```

- [ ] **Step 3: Full regression**

```bash
export CC=gcc
moon check --target all
moon test
moon build --target wasm-gc --release host_web
cd apps/host-web && npm test && npx tsc --noEmit && npm run build && cd ../..
moon run cmd/moonsightc --target native -- check demo/game
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Expected: all PASS. If `moon fmt --check` is used in CI, run `moon fmt` on touched packages first.

- [ ] **Step 4: Commit**

```bash
git add docs/play-input.md docs/host-commands.md docs/ui-moonbit.md docs/slug-text.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs: align play-input and host-commands with runtime hygiene contracts

Document menu presentation clocks, audio session clear, grapheme reveal,
atlas growth, and VM budget diagnostics to match the implemented behavior.
EOF
)"
```

---

## Self-review (plan vs design)

| Design requirement | Task |
|--------------------|------|
| H1 modal clocks + typewriter under menu | Task 1 |
| H1 Title UI-only | Task 1 |
| H2 clear on quit/start/boot_title | Task 2 |
| H2 load still apply_logic | Task 2 (no load change) |
| H3 grapheme reveal + clamp + no format bump | Task 3 |
| H4 grow to 4096 + generation + Host rebuild | Task 4 |
| H4 terminal overflow non-pending | Task 4 |
| H5 observable + retry | Task 5 |
| Docs + regression | Task 6 |
| No Formal 1.0 / 1.1 scope | Hard gates |

**Placeholder scan:** No TBD steps; layer-tween H1 test reuses existing setup; emoji fixtures may use `\u` escapes if literals fail.

**Type consistency:** `clear_playback_session`, `generation`, `budget_exhaustions`, `last_budget_exhausted`, `atlas_width/height/generation` exports named consistently across tasks.

---

## Execution notes

- Prefer isolated worktree from `main` for long runs, but not required by design (unlike 1.1).  
- Do not flip any `production_ready` or Formal 1.0 evidence fields.  
- If Task 4 Host rebuild is flaky on GPU CI, keep MoonBit tests green and document Host path coverage as unit-level generation/edge plumbing.
