///|
/// Minimal `Capabilities` double for UiApp / UiRuntime tests.
struct FakeCaps {
  mut started : Bool
  mut start_game_n : Int
  slots : Array[Bool]
  mut prefs : Prefs
  mut confirmed_choice : Int?
  save_calls : Array[Int]
  load_calls : Array[Int]
  mut advance_n : Int
} derive(Debug)

///|
fn FakeCaps::new(slots~ : Array[Bool] = []) -> FakeCaps {
  {
    started: false,
    start_game_n: 0,
    slots,
    prefs: Prefs::default(),
    confirmed_choice: None,
    save_calls: [],
    load_calls: [],
    advance_n: 0,
  }
}

///|
impl Capabilities for FakeCaps with fn start_game(self) {
  self.started = true
  self.start_game_n = self.start_game_n + 1
}

///|
impl Capabilities for FakeCaps with fn quit_to_title(_self) {
  ()
}

///|
impl Capabilities for FakeCaps with fn show_modal(_self, _name, mode~) {
  ignore(mode)
}

///|
impl Capabilities for FakeCaps with fn return_modal(_self) {
  ()
}

///|
impl Capabilities for FakeCaps with fn hide_modal(_self, name~) {
  ignore(name)
}

///|
impl Capabilities for FakeCaps with fn save_slot(self, i) {
  self.save_calls.push(i)
}

///|
impl Capabilities for FakeCaps with fn load_slot(self, i) {
  self.load_calls.push(i)
}

///|
impl Capabilities for FakeCaps with fn slot_occupied(self, i) {
  if i < 0 || i >= self.slots.length() {
    false
  } else {
    self.slots[i]
  }
}

///|
impl Capabilities for FakeCaps with fn slot_label(_self, i) {
  "Slot \{i}"
}

///|
impl Capabilities for FakeCaps with fn set_pref_f(self, k, v) {
  self.prefs = self.prefs.set(k, Float(v))
}

///|
impl Capabilities for FakeCaps with fn set_pref_b(self, k, v) {
  self.prefs = self.prefs.set(k, Bool(v))
}

///|
impl Capabilities for FakeCaps with fn adjust_pref(self, k, delta) {
  self.prefs = self.prefs.adjust(k, delta)
}

///|
impl Capabilities for FakeCaps with fn confirm_choice(self, i) {
  self.confirmed_choice = Some(i)
}

///|
impl Capabilities for FakeCaps with fn advance(self) {
  self.advance_n = self.advance_n + 1
}

///|
impl Capabilities for FakeCaps with fn prefs(self) {
  self.prefs
}

///|
impl Capabilities for FakeCaps with fn confirm_yes(_self) {
  ()
}

///|
impl Capabilities for FakeCaps with fn confirm_no(_self) {
  ()
}

///|
impl Capabilities for FakeCaps with fn request_quit_to_title(_self) {
  ()
}

///|
test "ui app registers modal and hud" {
  let app = UiApp::new()
  app.set_hud(
    UiNode::Text(
      src=TextBindSrc::Literal("hud"),
      x=0.0,
      y=0.0,
      font_size=16.0,
      visible=VisiblePred::Always,
    ),
  )
  app.register_modal(
    "title",
    UiNode::VBox(
      x=Some(10.0),
      y=Some(20.0),
      children=[
        UiNode::Button(label="Start", action_id=0, visible=VisiblePred::Always),
      ],
    ),
  )
  assert_true(app.hud is Some(_))
  assert_true(app.modals.contains("title"))
}

///|
test "ui app button helper assigns action id and runs handler" {
  let app = UiApp::new()
  let mut called = false
  let node = app.button("Go", fn(_caps : &Capabilities) { called = true })
  guard node is UiNode::Button(action_id~, ..) else { fail("button") }
  let caps : &Capabilities = FakeCaps::new()
  app.invoke(action_id, caps)
  assert_true(called)
}

///|
test "button allocates monotonic action ids" {
  let app = UiApp::new()
  let a = app.alloc_action(fn(_c : &Capabilities) { () })
  let b = app.alloc_action(fn(_c : &Capabilities) { () })
  assert_true(b == a + 1)
}

///|
test "modal show return and activate start_game" {
  let app = UiApp::new()
  let start_id = app.alloc_action(fn(c : &Capabilities) { c.start_game() })
  app.register_modal(
    "title",
    UiNode::VBox(
      x=Some(0.0),
      y=Some(0.0),
      children=[
        UiNode::Button(
          label="Start",
          action_id=start_id,
          visible=VisiblePred::Always,
        ),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  let caps = FakeCaps::new()
  let c : &Capabilities = caps
  rt.show_modal("title")
  assert_eq(rt.stack_depth(), 1)
  rt.activate(c)
  assert_true(caps.started)
  rt.return_modal()
  assert_eq(rt.stack_depth(), 0)
}

///|
test "vbox layout stacks buttons vertically" {
  let app = UiApp::new()
  app.register_modal(
    "m",
    UiNode::VBox(
      x=Some(100.0),
      y=Some(200.0),
      children=[
        UiNode::Button(label="A", action_id=0, visible=VisiblePred::Always),
        UiNode::Button(label="B", action_id=1, visible=VisiblePred::Always),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("m")
  let ops = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=UiBindCtx::empty(),
  )
  // Expect two button panels with y increasing by line height (~56-64)
  assert_true(ops.length() >= 2)
  let buttons : Array[UiDrawOp] = []
  for op in ops {
    if op.resource == "ui.button" || op.resource == "ui.button_focus" {
      buttons.push(op)
    }
  }
  assert_eq(buttons.length(), 2)
  assert_eq(buttons[0].x, 100.0)
  assert_eq(buttons[0].y, 200.0)
  assert_eq(buttons[0].w, 400.0)
  assert_eq(buttons[0].h, 52.0)
  let dy = buttons[1].y - buttons[0].y
  assert_true(dy >= 56.0 && dy <= 64.0)
  // First button focused by default
  assert_true(buttons[0].focused)
  assert_eq(buttons[0].resource, "ui.button_focus")
  assert_false(buttons[1].focused)
  assert_eq(buttons[1].resource, "ui.button")
}

///|
test "focus_delta wraps and activate invokes focused button" {
  let app = UiApp::new()
  let mut a_n = 0
  let mut b_n = 0
  let a_id = app.alloc_action(fn(_c : &Capabilities) { a_n = a_n + 1 })
  let b_id = app.alloc_action(fn(_c : &Capabilities) { b_n = b_n + 1 })
  app.register_modal(
    "m",
    UiNode::VBox(
      x=Some(0.0),
      y=Some(0.0),
      children=[
        UiNode::Button(label="A", action_id=a_id, visible=VisiblePred::Always),
        UiNode::Button(label="B", action_id=b_id, visible=VisiblePred::Always),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  let caps = FakeCaps::new()
  let c : &Capabilities = caps
  rt.show_modal("m")
  rt.focus_delta(c, 1)
  rt.activate(c)
  assert_eq(a_n, 0)
  assert_eq(b_n, 1)
  rt.focus_delta(c, 1) // wrap to A
  rt.activate(c)
  assert_eq(a_n, 1)
}

///|
test "menu mode paint_modal prepends dim" {
  let app = UiApp::new()
  app.register_modal(
    "game_menu",
    UiNode::Button(label="Back", action_id=0, visible=VisiblePred::Always),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.mode = Playing
  rt.show_modal("game_menu")
  assert_true(rt.mode is Menu)
  let ops = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=UiBindCtx::empty(),
  )
  assert_true(ops.length() >= 2)
  assert_eq(ops[0].resource, "ui.menu_dim")
  assert_eq(ops[0].w, 1920.0)
  assert_eq(ops[0].h, 1080.0)
}

///|
test "title root modal has no dim; nested modal dims" {
  let app = UiApp::new()
  app.register_modal(
    "title",
    UiNode::Button(label="Start", action_id=0, visible=VisiblePred::Always),
  )
  app.register_modal(
    "settings",
    UiNode::Button(label="Back", action_id=1, visible=VisiblePred::Always),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("title")
  assert_true(rt.mode is Title)
  let ops1 = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=UiBindCtx::empty(),
  )
  assert_true(ops1.length() >= 1)
  assert_false(ops1[0].resource == "ui.menu_dim")
  rt.show_modal("settings")
  let ops2 = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=UiBindCtx::empty(),
  )
  assert_eq(ops2[0].resource, "ui.menu_dim")
}

///|
test "choice list expands and activate confirms index" {
  let app = UiApp::new()
  app.set_hud(
    UiNode::ChoiceList(
      x=100.0,
      y=400.0,
      w=500.0,
      line_h=48.0,
      visible=VisiblePred::HasChoices,
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.mode = Playing
  let bind = {
    ..UiBindCtx::empty(),
    has_choices: true,
    choice_labels: ["Yes", "No"],
  }
  rt.sync_bind(bind)
  let ops = rt.paint_hud(canvas_w=1920.0, canvas_h=1080.0, bind~)
  let mut rows = 0
  for op in ops {
    if op.resource == "ui.choice_row" ||
      op.resource == "ui.choice_row_focus" ||
      op.resource == "ui.choice_row_hover" {
      rows = rows + 1
    }
  }
  assert_eq(rows, 2)
  let caps = FakeCaps::new()
  let c : &Capabilities = caps
  // Focus second choice and activate
  rt.focus_delta(c, 1)
  rt.activate(c)
  guard caps.confirmed_choice is Some(1) else { fail("expected choice 1") }
}

///|
test "handle_pointer hits button and activates" {
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
  // Miss
  assert_false(rt.handle_pointer(c, 10.0, 10.0))
  assert_eq(n, 0)
  // Hit button rect [100,200]–[500,252]
  assert_true(rt.handle_pointer(c, 150.0, 220.0))
  assert_eq(n, 1)
}

///|
test "return_modal restores Playing when stack empties from Menu" {
  let app = UiApp::new()
  app.register_modal(
    "game_menu",
    UiNode::Button(label="Back", action_id=0, visible=VisiblePred::Always),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.mode = Playing
  rt.show_modal("game_menu")
  assert_true(rt.mode is Menu)
  rt.return_modal()
  assert_eq(rt.stack_depth(), 0)
  assert_true(rt.mode is Playing)
}

///|
test "hide_modal removes by name" {
  let app = UiApp::new()
  app.register_modal(
    "a",
    UiNode::Button(label="A", action_id=0, visible=VisiblePred::Always),
  )
  app.register_modal(
    "b",
    UiNode::Button(label="B", action_id=1, visible=VisiblePred::Always),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.mode = Playing
  rt.show_modal("a")
  rt.show_modal("b")
  assert_eq(rt.stack_depth(), 2)
  rt.hide_modal(name="a")
  assert_eq(rt.stack_depth(), 1)
  assert_eq(rt.stack[0].name, "b")
}

///|
test "slot occupied false is not focusable" {
  let app = UiApp::new()
  let mut load_n = 0
  let id0 = app.alloc_action(fn(c : &Capabilities) {
    c.load_slot(0)
    load_n = load_n + 1
  })
  let id1 = app.alloc_action(fn(c : &Capabilities) {
    c.load_slot(1)
    load_n = load_n + 1
  })
  app.register_modal(
    "save_load",
    UiNode::VBox(
      x=Some(0.0),
      y=Some(0.0),
      children=[
        UiNode::Button(
          label="Slot 0",
          action_id=id0,
          visible=VisiblePred::SlotOccupied(0),
        ),
        UiNode::Button(
          label="Slot 1",
          action_id=id1,
          visible=VisiblePred::Always,
        ),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  let caps = FakeCaps::new(slots=[false, true])
  let c : &Capabilities = caps
  rt.show_modal("save_load", mode="load")
  let bind = {
    ..UiBindCtx::empty(),
    occupied: [false, true],
    modal_mode: Some("load"),
  }
  rt.sync_bind(bind)
  // Only Slot 1 is focusable; activate should hit id1
  rt.activate(c)
  assert_eq(caps.load_calls.length(), 1)
  assert_eq(caps.load_calls[0], 1)
}

///|
test "VisiblePred And short-circuits ModeIs and SlotOccupied" {
  let bind_load_empty = {
    ..UiBindCtx::empty(),
    occupied: [false, true],
    modal_mode: Some("load"),
  }
  let pred = VisiblePred::And(
    VisiblePred::ModeIs("load"),
    VisiblePred::SlotOccupied(0),
  )
  assert_true(!pred.eval(bind_load_empty))
  let pred1 = VisiblePred::And(
    VisiblePred::ModeIs("load"),
    VisiblePred::SlotOccupied(1),
  )
  assert_true(pred1.eval(bind_load_empty))
  let bind_save = {
    ..UiBindCtx::empty(),
    occupied: [true, true],
    modal_mode: Some("save"),
  }
  assert_true(!pred1.eval(bind_save))
}

///|
test "VisiblePred Not inverts SlotOccupied" {
  let bind = {
    ..UiBindCtx::empty(),
    occupied: [false, true],
  }
  let empty0 = VisiblePred::Not(VisiblePred::SlotOccupied(0))
  let empty1 = VisiblePred::Not(VisiblePred::SlotOccupied(1))
  assert_true(empty0.eval(bind))
  assert_true(!empty1.eval(bind))
  assert_true(VisiblePred::Not(VisiblePred::Always).eval(bind) == false)
  assert_true(VisiblePred::Not(VisiblePred::Never).eval(bind))
}

///|
test "slider is focusable and MenuRight adjusts pref" {
  let app = UiApp::new()
  app.register_modal(
    "settings",
    UiNode::VBox(
      x=Some(0.0),
      y=Some(0.0),
      children=[
        UiNode::Slider(
          key="master_volume",
          x=0.0,
          y=0.0,
          w=400.0,
          h=52.0,
          visible=VisiblePred::Always,
        ),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  let caps = FakeCaps::new()
  // Start mid-range so MenuRight can increase without clamping at 1.0.
  caps.prefs = { ..Prefs::default(), master_volume: 0.5 }
  rt.prefs = caps.prefs
  let c : &Capabilities = caps
  rt.show_modal("settings")
  let bind = { ..UiBindCtx::empty(), prefs: caps.prefs }
  rt.sync_bind(bind)
  let focus = rt.focusables_top(bind)
  assert_eq(focus.length(), 1)
  guard focus[0] is UiFocusTarget::Slider(key) else {
    fail("expected Slider focusable")
  }
  assert_eq(key, "master_volume")
  // slider_delta(+1) is the MenuRight path used by tick_ui.
  rt.slider_delta(c, 1)
  // volume step is 0.1
  assert_eq(caps.prefs.master_volume, 0.6)
  // MenuLeft decreases.
  rt.slider_delta(c, -1)
  assert_eq(caps.prefs.master_volume, 0.5)
  // Activate on Slider is a no-op.
  let before = caps.prefs.master_volume
  rt.activate(c)
  assert_eq(caps.prefs.master_volume, before)
}

///|
test "slider paint fill width tracks normalized pref" {
  let app = UiApp::new()
  app.register_modal(
    "s",
    UiNode::Slider(
      key="master_volume",
      x=0.0,
      y=0.0,
      w=400.0,
      h=52.0,
      visible=VisiblePred::Always,
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("s")
  let bind = {
    ..UiBindCtx::empty(),
    prefs: { ..Prefs::default(), master_volume: 0.25 },
  }
  let ops = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind~)
  // Track (full) + fill (0.25 * 400 = 100). First focusable is focused.
  let mut fill_w : Float = -1.0
  for op in ops {
    if op.focused && op.resource == "ui.slider_fill" {
      fill_w = op.w
    }
  }
  assert_true(fill_w > 99.0 && fill_w < 101.0)
}

///|
test "text in VBox paints at origin and takes a line of flow" {
  let app = UiApp::new()
  app.register_modal(
    "title",
    UiNode::VBox(
      x=Some(760.0),
      y=Some(360.0),
      children=[
        UiNode::Text(
          src=TextBindSrc::Literal("MoonSight"),
          x=0.0,
          y=0.0,
          font_size=36.0,
          visible=VisiblePred::Always,
        ),
        UiNode::Button(label="Start", action_id=0, visible=VisiblePred::Always),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("title")
  let ops = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=UiBindCtx::empty(),
  )
  let mut found_title = false
  let mut start_y : Float = -1.0
  for op in ops {
    match op.text {
      Some(t) =>
        if t == "MoonSight" {
          found_title = true
          // Title sits at VBox origin, not absolute (0,0).
          assert_eq(op.x, 760.0)
          assert_eq(op.y, 360.0)
        }
      None => ()
    }
    if op.resource == "ui.button" || op.resource == "ui.button_focus" {
      start_y = op.y
    }
  }
  assert_true(found_title)
  // Start button is below the title line (~64px).
  assert_true(start_y >= 360.0 + 56.0 && start_y <= 360.0 + 64.0)
}

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
  // Default focus index 0; hover index 1 (second button at y = 200 + ui_line_h)
  assert_true(rt.pointer_hover(100.0 + 10.0, 200.0 + 64.0 + 10.0))
  assert_eq(rt.hover_kind(), 1)
  let ops = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind~)
  let mut found_hover = false
  for op in ops {
    if op.resource == "ui.button_hover" || op.hovered {
      found_hover = true
    }
  }
  assert_true(found_hover)
  rt.pointer_leave()
  assert_eq(rt.hover_kind(), 0)
  // after leave, no hover resource on unfocused button
  let ops2 = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind~)
  for op in ops2 {
    assert_false(op.hovered)
    assert_false(op.resource == "ui.button_hover")
  }
}

///|
test "ScrollView paints only content inside viewport" {
  let app = UiApp::new()
  // 3 text lines × ui_line_h; viewport only 1.5 lines tall
  let lines : Array[UiNode] = []
  for i in 0..<3 {
    lines.push(
      UiNode::Text(
        src=TextBindSrc::Literal("L\{i}"),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=VisiblePred::Always,
      ),
    )
  }
  app.register_modal(
    "sv",
    UiNode::ScrollView(
      x=100.0,
      y=100.0,
      w=400.0,
      h=96.0, // ~1.5 * 64
      children=[UiNode::VBox(x=None, y=None, children=lines)],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("sv")
  rt.sync_bind(UiBindCtx::empty())
  let ops = rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty())
  // At scroll_y=0, only top lines intersect viewport; ops with text must have y in [100, 196)
  for op in ops {
    match op.text {
      Some(_) => {
        assert_true(op.y.to_double() >= 100.0 - 0.1)
        assert_true(op.y.to_double() < 196.0)
      }
      None => ()
    }
  }
}

///|
test "ScrollView content_h exceeds viewport when many children" {
  let app = UiApp::new()
  let lines : Array[UiNode] = []
  for _i in 0..<5 {
    lines.push(
      UiNode::Text(
        src=TextBindSrc::Literal("x"),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=VisiblePred::Always,
      ),
    )
  }
  app.register_modal(
    "sv",
    UiNode::ScrollView(
      x=0.0,
      y=0.0,
      w=400.0,
      h=64.0,
      children=[UiNode::VBox(x=None, y=None, children=lines)],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("sv")
  rt.sync_bind(UiBindCtx::empty())
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  assert_true(rt.scroll_max() > 0.0)
}

///|
/// Build a ScrollView with `n` text lines and the given viewport geometry.
fn make_scroll_runtime(
  n : Int,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  modal_name~ : String = "sv",
) -> UiRuntime {
  let app = UiApp::new()
  let lines : Array[UiNode] = []
  for i in 0..<n {
    lines.push(
      UiNode::Text(
        src=TextBindSrc::Literal("L\{i}"),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=VisiblePred::Always,
      ),
    )
  }
  app.register_modal(
    modal_name,
    UiNode::ScrollView(
      x~,
      y~,
      w~,
      h~,
      children=[UiNode::VBox(x=None, y=None, children=lines)],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal(modal_name)
  rt.sync_bind(UiBindCtx::empty())
  rt
}

///|
test "scroll_by clamps to range" {
  // 5 lines × ui_line_h (~64), viewport h=64 → content_h > viewport
  let rt = make_scroll_runtime(5, 100.0, 100.0, 400.0, 64.0)
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  assert_true(rt.scroll_max() > 0.0)
  rt.scroll_by(-1000.0)
  assert_eq(rt.scroll_y, 0.0)
  rt.scroll_by(10000.0)
  assert_true(rt.scroll_y >= rt.scroll_max() - 0.01)
}

///|
test "wheel dy positive decreases scroll_y" {
  // Viewport at (100,100) 400×200 so (150,120) is over the scroll area
  let rt = make_scroll_runtime(5, 100.0, 100.0, 400.0, 200.0)
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  rt.scroll_y = rt.scroll_max()
  let before = rt.scroll_y
  assert_true(before > 0.0)
  assert_true(rt.handle_wheel(150.0, 120.0, 40.0)) // over viewport; dy>0 → scroll_y decreases
  assert_true(rt.scroll_y < before)
}

///|
test "wheel outside viewport is ignored" {
  let rt = make_scroll_runtime(5, 100.0, 100.0, 400.0, 200.0)
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  rt.scroll_y = rt.scroll_max()
  let before = rt.scroll_y
  assert_false(rt.handle_wheel(10.0, 10.0, 40.0))
  assert_eq(rt.scroll_y, before)
}

///|
test "show_modal backlog pins scroll to newest" {
  // pin_scroll_end before measure sets pin_on_next_layout; paint applies max
  let rt = make_scroll_runtime(5, 100.0, 100.0, 400.0, 64.0, modal_name="backlog")
  rt.pin_scroll_end()
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  assert_true(rt.scroll_max() > 0.0)
  assert_true(rt.scroll_y >= rt.scroll_max() - 0.01)
}

///|
/// Content pan: pointer y increases → scroll_y decreases (same natural feel as wheel).
test "content drag pans scroll_y" {
  // Viewport at (100,100) 400×200; content taller so scroll_max > 0
  let rt = make_scroll_runtime(5, 100.0, 100.0, 400.0, 200.0)
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  assert_true(rt.scroll_max() > 50.0)
  rt.scroll_y = 50.0
  // Drag content down by 20 (pointer y increases) => scroll_y decreases by 20
  rt.begin_scroll_drag_content(y=200.0)
  rt.pointer_scroll_move(y=220.0)
  assert_true(rt.scroll_y > 29.9 && rt.scroll_y < 30.1)
  rt.end_scroll_drag()
  // After end, further move is a no-op
  let after = rt.scroll_y
  rt.pointer_scroll_move(y=250.0)
  assert_eq(rt.scroll_y, after)
}

///|
/// Thumb drag: move pointer toward bottom of track → scroll_y near max.
test "scrollbar thumb drag maps to scroll_y" {
  // Tall content, short viewport so thumb is small and travel is large
  let rt = make_scroll_runtime(8, 100.0, 100.0, 400.0, 200.0)
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  assert_true(rt.scroll_max() > 0.0)
  rt.scroll_y = 0.0
  let caps = FakeCaps::new()
  let c : &Capabilities = caps
  // Thumb sits on right edge of viewport (bar_w=16): x in [484, 500)
  // At scroll_y=0 thumb is near top of track (y≈100)
  assert_true(rt.handle_pointer(c, 492.0, 110.0))
  // Drag toward bottom of track → scroll near max
  rt.pointer_scroll_move(y=280.0)
  assert_true(rt.scroll_y >= rt.scroll_max() * 0.7)
  rt.end_scroll_drag()
}

///|
/// Track click jumps scroll_y by vertical ratio and may start Bar drag.
test "scrollbar track click jumps scroll_y" {
  let rt = make_scroll_runtime(8, 100.0, 100.0, 400.0, 200.0)
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  rt.scroll_y = 0.0
  let caps = FakeCaps::new()
  let c : &Capabilities = caps
  // Click track near bottom (below thumb at top) → jump toward max
  assert_true(rt.handle_pointer(c, 492.0, 280.0))
  assert_true(rt.scroll_y > rt.scroll_max() * 0.5)
  rt.end_scroll_drag()
}

///|
/// Focusable Button wins over content pan; drag state stays Idle.
test "button hit preferred over content pan" {
  let app = UiApp::new()
  let mut n = 0
  let id = app.alloc_action(fn(_c : &Capabilities) { n = n + 1 })
  // Fixed: ScrollView viewport + Button laid at Fixed origin outside content pan
  // area is not required — Button is a focusable child of ScrollView content.
  app.register_modal(
    "sv",
    UiNode::Fixed(
      x=0.0,
      y=0.0,
      w=Some(800.0),
      h=Some(600.0),
      children=[
        UiNode::ScrollView(
          x=100.0,
          y=100.0,
          w=400.0,
          h=200.0,
          children=[
            UiNode::VBox(
              x=None,
              y=None,
              children=[
                UiNode::Button(
                  label="Close",
                  action_id=id,
                  visible=VisiblePred::Always,
                ),
                UiNode::Text(
                  src=TextBindSrc::Literal("L1"),
                  x=0.0,
                  y=0.0,
                  font_size=22.0,
                  visible=VisiblePred::Always,
                ),
                UiNode::Text(
                  src=TextBindSrc::Literal("L2"),
                  x=0.0,
                  y=0.0,
                  font_size=22.0,
                  visible=VisiblePred::Always,
                ),
                UiNode::Text(
                  src=TextBindSrc::Literal("L3"),
                  x=0.0,
                  y=0.0,
                  font_size=22.0,
                  visible=VisiblePred::Always,
                ),
                UiNode::Text(
                  src=TextBindSrc::Literal("L4"),
                  x=0.0,
                  y=0.0,
                  font_size=22.0,
                  visible=VisiblePred::Always,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("sv")
  rt.sync_bind(UiBindCtx::empty())
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  assert_true(rt.scroll_max() > 0.0)
  rt.scroll_y = 50.0
  let before = rt.scroll_y
  let caps = FakeCaps::new()
  let c : &Capabilities = caps
  // Button at scroll origin: (100, 100 - scroll_y) = (100, 50) but clipped;
  // at scroll_y=0 button is at (100,100); with scroll_y=50 button at (100,50)
  // and is fully above viewport → not focusable. Reset to 0 so button is hit.
  rt.scroll_y = 0.0
  // Hit button rect [100,100]–[500,152]
  assert_true(rt.handle_pointer(c, 150.0, 120.0))
  assert_eq(n, 1)
  // No content drag started — move must not pan
  rt.pointer_scroll_move(y=180.0)
  assert_eq(rt.scroll_y, 0.0)
  ignore(before)
}

///|
/// Down on empty viewport content starts Content drag (consumed).
test "content hit begins content drag" {
  let rt = make_scroll_runtime(5, 100.0, 100.0, 400.0, 200.0)
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  rt.scroll_y = 50.0
  let caps = FakeCaps::new()
  let c : &Capabilities = caps
  // Hit left side of viewport (not on scrollbar)
  assert_true(rt.handle_pointer(c, 150.0, 150.0))
  rt.pointer_scroll_move(y=170.0)
  // y +20 → scroll_y -20
  assert_true(rt.scroll_y > 29.9 && rt.scroll_y < 30.1)
  rt.end_scroll_drag()
}

///|
/// After leaving a ScrollView modal, stale viewport metrics must not consume
/// pointer/wheel over the previous backlog geometry (Important 2).
test "return_modal clears scroll viewport metrics" {
  let app = UiApp::new()
  // Menu under backlog: return leaves this top (no ScrollView).
  app.register_modal(
    "game_menu",
    UiNode::Fixed(
      x=0.0,
      y=0.0,
      w=Some(1920.0),
      h=Some(1080.0),
      children=[
        UiNode::Button(label="Continue", action_id=0, visible=VisiblePred::Always),
      ],
    ),
  )
  // Enough lines that content_h exceeds viewport (20 × ~64 > 400).
  let lines : Array[UiNode] = []
  for i in 0..<20 {
    lines.push(
      UiNode::Text(
        src=TextBindSrc::Literal("L\{i}"),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=VisiblePred::Always,
      ),
    )
  }
  // Backlog-like viewport geometry so post-pop coords match a real leave path.
  app.register_modal(
    "backlog",
    UiNode::Fixed(
      x=0.0,
      y=0.0,
      w=Some(1920.0),
      h=Some(1080.0),
      children=[
        UiNode::ScrollView(
          x=360.0,
          y=150.0,
          w=1200.0,
          h=400.0,
          children=[UiNode::VBox(x=None, y=None, children=lines)],
        ),
        UiNode::Button(label="Close", action_id=1, visible=VisiblePred::Always),
      ],
    ),
  )
  let rt = UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("game_menu")
  rt.show_modal("backlog")
  rt.sync_bind(UiBindCtx::empty())
  ignore(rt.paint_modal(canvas_w=1920.0, canvas_h=1080.0, bind=UiBindCtx::empty()))
  assert_true(rt.scroll_max() > 0.0)
  // Wheel over measured viewport consumes while backlog is open.
  assert_true(rt.handle_wheel(500.0, 400.0, 40.0))
  let y_while_open = rt.scroll_y
  // Pop backlog → game_menu (no ScrollView). Metrics must be invalidated.
  rt.return_modal()
  assert_eq(rt.stack_depth(), 1)
  assert_eq(rt.scroll_vp_w.to_double(), 0.0)
  assert_eq(rt.scroll_vp_h.to_double(), 0.0)
  assert_eq(rt.scroll_content_h, 0.0)
  // Old backlog viewport coords must not consume wheel or start content drag.
  assert_false(rt.handle_wheel(500.0, 400.0, 40.0))
  assert_eq(rt.scroll_y, 0.0)
  let caps = FakeCaps::new()
  let c : &Capabilities = caps
  // Pointer in old content area: may hit menu button or miss; must not pan scroll.
  ignore(rt.handle_pointer(c, 500.0, 400.0))
  let before_move = rt.scroll_y
  rt.pointer_scroll_move(y=450.0)
  assert_eq(rt.scroll_y, before_move)
  ignore(y_while_open)
}
