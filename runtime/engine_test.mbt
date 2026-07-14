///|
test "choice selects branch" {
  let src =
    #|- scene "s"
    #|@flow.choice "Yes" "No" --result c
    #|
  let ir = @script.compile_to_ir(src, file="choice.yuki")
  let ops = ir.scenes["s"].ops
  guard ops[0] is Choose(options~, result_var~) else {
    fail("expected IrOp::Choose from flow.choice")
  }
  assert_eq(result_var, "c")
  assert_eq(options.length(), 2)
  assert_eq(options[0], "Yes")
  assert_eq(options[1], "No")

  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  assert_true(eng.vm.wait == Choose)
  guard eng.stage.choices is Some(ch) else { fail("choices on stage") }
  assert_eq(ch.options.length(), 2)
  assert_eq(ch.options[0], "Yes")

  eng.tick(Select(0))
  assert_true(eng.stage.get_var("c") == Int(0))
  assert_true(eng.stage.choices is None)
  assert_true(eng.vm.wait == Halted)
}

///|
test "choice named result form lowers and selects" {
  let src =
    #|- scene "s"
    #|@flow.choice result="c" "Yes" "No"
    #|
  let ir = @script.compile_to_ir(src, file="choice2.yuki")
  guard ir.scenes["s"].ops[0] is Choose(result_var~, options~) else {
    fail("Choose")
  }
  assert_eq(result_var, "c")
  assert_eq(options[1], "No")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  eng.tick(Select(1))
  assert_true(eng.stage.get_var("c") == Int(1))
}

///|
test "choice Advance commits focused row; MenuDown moves focus" {
  let src =
    #|- scene "s"
    #|@flow.choice "Talk" "Leave" --result act
    #|
  let ir = @script.compile_to_ir(src, file="choice_adv.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  assert_true(eng.vm.wait == Choose)
  guard eng.stage.choice_focus() is Some(0) else { fail("focus 0") }
  eng.tick(MenuDown)
  guard eng.stage.choice_focus() is Some(1) else { fail("focus Leave") }
  // HUD highlight must track Stage focus (commit path uses Stage).
  assert_eq(eng.ui.hud_focus, 1)
  eng.sync_ui_bind()
  assert_eq(eng.ui.hud_focus, 1)
  eng.tick(Advance)
  assert_true(eng.stage.get_var("act") == Int(1))
  assert_true(eng.stage.choices is None)
}

///|
test "sync_ui_bind aligns hud_focus with stage choice focus" {
  let src =
    #|- scene "s"
    #|@flow.choice "A" "B" "C" --result pick
    #|
  let ir = @script.compile_to_ir(src, file="choice_hud_sync.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  assert_true(eng.vm.wait == Choose)
  // Simulate stale HUD focus while Stage still starts at 0.
  eng.ui.hud_focus = 2
  eng.sync_ui_bind()
  assert_eq(eng.ui.hud_focus, 0)
  guard eng.stage.choice_focus() is Some(0) else { fail("stage 0") }
  eng.tick(MenuDown)
  eng.tick(MenuDown)
  guard eng.stage.choice_focus() is Some(2) else { fail("stage 2") }
  assert_eq(eng.ui.hud_focus, 2)
  eng.ui.hud_focus = 0
  eng.sync_ui_bind()
  assert_eq(eng.ui.hud_focus, 2)
}

///|
test "engine view snapshots stage for render" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|
  let ir = @script.compile_to_ir(src, file="view.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  let view = eng.view()
  assert_eq(view.scene, "s")
  assert_true(view.wait == Yield)
  guard view.text is Some(t) else { fail("view text") }
  assert_eq(t.full_text, "Hi")
  assert_true(view.auto == false)
}

///|
test "fade transition eases overlay toward target" {
  let fade_src =
    #|- scene "s"
    #|
  let ir = @script.compile_to_ir(fade_src, file="fade.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.stage.overlay_opacity = 0.0
  eng.stage.fade_to = 1.0
  eng.stage.fade_remaining = 0.5
  // Wall-clock: duration 0.5 from 0→1 is halfway after 0.25s total
  eng.tick(None_, dt=0.25)
  assert_true(eng.stage.overlay_opacity > 0.45)
  assert_true(eng.stage.overlay_opacity < 0.55)
  assert_true(eng.stage.fade_remaining > 0.2)
  assert_true(eng.stage.fade_remaining < 0.3)
  // Finish remaining wall-clock time → reaches ~1.0 after 0.5s total
  eng.tick(None_, dt=0.25)
  assert_eq(eng.stage.overlay_opacity, 1.0)
  assert_eq(eng.stage.fade_remaining, 0.0)
}

///|
/// Dual-phase dissolve: 0→1 over first half, 1→0 over second half; total wall = duration.
test "dissolve dual-phase veil out then in" {
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let ir = @script.compile_to_ir(src, file="dissolve.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.tick(None_, dt=0.0)
  ignore(
    @std_commands.standard_registry().call("trans.dissolve", eng.stage, [
      Float(1.0),
    ]),
  )
  assert_eq(eng.stage.dissolve_phase, 1)
  assert_eq(eng.stage.overlay_opacity, 0.0)
  assert_eq(eng.stage.fade_remaining, 1.0)
  // Mid Out (0.25 of 0.5 half) → ~0.5 opacity, still Out
  eng.tick(None_, dt=0.25)
  assert_eq(eng.stage.dissolve_phase, 1)
  assert_true(eng.stage.overlay_opacity > 0.45)
  assert_true(eng.stage.overlay_opacity < 0.55)
  assert_true(eng.stage.fade_remaining > 0.7)
  assert_true(eng.stage.fade_remaining < 0.8)
  // End of Out half → near opaque; phase may flip to In on exact boundary
  eng.tick(None_, dt=0.25)
  assert_true(eng.stage.overlay_opacity > 0.9)
  assert_true(eng.stage.dissolve_phase == 1 || eng.stage.dissolve_phase == 2)
  // Mid In (another 0.25) → ~0.5 opacity, phase In
  eng.tick(None_, dt=0.25)
  assert_eq(eng.stage.dissolve_phase, 2)
  assert_true(eng.stage.overlay_opacity > 0.45)
  assert_true(eng.stage.overlay_opacity < 0.55)
  // Finish → clear
  eng.tick(None_, dt=0.25)
  assert_eq(eng.stage.dissolve_phase, 0)
  assert_eq(eng.stage.overlay_opacity, 0.0)
  assert_eq(eng.stage.fade_remaining, 0.0)
}

///|
/// Presentation clock: dissolve advances during timed wait; skip_held does not snap it.
test "dissolve advances during wait; skip does not snap" {
  let src =
    #|- scene "s"
    #|@flow.wait 1.0
    #|
  let ir = @script.compile_to_ir(src, file="dissolve_wait.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.tick(None_, dt=0.0)
  assert_true(eng.stage.wait_remaining > 0.0)
  ignore(
    @std_commands.standard_registry().call("trans.dissolve", eng.stage, [
      Float(1.0),
    ]),
  )
  // During wait, dissolve still ticks on presentation clock.
  eng.tick(None_, dt=0.25)
  assert_true(eng.stage.wait_remaining > 0.0)
  assert_true(eng.stage.overlay_opacity > 0.45)
  assert_true(eng.stage.overlay_opacity < 0.55)
  assert_eq(eng.stage.dissolve_phase, 1)
  // skip_held with dt=0 must not snap dissolve (same as fade).
  let op_before = eng.stage.overlay_opacity
  let phase_before = eng.stage.dissolve_phase
  let rem_before = eng.stage.fade_remaining
  eng.tick(None_, skip_held=true, dt=0.0)
  assert_eq(eng.stage.overlay_opacity, op_before)
  assert_eq(eng.stage.dissolve_phase, phase_before)
  assert_eq(eng.stage.fade_remaining, rem_before)
}

///|
test "toggle auto synthesizes advance on yield" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="auto.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  guard eng.stage.text is Some(t0) else { fail("first") }
  assert_eq(t0.full_text, "Hi")
  // Complete typewriter (text.end no longer force-completes).
  eng.tick(Advance)
  guard eng.stage.text is Some(t_done) else { fail("complete") }
  assert_true(t_done.complete)
  eng.tick(ToggleAuto)
  assert_true(eng.auto)
  assert_true(eng.ui.prefs.auto_mode)
  // auto + None_ while Yield → Advance to next line
  eng.tick(None_)
  guard eng.stage.text is Some(t1) else { fail("second") }
  assert_eq(t1.full_text, "There")
}

///|
test "playing ToggleAuto syncs prefs.auto_mode" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|
  let ir = @script.compile_to_ir(src, file="auto_prefs.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  assert_true(!eng.auto)
  assert_true(!eng.ui.prefs.auto_mode)
  eng.tick(ToggleAuto)
  assert_true(eng.auto)
  assert_true(eng.ui.prefs.auto_mode)
  eng.tick(ToggleAuto)
  assert_true(!eng.auto)
  assert_true(!eng.ui.prefs.auto_mode)
}

///|
test "typewriter reveals chars over ticks without complete_on_end" {
  let src =
    #|- scene "s"
    #|y:Hello
    #|
  let ir = @script.compile_to_ir(src, file="tw.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  // dt=0: run to Yield but do not reveal
  eng.tick(None_, dt=0.0)
  guard eng.stage.text is Some(t0) else { fail("text") }
  assert_eq(t0.full_text, "Hello")
  assert_true(!t0.complete)
  assert_eq(t0.visible_chars, 0)
  // One frame at 1/40s → ~1 char (engine floors to at least 1 when dt>0)
  eng.tick(None_, dt=0.025)
  guard eng.stage.text is Some(t1) else { fail("tick1") }
  assert_true(t1.visible_chars >= 1)
  assert_true(t1.visible_chars < t1.full_text.length() || t1.complete)
  // Enough ticks to finish
  for _ in 0..<20 {
    eng.tick(None_, dt=0.05)
  }
  guard eng.stage.text is Some(t2) else { fail("done") }
  assert_true(t2.complete)
  assert_eq(t2.visible_chars, t2.full_text.length())
}

///|
test "completed dialogue line is recorded in backlog" {
  let src =
    #|- scene "s"
    #|y:Hello
    #|
  let ir = @script.compile_to_ir(src, file="bl.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_, dt=0.0)
  // Incomplete typewriter: complete via Advance
  eng.tick(Advance)
  guard eng.stage.text is Some(t) else { fail("text") }
  assert_true(t.complete)
  assert_true(eng.backlog.len() >= 1)
  assert_eq(eng.backlog.get(0).text, "Hello")
}

///|
test "OpenBacklog pushes modal name backlog" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|
  let ir = @script.compile_to_ir(src, file="bl_open.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s", app=app_backlog_close())
  eng.tick(None_, dt=0.0)
  assert_true(eng.vm.wait == Yield)
  eng.tick(OpenBacklog)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "backlog")
  assert_true(eng.ui.mode is Menu)
}

///|
test "sync_ui_bind fills backlog_lines after dialogue complete" {
  let src =
    #|- scene "s"
    #|Hero:Hello
    #|
  let ir = @script.compile_to_ir(src, file="bl_bind.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_, dt=0.0)
  eng.tick(Advance)
  eng.sync_ui_bind()
  assert_true(eng.ui.bind.backlog_lines.length() >= 1)
  assert_eq(eng.ui.bind.backlog_lines[0], "Hero: Hello")
  assert_eq(
    @runtime.TextBindSrc::BacklogLine(0).resolve(eng.ui.bind),
    "Hero: Hello",
  )
  assert_eq(@runtime.TextBindSrc::BacklogLine(99).resolve(eng.ui.bind), "")
}

///|
test "sync_ui_bind exposes up to backlog capacity lines" {
  let src =
    #|- scene "s"
    #|y:seed
    #|
  let ir = @script.compile_to_ir(src, file="bl_cap.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  for i in 0..<20 {
    eng.backlog.push(speaker=Some("H"), text="line \{i}")
  }
  eng.sync_ui_bind()
  assert_eq(eng.ui.bind.backlog_lines.length(), 20)
  assert_eq(eng.ui.bind.backlog_lines[0], "H: line 0")
  assert_eq(eng.ui.bind.backlog_lines[19], "H: line 19")
  // Still bound by store capacity (default 100), not a hard 12.
  for i in 20..<100 {
    eng.backlog.push(speaker=None, text="x\{i}")
  }
  eng.sync_ui_bind()
  assert_eq(eng.ui.bind.backlog_lines.length(), 100)
  assert_eq(eng.ui.bind.backlog_lines[0], "H: line 0")
  assert_eq(eng.ui.bind.backlog_lines[99], "x99")
}

///|
test "sync_ui_bind fills slot_labels" {
  let src =
    #|- scene "s"
    #|Hero:Hi
    #|
  let ir = @script.compile_to_ir(src, file="slot_lbl.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s", save_slots=4)
  eng.sync_ui_bind()
  assert_eq(eng.ui.bind.slot_labels.length(), 4)
  assert_eq(eng.ui.bind.slot_labels[0], "Slot 0 (empty)")
  assert_eq(
    @runtime.TextBindSrc::SlotLabel(0).resolve(eng.ui.bind),
    "Slot 0 (empty)",
  )
  // Occupied with saved_at in blob.
  let stamped =
    #|{"format_version":3,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{},"layers":[],"overlay_opacity":0,"audio":{},"wait":"Running","auto":false,"fade_to":0,"fade_remaining":0,"wait_remaining":0,"saved_at":"2026-07-10T12:00:00Z"}
  eng.set_slot_blob(1, stamped)
  // Occupied without saved_at.
  let bare =
    #|{"format_version":3,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{},"layers":[],"overlay_opacity":0,"audio":{},"wait":"Running","auto":false,"fade_to":0,"fade_remaining":0,"wait_remaining":0}
  eng.set_slot_blob(2, bare)
  eng.set_slot_blob(3, "not-json")
  eng.sync_ui_bind()
  assert_eq(eng.ui.bind.slot_labels[1], "Slot 1 · 2026-07-10T12:00:00Z")
  assert_eq(eng.ui.bind.slot_labels[2], "Slot 2 · saved")
  assert_eq(eng.ui.bind.slot_labels[3], "Slot 3 · invalid")
  assert_eq(
    @runtime.TextBindSrc::SlotLabel(1).resolve(eng.ui.bind),
    "Slot 1 · 2026-07-10T12:00:00Z",
  )
  assert_eq(
    @runtime.TextBindSrc::SlotLabel(99).resolve(eng.ui.bind),
    "Slot 99 (empty)",
  )
}

///|
test "jump_if branches Talk vs Leave to different scenes" {
  let src =
    #|- scene "s"
    #|@flow.choice "Talk" "Leave" --result act
    #|@flow.jump_if act 0 "talk"
    #|@flow.jump "leave"
    #|- scene "talk"
    #|@var.set "path" 1
    #|- scene "leave"
    #|@var.set "path" 2
    #|
  let ir = @script.compile_to_ir(src, file="branch.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.tick(None_)
  eng.tick(Select(0))
  assert_eq(eng.vm.scene, "talk")
  assert_true(eng.stage.get_var("path") == Int(1))

  let eng2 = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng2.tick(None_)
  eng2.tick(Select(1))
  assert_eq(eng2.vm.scene, "leave")
  assert_true(eng2.stage.get_var("path") == Int(2))
}

///|
test "missing scene sets last_error and halts" {
  let src =
    #|- scene "s"
    #|@flow.jump "nope"
    #|
  let ir = @script.compile_to_ir(src, file="miss.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.tick(None_)
  assert_true(eng.vm.wait == Halted)
  guard eng.vm.last_error is Some(msg) else { fail("last_error") }
  assert_true(msg.contains("nope"))
}

///|
test "layer.show bare kind keyword via script" {
  let src =
    #|- scene "s"
    #|@layer.show "bg" "bg_room" kind=background
    #|
  let ir = @script.compile_to_ir(src, file="kind.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.tick(None_, dt=0.0)
  assert_eq(eng.stage.layers.length(), 1)
  assert_true(eng.stage.layers[0].kind == Background)
}

///|
test "flow.wait duration resumes after real time" {
  let src =
    #|- scene "s"
    #|@flow.wait 0.5
    #|@var.set "done" true
    #|
  let ir = @script.compile_to_ir(src, file="wait.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.tick(None_, dt=0.0)
  // After first run should be Yield with wait_remaining ~ 0.5
  assert_true(eng.vm.wait == Yield)
  assert_true(eng.stage.wait_remaining > 0.0)
  // Advance must not skip
  eng.tick(Advance, dt=0.1)
  assert_true(eng.vm.wait == Yield)
  assert_true(eng.stage.get_var("done") == None_)
  eng.tick(None_, dt=0.5)
  assert_true(
    eng.stage.get_var("done") == Bool(true) ||
    eng.vm.wait == Halted ||
    eng.vm.wait == Running,
  )
  // After enough time, var set
  eng.tick(None_, dt=0.1)
  assert_true(eng.stage.get_var("done") == Bool(true))
}

///|
test "layer opacity tween advances on engine tick" {
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(src, file="t.yuki"),
    entry="s",
  )
  eng.stage.show_layer(id="y", layer=Character, resource="c", z=1, opacity=0.0)
  eng.stage.start_layer_tween(id="y", prop=Opacity, to=1.0, duration=1.0)
  eng.tick(None_, dt=0.5)
  assert_eq(eng.stage.layers[0].opacity, 0.5)
}

///|
/// UiApp: game_menu with Continue → return_modal.
fn app_game_menu_continue() -> @runtime.UiApp {
  let app = @runtime.UiApp::new()
  app.register_modal(
    "game_menu",
    @runtime.UiNode::VBox(x=None, y=None, children=[
      app.button("Continue", fn(c : &@runtime.Capabilities) { c.return_modal() }),
    ]),
  )
  app
}

///|
/// UiApp: backlog with Close → return_modal.
fn app_backlog_close() -> @runtime.UiApp {
  let app = @runtime.UiApp::new()
  app.register_modal(
    "backlog",
    @runtime.UiNode::VBox(x=None, y=None, children=[
      app.button("Close", fn(c : &@runtime.Capabilities) { c.return_modal() }),
    ]),
  )
  app
}

///|
/// UiApp: title with Start → start_game.
fn app_title_start() -> @runtime.UiApp {
  let app = @runtime.UiApp::new()
  app.register_modal(
    "title",
    @runtime.UiNode::VBox(x=None, y=None, children=[
      app.button("Start", fn(c : &@runtime.Capabilities) { c.start_game() }),
    ]),
  )
  app
}

///|
/// UiApp: title (Start + Settings) and settings (Back).
fn app_title_with_settings() -> @runtime.UiApp {
  let app = @runtime.UiApp::new()
  app.register_modal(
    "title",
    @runtime.UiNode::VBox(x=None, y=None, children=[
      app.button("Start", fn(c : &@runtime.Capabilities) { c.start_game() }),
      app.button("Settings", fn(c : &@runtime.Capabilities) {
        c.show_modal("settings", mode=None)
      }),
    ]),
  )
  app.register_modal(
    "settings",
    @runtime.UiNode::VBox(x=None, y=None, children=[
      app.button("Back", fn(c : &@runtime.Capabilities) { c.return_modal() }),
    ]),
  )
  app
}

///|
/// Combined title + game_menu for load-clear tests.
fn app_title_and_menu() -> @runtime.UiApp {
  let app = @runtime.UiApp::new()
  app.register_modal(
    "title",
    @runtime.UiNode::VBox(x=None, y=None, children=[
      app.button("Start", fn(c : &@runtime.Capabilities) { c.start_game() }),
    ]),
  )
  app.register_modal(
    "game_menu",
    @runtime.UiNode::VBox(x=None, y=None, children=[
      app.button("Continue", fn(c : &@runtime.Capabilities) { c.return_modal() }),
    ]),
  )
  app
}

///|
test "open menu freezes vm ip until continue" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="menu_gate.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    app=app_game_menu_continue(),
  )
  eng.tick(None_, dt=0.0)
  assert_true(eng.vm.wait == Yield)
  let ip0 = eng.vm.ip
  eng.tick(OpenMenu)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "game_menu")
  assert_true(eng.ui.mode is Menu)
  assert_eq(eng.vm.ip, ip0)
  // Narrative IP frozen while menu open (presentation clocks may still run).
  eng.tick(None_, dt=0.05)
  assert_eq(eng.vm.ip, ip0)
  assert_eq(eng.ui.stack_depth(), 1)
  // Advance activates Continue (return_modal) → back to Playing; IP still frozen.
  eng.tick(Advance)
  assert_eq(eng.ui.stack_depth(), 0)
  assert_true(eng.ui.mode is Playing)
  assert_eq(eng.vm.ip, ip0)
  assert_true(eng.vm.wait == Yield)
  // Resume narrative: complete typewriter if needed, then advance line.
  // Typewriter may already have completed under the menu (H1 presentation clocks).
  guard eng.stage.text is Some(t0) else { fail("text") }
  if !t0.complete {
    eng.tick(Advance)
    guard eng.stage.text is Some(t) else { fail("text") }
    assert_true(t.complete)
  }
  eng.tick(Advance)
  guard eng.stage.text is Some(t2) else { fail("second line") }
  assert_eq(t2.full_text, "There")
}

///|
test "boot_title then start_game enters playing" {
  let src =
    #|- scene "s"
    #|@var.set "started" true
    #|
  let ir = @script.compile_to_ir(src, file="title_boot.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
    app=app_title_start(),
  )
  eng.boot_title()
  assert_true(eng.ui.mode is Title)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "title")
  // Narrative must not run on Title.
  eng.tick(None_)
  assert_true(eng.stage.get_var("started") == None_)
  // Activate Start → start_game
  eng.tick(Advance)
  assert_true(eng.ui.mode is Playing)
  assert_eq(eng.ui.stack_depth(), 0)
  // Now Playing runs VM.
  eng.tick(None_)
  assert_true(eng.stage.get_var("started") == Bool(true))
}

///|
test "boot_title without title def stays Playing" {
  let src =
    #|- scene "s"
    #|@var.set "ran" true
    #|
  let ir = @script.compile_to_ir(src, file="no_title.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.boot_title()
  assert_true(eng.ui.mode is Playing)
  assert_eq(eng.ui.stack_depth(), 0)
  eng.tick(None_)
  assert_true(eng.stage.get_var("ran") == Bool(true))
}

///|
test "boot_title shows title modal via UiRuntime" {
  let src =
    #|- scene "entrypoint"
    #|@var.set "x" 1
    #|
  let ir = @script.compile_to_ir(src, file="t.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="entrypoint",
    director=@std_commands.standard_registry(),
    app=app_title_start(),
  )
  eng.boot_title()
  assert_true(eng.ui.mode is Title)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "title")
}

///|
test "menu open pauses narrative advance" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="menu_pause.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    app=app_game_menu_continue(),
  )
  eng.tick(None_, dt=0.0)
  eng.tick(Advance) // complete typewriter
  assert_true(eng.vm.wait == Yield)
  let ip0 = eng.vm.ip
  eng.tick(OpenMenu)
  assert_eq(eng.ui.stack_depth(), 1)
  // Advance while menu open must not consume dialogue yield.
  eng.tick(Advance)
  assert_eq(eng.ui.stack_depth(), 0)
  assert_eq(eng.vm.ip, ip0)
  guard eng.stage.text is Some(t) else { fail("text") }
  assert_eq(t.full_text, "Hi")
}

///|
test "ui.show host command opens menu and freezes ip" {
  let src =
    #|- scene "s"
    #|y:Line
    #|@ui.show "game_menu"
    #|@var.set "after" 1
    #|
  let ir = @script.compile_to_ir(src, file="ui_show.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
    app=app_game_menu_continue(),
  )
  // Reach first yield on text.
  eng.tick(None_, dt=0.0)
  eng.tick(Advance) // complete typewriter
  eng.tick(Advance) // resume → text.end path → ui.show yields
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "game_menu")
  assert_true(eng.stage.get_var("after") == None_)
  let ip_menu = eng.vm.ip
  eng.tick(None_)
  assert_eq(eng.vm.ip, ip_menu)
  eng.tick(Advance) // Continue
  assert_eq(eng.ui.stack_depth(), 0)
  // After menu, still at Yield from ui.show; Advance resumes past it.
  eng.tick(Advance)
  assert_true(eng.stage.get_var("after") == Int(1))
}

///|
/// Esc on nested Title modal (e.g. title → settings) pops one layer; root Title ignores Esc.
test "OpenMenu pops nested Title settings back to title" {
  let src =
    #|- scene "s"
    #|@var.set "started" true
    #|
  let ir = @script.compile_to_ir(src, file="title_esc.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
    app=app_title_with_settings(),
  )
  eng.boot_title()
  assert_true(eng.ui.mode is Title)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "title")
  // Root Title: Esc is ignored.
  eng.tick(OpenMenu)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "title")
  assert_true(eng.ui.mode is Title)
  // Focus Settings (index 1) and open it.
  eng.tick(MenuDown)
  eng.tick(Advance)
  assert_eq(eng.ui.stack_depth(), 2)
  assert_eq(eng.ui.stack[1].name, "settings")
  assert_true(eng.ui.mode is Title)
  // Esc pops settings → back to [title].
  eng.tick(OpenMenu)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "title")
  assert_true(eng.ui.mode is Title)
}

///|
/// Successful load clears residual modal stack and forces Playing.
test "load clears screen stack to Playing" {
  let src =
    #|- scene "s"
    #|y:Hello
    #|
  let ir = @script.compile_to_ir(src, file="load_clear.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
    app=app_title_and_menu(),
  )
  eng.tick(None_, dt=0.0)
  let blob = eng.save()
  // Leave residual UI open (title + menu would both clear).
  eng.boot_title()
  eng.ui.show_modal("game_menu")
  assert_true(eng.ui.stack_depth() >= 1)
  assert_true(!(eng.ui.mode is Playing))
  eng.load(blob)
  assert_eq(eng.ui.stack_depth(), 0)
  assert_true(eng.ui.mode is Playing)
}

///|
test "skip_held completes typewriter then advances yield" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="skip_held.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_, dt=0.0)
  guard eng.stage.text is Some(t0) else { fail("first line") }
  assert_eq(t0.full_text, "Hi")
  assert_true(!t0.complete)
  // Hold skip: complete typewriter; stay on the same Yield this frame.
  eng.tick(None_, skip_held=true, dt=0.0)
  guard eng.stage.text is Some(t1) else { fail("completed") }
  assert_eq(t1.full_text, "Hi")
  assert_true(t1.complete)
  assert_true(eng.vm.wait == Yield)
  // Next frame hold skip: advance past yield to the next line.
  eng.tick(None_, skip_held=true, dt=0.0)
  guard eng.stage.text is Some(t2) else { fail("second line") }
  assert_eq(t2.full_text, "There")
}

///|
test "skip_held does not skip timed wait" {
  let src =
    #|- scene "s"
    #|@flow.wait 0.5
    #|@var.set "done" true
    #|
  let ir = @script.compile_to_ir(src, file="skip_wait.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.tick(None_, dt=0.0)
  assert_true(eng.vm.wait == Yield)
  assert_true(eng.stage.wait_remaining > 0.0)
  let ip0 = eng.vm.ip
  eng.tick(None_, skip_held=true, dt=0.0)
  assert_eq(eng.vm.ip, ip0)
  assert_true(eng.stage.wait_remaining > 0.0)
  assert_true(eng.stage.get_var("done") == None_)
}

///|
test "skip_held does not auto-select choices" {
  let src =
    #|- scene "s"
    #|@flow.choice "Yes" "No" --result c
    #|
  let ir = @script.compile_to_ir(src, file="skip_choice.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  assert_true(eng.vm.wait == Choose)
  eng.tick(None_, skip_held=true)
  assert_true(eng.vm.wait == Choose)
  guard eng.stage.choices is Some(ch) else { fail("choices remain") }
  assert_eq(ch.options.length(), 2)
  assert_true(eng.stage.get_var("c") == None_)
}

///|
/// Mid-burst `@ui.show` must stop hold-skip before later narrative (var.set).
/// Mirrors `ui.show host command opens menu and freezes ip` under skip_held.
test "skip_held stops on pending ui.show before later var" {
  let src =
    #|- scene "s"
    #|y:Line
    #|@ui.show "game_menu"
    #|@var.set "after" 1
    #|
  let ir = @script.compile_to_ir(src, file="skip_ui_show.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
    app=app_game_menu_continue(),
  )
  eng.tick(None_, dt=0.0)
  // Complete typewriter on first hold; stay on dialogue Yield.
  eng.tick(None_, skip_held=true, dt=0.0)
  guard eng.stage.text is Some(t) else { fail("text") }
  assert_true(t.complete)
  assert_true(eng.vm.wait == Yield)
  // Advance past dialogue; must stop at @ui.show and not set `after`.
  eng.tick(None_, skip_held=true, dt=0.0)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "game_menu")
  assert_true(eng.stage.get_var("after") == None_)
  assert_true(eng.stage.ui_ops.is_empty())
}

///|
/// One skip_held frame advances at most `skip_burst_max` (8) pure Yields.
test "skip_held burst max is 8 yields per tick" {
  let src =
    #|- scene "s"
    #|@flow.yield
    #|@flow.yield
    #|@flow.yield
    #|@flow.yield
    #|@flow.yield
    #|@flow.yield
    #|@flow.yield
    #|@flow.yield
    #|@flow.yield
    #|@var.set "past9" 1
    #|
  let ir = @script.compile_to_ir(src, file="skip_burst.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  // Reach first pure yield.
  eng.tick(None_, dt=0.0)
  assert_true(eng.vm.wait == Yield)
  assert_true(eng.stage.get_var("past9") == None_)
  // One hold-skip frame: ≤8 yield advances; 9th yield (and var) not yet.
  eng.tick(None_, skip_held=true, dt=0.0)
  assert_true(eng.stage.get_var("past9") == None_)
  assert_true(eng.vm.wait == Yield)
}

///|
/// First save on empty slot writes immediately; second on occupied opens confirm.
test "save_slot occupied opens confirm without overwriting" {
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let ir = @script.compile_to_ir(src, file="confirm_save.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.stage.set_var("marker", Int(1))
  let caps : &@runtime.Capabilities = eng
  caps.save_slot(0)
  assert_true(eng.pending_confirm is None)
  guard eng.get_slot_blob(0) is Some(first) else { fail("first save") }
  let g1 = @runtime.parse_save_game(first)
  assert_true(g1.vars.get("marker") == Some(Int(1)))
  // Mutate stage; re-save must open confirm and leave first blob intact.
  eng.stage.set_var("marker", Int(2))
  caps.save_slot(0)
  assert_true(eng.pending_confirm == Some(OverwriteSave(0)))
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "confirm")
  guard eng.get_slot_blob(0) is Some(still) else { fail("still first") }
  let g2 = @runtime.parse_save_game(still)
  assert_true(g2.vars.get("marker") == Some(Int(1)))
}

///|
/// Menu-triggered loads must surface runtime validation failures without
/// mutating the active playthrough or closing the load screen.
test "load_slot records semantic failure and preserves active state" {
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let ir = @script.compile_to_ir(src, file="menu_load_failure.yuki")
  let app = @runtime.UiApp::new()
  app.register_modal("load", @runtime.UiNode::VBox(x=None, y=None, children=[]))
  let foreign = @runtime.Engine::from_ir(ir, entry="s", module_id="foreign")
  let eng = @runtime.Engine::from_ir(ir, entry="s", module_id="active", app~)
  eng.tick(None_)
  eng.stage.set_var("keep", Int(7))
  eng.stage.overlay_opacity = 0.42
  eng.ui.show_modal("load")
  let scene_before = eng.vm.scene
  let ip_before = eng.vm.ip
  let wait_before = eng.vm.wait
  let stack_depth_before = eng.ui.stack_depth()
  eng.set_slot_blob(0, foreign.save())
  let caps : &@runtime.Capabilities = eng
  caps.load_slot(0)
  assert_eq(eng.slot_load_error_slot(), 0)
  assert_true(eng.consume_slot_load_error().contains("module_id mismatch"))
  assert_eq(eng.slot_load_error_slot(), -1)
  assert_eq(eng.consume_slot_load_error(), "")
  assert_eq(eng.vm.scene, scene_before)
  assert_eq(eng.vm.ip, ip_before)
  assert_true(eng.vm.wait == wait_before)
  assert_true(eng.stage.get_var("keep") == Int(7))
  assert_eq(eng.stage.overlay_opacity, 0.42)
  assert_eq(eng.ui.stack_depth(), stack_depth_before)
  assert_eq(eng.ui.stack[0].name, "load")

  let base = @runtime.parse_save_game(eng.save())
  let unknown = { ..base, scene: "missing" }.to_json().stringify()
  eng.set_slot_blob(1, unknown)
  caps.load_slot(1)
  assert_eq(eng.slot_load_error_slot(), 1)
  assert_true(eng.consume_slot_load_error().contains("unknown scene"))

  let stale = { ..base, ip: 999 }.to_json().stringify()
  eng.set_slot_blob(2, stale)
  caps.load_slot(2)
  assert_eq(eng.slot_load_error_slot(), 2)
  assert_true(
    eng.consume_slot_load_error().contains("instruction pointer 999 is invalid"),
  )

  let inconsistent = {
      ..base,
      wait: Choose,
      choices: None,
      choose_result_var: None,
    }
    .to_json()
    .stringify()
  eng.set_slot_blob(3, inconsistent)
  caps.load_slot(3)
  assert_eq(eng.slot_load_error_slot(), 3)
  assert_true(
    eng.consume_slot_load_error().contains("invalid save continuation"),
  )

  let unsupported = { ..base, format_version: 99 }.to_json().stringify()
  eng.set_slot_blob(4, unsupported)
  caps.load_slot(4)
  assert_eq(eng.slot_load_error_slot(), 4)
  assert_true(
    eng.consume_slot_load_error().contains("unsupported save format_version"),
  )
}

///|
test "successful load_slot clears stale failure and consumes no diagnostic" {
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let ir = @script.compile_to_ir(src, file="menu_load_recovery.yuki")
  let foreign = @runtime.Engine::from_ir(ir, entry="s", module_id="foreign")
  let eng = @runtime.Engine::from_ir(ir, entry="s", module_id="active")
  eng.set_slot_blob(0, foreign.save())
  let caps : &@runtime.Capabilities = eng
  caps.load_slot(0)
  assert_eq(eng.slot_load_error_slot(), 0)
  eng.set_slot_blob(0, eng.save())
  caps.load_slot(0)
  assert_eq(eng.slot_load_error_slot(), -1)
  assert_eq(eng.consume_slot_load_error(), "")
  assert_eq(eng.ui.stack_depth(), 0)
  assert_true(eng.ui.mode is Playing)
}

///|
test "confirm_yes overwrites save" {
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let ir = @script.compile_to_ir(src, file="confirm_yes.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.stage.set_var("marker", Int(1))
  let caps : &@runtime.Capabilities = eng
  caps.save_slot(0)
  eng.stage.set_var("marker", Int(2))
  caps.save_slot(0)
  assert_true(eng.pending_confirm == Some(OverwriteSave(0)))
  caps.confirm_yes()
  assert_true(eng.pending_confirm is None)
  assert_eq(eng.ui.stack_depth(), 0)
  guard eng.get_slot_blob(0) is Some(blob) else { fail("overwritten") }
  let g = @runtime.parse_save_game(blob)
  assert_true(g.vars.get("marker") == Some(Int(2)))
}

///|
test "confirm_no cancels" {
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let ir = @script.compile_to_ir(src, file="confirm_no.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.stage.set_var("marker", Int(1))
  let caps : &@runtime.Capabilities = eng
  caps.save_slot(0)
  eng.stage.set_var("marker", Int(2))
  caps.save_slot(0)
  assert_true(eng.pending_confirm == Some(OverwriteSave(0)))
  caps.confirm_no()
  assert_true(eng.pending_confirm is None)
  assert_eq(eng.ui.stack_depth(), 0)
  guard eng.get_slot_blob(0) is Some(blob) else { fail("kept") }
  let g = @runtime.parse_save_game(blob)
  assert_true(g.vars.get("marker") == Some(Int(1)))
}

///|
/// Default focus on confirm is No (index 0); Advance activates cancel path.
/// No is registered before Yes so focus 0 is the safe-cancel contract.
test "confirm default focus is No; Advance cancels overwrite" {
  let app = @runtime.UiApp::new()
  let no_id = app.alloc_action(fn(c : &@runtime.Capabilities) { c.confirm_no() })
  let yes_id = app.alloc_action(fn(c : &@runtime.Capabilities) {
    c.confirm_yes()
  })
  app.register_modal(
    "confirm",
    @runtime.UiNode::VBox(x=Some(0.0), y=Some(0.0), children=[
      @runtime.UiNode::Button(
        label="No",
        action_id=no_id,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::Button(
        label="Yes",
        action_id=yes_id,
        visible=@runtime.VisiblePred::Always,
      ),
    ]),
  )
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let ir = @script.compile_to_ir(src, file="confirm_focus.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s", app~)
  eng.stage.set_var("marker", Int(1))
  let caps : &@runtime.Capabilities = eng
  caps.save_slot(0)
  eng.stage.set_var("marker", Int(2))
  caps.save_slot(0)
  assert_true(eng.pending_confirm == Some(OverwriteSave(0)))
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "confirm")
  assert_eq(eng.ui.stack[0].focus, 0)
  // Activate focused button without MenuDown → confirm_no.
  eng.tick(Advance)
  assert_true(eng.pending_confirm is None)
  assert_eq(eng.ui.stack_depth(), 0)
  guard eng.get_slot_blob(0) is Some(blob) else { fail("kept") }
  let g = @runtime.parse_save_game(blob)
  assert_true(g.vars.get("marker") == Some(Int(1)))
}

///|
/// Esc on overwrite confirm must clear pending_confirm (same as confirm_no).
test "OpenMenu on confirm clears pending without overwrite" {
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let ir = @script.compile_to_ir(src, file="confirm_esc.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.stage.set_var("marker", Int(1))
  let caps : &@runtime.Capabilities = eng
  caps.save_slot(0)
  eng.stage.set_var("marker", Int(2))
  caps.save_slot(0)
  assert_true(eng.pending_confirm == Some(OverwriteSave(0)))
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "confirm")
  eng.tick(OpenMenu)
  assert_true(eng.pending_confirm is None)
  assert_eq(eng.ui.stack_depth(), 0)
  guard eng.get_slot_blob(0) is Some(blob) else { fail("kept") }
  let g = @runtime.parse_save_game(blob)
  assert_true(g.vars.get("marker") == Some(Int(1)))
}

///|
test "request_quit_to_title requires confirm_yes" {
  let app = @runtime.UiApp::new()
  app.register_modal(
    "title",
    @runtime.UiNode::Text(
      src=@runtime.TextBindSrc::Literal("Title"),
      x=0.0,
      y=0.0,
      font_size=24.0,
      visible=@runtime.VisiblePred::Always,
    ),
  )
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let ir = @script.compile_to_ir(src, file="confirm_quit.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s", app~)
  eng.ui.mode = Playing
  let caps : &@runtime.Capabilities = eng
  caps.request_quit_to_title()
  assert_true(eng.pending_confirm == Some(QuitToTitle))
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "confirm")
  assert_true(!(eng.ui.mode is Title))
  // No: cancel, still not title.
  caps.confirm_no()
  assert_true(eng.pending_confirm is None)
  assert_eq(eng.ui.stack_depth(), 0)
  assert_true(!(eng.ui.mode is Title))
  // Yes: tear down to title.
  caps.request_quit_to_title()
  caps.confirm_yes()
  assert_true(eng.pending_confirm is None)
  assert_true(eng.ui.mode is Title)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "title")
}

///|
/// H2: quit_to_title hard-stops global mixer BGM (session boundary).
test "H2 quit_to_title clears global mixer bgm" {
  @audio.reset_global_mixer()
  let q = @audio.QueueBackend::new()
  @audio.install_mixer(@audio.Mixer::with_backend((q : &@audio.AudioBackend)))
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(src, file="h2.yuki"),
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
  assert_true(@audio.global_mixer().se is None)
  assert_true(@audio.global_mixer().bgm_fade_to is None)
  let mut saw_stop = false
  for i in 0..<q.len() {
    if q.get(i) is Some(@audio.StopBgm) {
      saw_stop = true
    }
  }
  assert_true(saw_stop)
  @audio.reset_global_mixer()
}

///|
/// Pref volume mutations must multiply into global mixer output gains.
test "set_pref volume updates global mixer gains" {
  @audio.reset_global_mixer()
  let q = @audio.QueueBackend::new()
  @audio.install_mixer(@audio.Mixer::with_backend((q : &@audio.AudioBackend)))
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let ir = @script.compile_to_ir(src, file="t.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  // set_pref_f is on Capabilities; pub impl on Engine (see engine.mbt).
  let caps : &@runtime.Capabilities = eng
  caps.set_pref_f("master_volume", 0.5)
  caps.set_pref_f("bgm_volume", 0.5)
  @audio.global_mixer().play_bgm("x", volume=1.0)
  guard q.get(0) is Some(@audio.PlayBgm(volume~, ..)) else { fail("PlayBgm") }
  // 1.0 * 0.5 * 0.5 = 0.25
  assert_true(volume > 0.24 && volume < 0.26)
  @audio.reset_global_mixer()
}

///|
/// Simple HUD with ChoiceList at known geometry (mirrors std_ui defaults).
fn app_hud_choices() -> @runtime.UiApp {
  let app = @runtime.UiApp::new()
  app.set_hud(
    @runtime.UiNode::ChoiceList(
      x=80.0,
      y=556.0,
      w=1760.0,
      line_h=48.0,
      visible=@runtime.VisiblePred::HasChoices,
    ),
  )
  app
}

///|
/// Pointer miss on Playing dialogue: first down completes typewriter (Advance parity).
test "pointer miss advances dialogue when Playing" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="ptr_miss.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_, dt=0.0)
  assert_true(eng.vm.wait == Yield)
  guard eng.stage.text is Some(t0) else { fail("text") }
  assert_eq(t0.full_text, "Hi")
  assert_false(t0.complete)
  eng.sync_ui_bind()
  // Miss empty HUD (no choices / no focusables).
  let kind = eng.pointer_event(50.0, 50.0, phase=1)
  assert_eq(kind, 0)
  guard eng.stage.text is Some(t1) else { fail("after complete") }
  assert_true(t1.complete)
  assert_true(eng.vm.wait == Yield)
  // Second miss advances to next line (run_until_wait).
  ignore(eng.pointer_event(50.0, 50.0, phase=1))
  guard eng.stage.text is Some(t2) else { fail("second line") }
  assert_eq(t2.full_text, "There")
}

///|
/// Timed wait gate: pointer down must not Advance while wait_remaining > 0.
test "pointer down ignored while wait_remaining" {
  let src =
    #|- scene "s"
    #|y:Wait
    #|y:Next
    #|
  let ir = @script.compile_to_ir(src, file="ptr_wait.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_, dt=0.0)
  eng.tick(Advance) // complete typewriter
  guard eng.stage.text is Some(t0) else { fail("text") }
  assert_true(t0.complete)
  assert_eq(t0.full_text, "Wait")
  eng.stage.wait_remaining = 1.0
  eng.sync_ui_bind()
  ignore(eng.pointer_event(100.0, 100.0, phase=1))
  assert_eq(eng.stage.wait_remaining, 1.0)
  assert_true(eng.vm.wait == Yield)
  guard eng.stage.text is Some(t1) else { fail("unchanged") }
  assert_eq(t1.full_text, "Wait")
  assert_true(t1.complete)
}

///|
/// Pointer down on a choice row confirms that index (Choose + HUD hit).
test "pointer hits choice while Choose" {
  let src =
    #|- scene "s"
    #|@flow.choice "Yes" "No" --result c
    #|
  let ir = @script.compile_to_ir(src, file="ptr_choice.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s", app=app_hud_choices())
  eng.tick(None_, dt=0.0)
  assert_true(eng.vm.wait == Choose)
  eng.sync_ui_bind()
  // Second row: y = 556 + 1*48 = 604; hit center of row (h = line_h - 8).
  let kind = eng.pointer_event(100.0, 604.0 + 10.0, phase=1)
  assert_eq(kind, 2)
  assert_true(eng.stage.get_var("c") == Int(1))
  assert_true(eng.stage.choices is None)
}

///|
/// phase=0 move updates hover; phase=3 leave clears hover.
test "pointer move and leave update hover_kind" {
  let src =
    #|- scene "s"
    #|@flow.choice "A" "B" --result c
    #|
  let ir = @script.compile_to_ir(src, file="ptr_hover.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s", app=app_hud_choices())
  eng.tick(None_, dt=0.0)
  eng.sync_ui_bind()
  let k0 = eng.pointer_event(100.0, 556.0 + 10.0, phase=0)
  assert_eq(k0, 2)
  assert_eq(eng.ui.hover_kind(), 2)
  let k1 = eng.pointer_event(0.0, 0.0, phase=3)
  assert_eq(k1, 0)
  assert_eq(eng.ui.hover_kind(), 0)
}

///|
/// phase=2 is pointer-up: ends scroll drag and must not Advance.
test "pointer phase 2 ends scroll drag without Advance" {
  let app = @runtime.UiApp::new()
  let lines : Array[@runtime.UiNode] = []
  for i in 0..<5 {
    lines.push(
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Literal("L\{i}"),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=@runtime.VisiblePred::Always,
      ),
    )
  }
  app.register_modal(
    "sv",
    @runtime.UiNode::ScrollView(x=100.0, y=100.0, w=400.0, h=200.0, children=[
      @runtime.UiNode::VBox(x=None, y=None, children=lines),
    ]),
  )
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="ptr_up.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s", app~)
  eng.tick(None_, dt=0.0)
  assert_true(eng.vm.wait == Yield)
  guard eng.stage.text is Some(t0) else { fail("text") }
  assert_eq(t0.full_text, "Hi")
  assert_false(t0.complete)
  // Open ScrollView modal (Playing → Menu); measure layout
  eng.ui.show_modal("sv")
  eng.sync_ui_bind()
  ignore(
    eng.ui.paint_modal(
      canvas_w=1920.0,
      canvas_h=1080.0,
      bind=@runtime.UiBindCtx::empty(),
    ),
  )
  assert_true(eng.ui.scroll_max() > 50.0)
  eng.ui.scroll_y = 50.0
  // phase 1: down on content → Content drag
  ignore(eng.pointer_event(150.0, 150.0, phase=1))
  // phase 0: drag down → scroll_y decreases
  ignore(eng.pointer_event(150.0, 170.0, phase=0))
  assert_true(eng.ui.scroll_y > 29.9 && eng.ui.scroll_y < 30.1)
  // phase 2: up ends drag; no Advance (modal active, typewriter still incomplete)
  ignore(eng.pointer_event(150.0, 170.0, phase=2))
  let sy = eng.ui.scroll_y
  ignore(eng.pointer_event(150.0, 220.0, phase=0))
  assert_eq(eng.ui.scroll_y, sy)
  guard eng.stage.text is Some(t1) else { fail("text after up") }
  assert_false(t1.complete)
  assert_eq(t1.full_text, "Hi")
  assert_true(eng.vm.wait == Yield)
}

///|
/// Unknown phase (not 0/1/2/3) must not activate UI or Advance; only hover update.
test "pointer unknown phase is not down" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="ptr_phase.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_, dt=0.0)
  assert_true(eng.vm.wait == Yield)
  guard eng.stage.text is Some(t0) else { fail("text") }
  assert_eq(t0.full_text, "Hi")
  assert_false(t0.complete)
  eng.sync_ui_bind()
  // phase=4 (not 0/1/2/3) must not complete typewriter / Advance.
  ignore(eng.pointer_event(50.0, 50.0, phase=4))
  guard eng.stage.text is Some(t1) else { fail("unchanged") }
  assert_false(t1.complete)
  assert_eq(t1.full_text, "Hi")
  assert_true(eng.vm.wait == Yield)
}

///|
/// UiApp: backlog ScrollView (tall content) + Close outside viewport.
fn app_backlog_scroll() -> @runtime.UiApp {
  let app = @runtime.UiApp::new()
  let lines : Array[@runtime.UiNode] = []
  for i in 0..<8 {
    lines.push(
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Literal("L\{i}"),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=@runtime.VisiblePred::Always,
      ),
    )
  }
  app.register_modal(
    "backlog",
    @runtime.UiNode::Fixed(x=0.0, y=0.0, w=Some(1920.0), h=Some(1080.0), children=[
      @runtime.UiNode::ScrollView(x=100.0, y=100.0, w=400.0, h=200.0, children=[
        @runtime.UiNode::VBox(x=None, y=None, children=lines),
      ]),
      app.button("Close", fn(c : &@runtime.Capabilities) { c.return_modal() }),
    ]),
  )
  app
}

///|
/// Wheel while backlog is open must scroll (or no-op) but never Advance narrative.
test "wheel on backlog does not Advance narrative" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="wheel_bl.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s", app=app_backlog_scroll())
  eng.tick(None_, dt=0.0)
  assert_true(eng.vm.wait == Yield)
  guard eng.stage.text is Some(t0) else { fail("text") }
  assert_eq(t0.full_text, "Hi")
  assert_false(t0.complete)
  eng.tick(OpenBacklog)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "backlog")
  // Wheel over ScrollView viewport; modal gate ⇒ no typewriter complete / Advance.
  ignore(eng.wheel_event(150.0, 120.0, 40.0))
  guard eng.stage.text is Some(t1) else { fail("after wheel") }
  assert_false(t1.complete)
  assert_eq(t1.full_text, "Hi")
  assert_true(eng.vm.wait == Yield)
  assert_eq(eng.ui.stack_depth(), 1)
}

///|
/// MenuUp on backlog always scrolls toward older content (even with Close focused).
test "MenuUp on backlog decreases scroll_y toward older" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|
  let ir = @script.compile_to_ir(src, file="menu_scroll.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s", app=app_backlog_scroll())
  eng.tick(None_, dt=0.0)
  eng.tick(OpenBacklog)
  assert_eq(eng.ui.stack[0].name, "backlog")
  // Focus stays on Close (only focusable); ↑ must still scroll, not focus-wrap.
  assert_eq(eng.ui.stack[0].focus, 0)
  eng.sync_ui_bind()
  eng.ui.ensure_scroll_metrics(eng.ui.bind)
  assert_true(eng.ui.scroll_max() > 0.0)
  // show_modal("backlog") pins to newest (bottom) after layout.
  assert_true(eng.ui.scroll_y >= eng.ui.scroll_max() - 0.01)
  let before = eng.ui.scroll_y
  eng.tick(MenuUp)
  assert_eq(eng.ui.stack[0].focus, 0)
  assert_true(eng.ui.scroll_y < before)
  let expected = before - @runtime.ui_scroll_line_h
  assert_true(
    eng.ui.scroll_y > expected - 0.1 && eng.ui.scroll_y < expected + 0.1,
  )
}

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
    app=app_game_menu_continue(),
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
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(src, file="h1-fade.yuki"),
    entry="s",
    director=@std_commands.standard_registry(),
    app=app_game_menu_continue(),
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
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(src, file="h1-tween.yuki"),
    entry="s",
    app=app_game_menu_continue(),
  )
  eng.tick(None_, dt=0.0)
  // Same layer setup as "layer opacity tween advances on engine tick".
  eng.stage.show_layer(id="y", layer=Character, resource="c", z=1, opacity=0.0)
  eng.stage.start_layer_tween(id="y", prop=Opacity, to=1.0, duration=1.0)
  eng.tick(OpenMenu, dt=0.0)
  eng.tick(None_, dt=0.5)
  assert_eq(eng.stage.layers[0].opacity, 0.5)
}

///|
test "H1 skip_held does not burst under modal" {
  let src =
    #|- scene "s"
    #|y:line one
    #|y:line two
    #|
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(src, file="h1-skip.yuki"),
    entry="s",
    app=app_game_menu_continue(),
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
