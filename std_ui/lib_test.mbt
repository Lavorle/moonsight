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
fn count_buttons(node : @runtime.UiNode, label : String) -> Int {
  match node {
    @runtime.UiNode::Button(label=l, ..) => if l == label { 1 } else { 0 }
    @runtime.UiNode::VBox(children~, ..)
    | @runtime.UiNode::HBox(children~, ..)
    | @runtime.UiNode::Fixed(children~, ..)
    | @runtime.UiNode::ScrollView(children~, ..) => {
      let mut total = 0
      for child in children {
        total = total + count_buttons(child, label)
      }
      total
    }
    _ => 0
  }
}

///|
test "save_load honors a one-slot registration" {
  let app = @runtime.UiApp::new()
  register(app, save_slots=1)
  guard app.modals.get("save_load") is Some(root) else {
    fail("save_load modal missing")
  }
  assert_eq(count_buttons(root, "Save"), 1)
  assert_eq(count_buttons(root, "Load"), 1)
  assert_eq(count_buttons(root, "Back"), 1)
  let rt = @runtime.UiRuntime::from_app(app, save_slots=1)
  rt.show_modal("save_load", mode="save")
  let bind = {
    ..@runtime.UiBindCtx::empty(),
    occupied: [false],
    modal_mode: Some("save"),
  }
  assert_eq(rt.focusables_top(bind).length(), 2)
}

///|
test "save_load honors twenty slots and scrolls the slot list" {
  let app = @runtime.UiApp::new()
  register(app, save_slots=20)
  guard app.modals.get("save_load") is Some(root) else {
    fail("save_load modal missing")
  }
  assert_eq(count_buttons(root, "Save"), 20)
  assert_eq(count_buttons(root, "Load"), 20)
  assert_eq(count_buttons(root, "Back"), 1)
  let rt = @runtime.UiRuntime::from_app(app, save_slots=20)
  rt.show_modal("save_load", mode="save")
  let occupied : Array[Bool] = []
  for _ in 0..<20 {
    occupied.push(false)
  }
  let bind = {
    ..@runtime.UiBindCtx::empty(),
    occupied,
    modal_mode: Some("save"),
  }
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind~))
  assert_true(rt.scroll_max() > 0.0)
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
test "save_load paints slot empty and filled icons" {
  let app = @runtime.UiApp::new()
  register(app)
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("save_load", mode="save")
  let bind = {
    ..@runtime.UiBindCtx::empty(),
    occupied: [false, true, false, false, false, false],
    modal_mode: Some("save"),
  }
  let ops = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind~)
  let mut empty_n = 0
  let mut filled_n = 0
  for op in ops {
    if op.resource == "ui.slot_empty" {
      empty_n = empty_n + 1
    }
    if op.resource == "ui.slot_filled" {
      filled_n = filled_n + 1
    }
  }
  // Slot 1 occupied → 5 empty icons + 1 filled icon.
  assert_eq(empty_n, 5)
  assert_eq(filled_n, 1)
  // Same occupancy icons in load mode (icons are mode-independent).
  rt.return_modal()
  rt.show_modal("save_load", mode="load")
  let bind_load = {
    ..@runtime.UiBindCtx::empty(),
    occupied: [false, true, false, false, false, false],
    modal_mode: Some("load"),
  }
  let ops_load = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=bind_load,
  )
  let mut empty_load = 0
  let mut filled_load = 0
  for op in ops_load {
    if op.resource == "ui.slot_empty" {
      empty_load = empty_load + 1
    }
    if op.resource == "ui.slot_filled" {
      filled_load = filled_load + 1
    }
  }
  assert_eq(empty_load, 5)
  assert_eq(filled_load, 1)
}

///|
test "confirm modal focuses No first" {
  let app = @runtime.UiApp::new()
  register(app)
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("confirm")
  assert_eq(rt.stack[0].name, "confirm")
  // show_modal seeds focus at 0; No is registered before Yes in build_confirm.
  assert_eq(rt.stack[0].focus, 0)
  let bind = @runtime.UiBindCtx::empty()
  let focus = rt.focusables_top(bind)
  assert_eq(focus.length(), 2)
  let ops = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind~)
  let mut found_no_focused = false
  let mut found_yes_unfocused = false
  for op in ops {
    match op.text {
      Some(t) =>
        if t == "No" {
          assert_true(op.focused)
          found_no_focused = true
        } else if t == "Yes" {
          assert_false(op.focused)
          found_yes_unfocused = true
        }
      None => ()
    }
  }
  assert_true(found_no_focused)
  assert_true(found_yes_unfocused)
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
test "std_ui backlog modal registers and uses ScrollView" {
  let app = @runtime.UiApp::new()
  register(app)
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("backlog")
  // Many preformatted lines so content height exceeds ScrollView viewport (780).
  let lines : Array[String] = []
  for i in 0..<30 {
    lines.push("line \{i}")
  }
  let bind = { ..@runtime.UiBindCtx::empty(), backlog_lines: lines }
  rt.sync_bind(bind)
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind~))
  assert_true(rt.scroll_max() > 0.0)
  // Close lives outside ScrollView and remains the only focusable.
  let focus = rt.focusables_top(bind)
  assert_eq(focus.length(), 1)
  // Few lines must not inflate content via empty BacklogLine slots (collapse).
  let few = { ..@runtime.UiBindCtx::empty(), backlog_lines: ["a", "b"] }
  rt.sync_bind(few)
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=few))
  assert_eq(rt.scroll_max(), 0.0)
}

///|
/// Spec §2.3: empty backlog shows hint copy + Close (not only History + empty SV).
test "std_ui empty backlog shows hint and Close" {
  let app = @runtime.UiApp::new()
  register(app)
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("backlog")
  let empty = @runtime.UiBindCtx::empty()
  rt.sync_bind(empty)
  let ops = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=empty)
  let mut found_hint = false
  let mut found_history = false
  for op in ops {
    match op.text {
      Some(t) => {
        if t == "No dialogue history yet." {
          found_hint = true
        }
        if t == "History" {
          found_history = true
        }
      }
      None => ()
    }
  }
  assert_true(found_history)
  assert_true(found_hint)
  // Close remains the only focusable.
  let focus = rt.focusables_top(empty)
  assert_eq(focus.length(), 1)
  assert_eq(rt.scroll_max(), 0.0)
  // With lines, empty-state hint is hidden.
  let lined = { ..@runtime.UiBindCtx::empty(), backlog_lines: ["a: hi"] }
  rt.sync_bind(lined)
  let ops2 = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=lined)
  for op in ops2 {
    match op.text {
      Some(t) => assert_false(t == "No dialogue history yet.")
      None => ()
    }
  }
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
  assert_true(
    body.length() < 5 || eng.stage.text is Some({ complete: true, .. }),
  )
  guard eng.stage.text is Some(t) else { fail("text") }
  assert_eq(body, t.full_text.unsafe_substring(start=0, end=t.visible_chars))
}
