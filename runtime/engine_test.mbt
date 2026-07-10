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
    @runtime.UiNode::VBox(
      x=None,
      y=None,
      children=[
        app.button("Continue", fn(c : &@runtime.Capabilities) { c.return_modal() }),
      ],
    ),
  )
  app
}

///|
/// UiApp: title with Start → start_game.
fn app_title_start() -> @runtime.UiApp {
  let app = @runtime.UiApp::new()
  app.register_modal(
    "title",
    @runtime.UiNode::VBox(
      x=None,
      y=None,
      children=[
        app.button("Start", fn(c : &@runtime.Capabilities) { c.start_game() }),
      ],
    ),
  )
  app
}

///|
/// UiApp: title (Start + Settings) and settings (Back).
fn app_title_with_settings() -> @runtime.UiApp {
  let app = @runtime.UiApp::new()
  app.register_modal(
    "title",
    @runtime.UiNode::VBox(
      x=None,
      y=None,
      children=[
        app.button("Start", fn(c : &@runtime.Capabilities) { c.start_game() }),
        app.button(
          "Settings",
          fn(c : &@runtime.Capabilities) { c.show_modal("settings", mode=None) },
        ),
      ],
    ),
  )
  app.register_modal(
    "settings",
    @runtime.UiNode::VBox(
      x=None,
      y=None,
      children=[
        app.button("Back", fn(c : &@runtime.Capabilities) { c.return_modal() }),
      ],
    ),
  )
  app
}

///|
/// Combined title + game_menu for load-clear tests.
fn app_title_and_menu() -> @runtime.UiApp {
  let app = @runtime.UiApp::new()
  app.register_modal(
    "title",
    @runtime.UiNode::VBox(
      x=None,
      y=None,
      children=[
        app.button("Start", fn(c : &@runtime.Capabilities) { c.start_game() }),
      ],
    ),
  )
  app.register_modal(
    "game_menu",
    @runtime.UiNode::VBox(
      x=None,
      y=None,
      children=[
        app.button("Continue", fn(c : &@runtime.Capabilities) { c.return_modal() }),
      ],
    ),
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
  let eng = @runtime.Engine::from_ir(ir, entry="s", app=app_game_menu_continue())
  eng.tick(None_, dt=0.0)
  assert_true(eng.vm.wait == Yield)
  let ip0 = eng.vm.ip
  eng.tick(OpenMenu)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "game_menu")
  assert_true(eng.ui.mode is Menu)
  assert_eq(eng.vm.ip, ip0)
  // Narrative frozen while menu open.
  eng.tick(None_, dt=0.05)
  assert_eq(eng.vm.ip, ip0)
  assert_eq(eng.ui.stack_depth(), 1)
  // Advance activates Continue (return_modal) → back to Playing; IP still frozen.
  eng.tick(Advance)
  assert_eq(eng.ui.stack_depth(), 0)
  assert_true(eng.ui.mode is Playing)
  assert_eq(eng.vm.ip, ip0)
  assert_true(eng.vm.wait == Yield)
  // Resume narrative: complete typewriter then advance line.
  eng.tick(Advance)
  guard eng.stage.text is Some(t) else { fail("text") }
  assert_true(t.complete)
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
  let eng = @runtime.Engine::from_ir(ir, entry="s", app=app_game_menu_continue())
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
