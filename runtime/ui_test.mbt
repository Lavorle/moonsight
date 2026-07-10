///|
/// Minimal `Capabilities` double for UiApp handler tests.
struct FakeCaps {
  mut start_game_n : Int
} derive(Debug)

///|
fn FakeCaps::new() -> FakeCaps {
  { start_game_n: 0 }
}

///|
impl Capabilities for FakeCaps with fn start_game(self) {
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
impl Capabilities for FakeCaps with fn save_slot(_self, _i) {
  ()
}

///|
impl Capabilities for FakeCaps with fn load_slot(_self, _i) {
  ()
}

///|
impl Capabilities for FakeCaps with fn slot_occupied(_self, _i) {
  false
}

///|
impl Capabilities for FakeCaps with fn slot_label(_self, i) {
  "Slot \{i}"
}

///|
impl Capabilities for FakeCaps with fn set_pref_f(_self, _k, _v) {
  ()
}

///|
impl Capabilities for FakeCaps with fn set_pref_b(_self, _k, _v) {
  ()
}

///|
impl Capabilities for FakeCaps with fn adjust_pref(_self, _k, _delta) {
  ()
}

///|
impl Capabilities for FakeCaps with fn confirm_choice(_self, _i) {
  ()
}

///|
impl Capabilities for FakeCaps with fn advance(_self) {
  ()
}

///|
impl Capabilities for FakeCaps with fn prefs(_self) {
  Prefs::default()
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
