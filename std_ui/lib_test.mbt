///|
test "register sets hud and six modals" {
  let app = @runtime.UiApp::new()
  register(app)
  assert_true(app.hud is Some(_))
  assert_true(app.modals.contains("title"))
  assert_true(app.modals.contains("game_menu"))
  assert_true(app.modals.contains("save_load"))
  assert_true(app.modals.contains("settings"))
  assert_true(app.modals.contains("confirm"))
  assert_true(app.modals.contains("backlog"))
}

///|
test "title start_game reaches playing" {
  let src =
    #|- scene "entrypoint"
    #|Hero:Hi
    #|
  let ir = @script.compile_to_ir(src, file="d.yuki")
  let app = @runtime.UiApp::new()
  register(app)
  let eng = @runtime.Engine::from_ir(ir, entry="entrypoint", app~)
  eng.boot_title()
  assert_true(eng.ui.mode is @runtime.UiMode::Title)
  assert_eq(eng.ui.stack_depth(), 1)
  assert_eq(eng.ui.stack[0].name, "title")
  // First focusable is Start (Text "MoonSight" is not focusable).
  eng.tick(@runtime.Intent::Advance)
  assert_true(eng.ui.mode is @runtime.UiMode::Playing)
  assert_eq(eng.ui.stack_depth(), 0)
}

///|
test "hud paints dialogue box when bind has text" {
  let app = @runtime.UiApp::new()
  register(app)
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.mode = @runtime.UiMode::Playing
  let bind = {
    ..@runtime.UiBindCtx::empty(),
    has_text: true,
    dialogue_name: "Hero",
    dialogue_body: "Hello",
  }
  rt.sync_bind(bind)
  let ops = rt.paint_hud(canvas_w=1920.0, canvas_h=1080.0, bind~)
  let mut has_box = false
  let mut has_nameplate = false
  for op in ops {
    if op.resource == "ui.dialogue_box" {
      has_box = true
      assert_eq(op.x, 64.0)
      assert_eq(op.y, 772.0)
      assert_eq(op.w, 1792.0)
      assert_eq(op.h, 276.0)
    }
    if op.resource == "ui.nameplate" {
      has_nameplate = true
    }
  }
  assert_true(has_box)
  assert_true(has_nameplate)
}

///|
test "load mode empty slots are not focusable" {
  let app = @runtime.UiApp::new()
  register(app)
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("save_load", mode="load")
  let bind = {
    ..@runtime.UiBindCtx::empty(),
    occupied: [false, true, false, false, false, false],
    modal_mode: Some("load"),
  }
  // Occupied slot 1 + Back only — empty load slots filtered by And(ModeIs, SlotOccupied).
  let focus = rt.focusables_top(bind)
  assert_eq(focus.length(), 2)
  // First focusable activates load_slot(1) via registered handler; Back is second.
  // Re-open with all empty → only Back remains.
  let bind_empty = {
    ..@runtime.UiBindCtx::empty(),
    occupied: [false, false, false, false, false, false],
    modal_mode: Some("load"),
  }
  let focus_empty = rt.focusables_top(bind_empty)
  assert_eq(focus_empty.length(), 1)
  // Save mode keeps all 6 slots + Back regardless of occupancy.
  rt.return_modal()
  rt.show_modal("save_load", mode="save")
  let bind_save = {
    ..@runtime.UiBindCtx::empty(),
    occupied: [false, true, false, false, false, false],
    modal_mode: Some("save"),
  }
  let focus_save = rt.focusables_top(bind_save)
  assert_eq(focus_save.length(), 7)
}

///|
test "title modal Text MoonSight paints on centered card" {
  let app = @runtime.UiApp::new()
  register(app)
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("title")
  let ops = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=@runtime.UiBindCtx::empty(),
  )
  let mut found = false
  let mut has_card = false
  for op in ops {
    if op.resource == "ui.dialogue_box" {
      has_card = true
      assert_eq(op.x, 680.0)
      assert_eq(op.w, 560.0)
    }
    match op.text {
      Some(t) =>
        if t == "MoonSight" {
          found = true
          assert_eq(op.x, 760.0)
          assert_eq(op.y, 300.0)
        }
      None => ()
    }
  }
  assert_true(found)
  assert_true(has_card)
}

///|
test "typewriter bind exposes visible prefix only" {
  let src =
    #|- scene "entrypoint"
    #|Hero:Hello
    #|
  let ir = @script.compile_to_ir(src, file="tw.yuki")
  let app = @runtime.UiApp::new()
  register(app)
  let eng = @runtime.Engine::from_ir(ir, entry="entrypoint", app~)
  eng.ui.mode = @runtime.UiMode::Playing
  // dt=0 reaches Yield without revealing chars.
  eng.tick(@runtime.Intent::None_, dt=0.0)
  eng.sync_ui_bind()
  assert_eq(eng.ui.bind.dialogue_body, "")
  assert_eq(eng.ui.bind.dialogue_name, "Hero")
  assert_true(eng.ui.bind.has_text)
  // One frame reveals at least one char into the bind body.
  eng.tick(@runtime.Intent::None_, dt=0.025)
  eng.sync_ui_bind()
  let body = eng.ui.bind.dialogue_body
  assert_true(body.length() >= 1)
  assert_true(body.length() < 5 || eng.stage.text is Some({ complete: true, .. }))
  guard eng.stage.text is Some(t) else { fail("text") }
  assert_eq(body, t.full_text.unsafe_substring(start=0, end=t.visible_chars))
}
