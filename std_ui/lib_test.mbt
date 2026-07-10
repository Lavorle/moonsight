///|
test "register sets hud and four modals" {
  let app = @runtime.UiApp::new()
  register(app)
  assert_true(app.hud is Some(_))
  assert_true(app.modals.contains("title"))
  assert_true(app.modals.contains("game_menu"))
  assert_true(app.modals.contains("save_load"))
  assert_true(app.modals.contains("settings"))
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
      assert_eq(op.x, 48.0)
      assert_eq(op.y, 756.0)
      assert_eq(op.w, 1824.0)
      assert_eq(op.h, 324.0)
    }
    if op.resource == "ui.nameplate" {
      has_nameplate = true
    }
  }
  assert_true(has_box)
  assert_true(has_nameplate)
}
