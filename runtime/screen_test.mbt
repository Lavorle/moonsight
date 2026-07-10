///|
/// Test double for `ScreenHost`.
struct FakeHost {
  mut start_game_n : Int
  mut quit_to_title_n : Int
  save_slot_calls : Array[Int]
  load_slot_calls : Array[Int]
  occupied : Array[Bool]
  mut applied_prefs : Prefs?
} derive(Debug)

///|
fn FakeHost::new(occupied~ : Array[Bool] = []) -> FakeHost {
  {
    start_game_n: 0,
    quit_to_title_n: 0,
    save_slot_calls: [],
    load_slot_calls: [],
    occupied,
    applied_prefs: None,
  }
}

///|
impl ScreenHost for FakeHost with fn start_game(self) {
  self.start_game_n = self.start_game_n + 1
}

///|
impl ScreenHost for FakeHost with fn quit_to_title(self) {
  self.quit_to_title_n = self.quit_to_title_n + 1
}

///|
impl ScreenHost for FakeHost with fn save_slot(self, i) {
  self.save_slot_calls.push(i)
}

///|
impl ScreenHost for FakeHost with fn load_slot(self, i) {
  self.load_slot_calls.push(i)
}

///|
impl ScreenHost for FakeHost with fn slot_occupied(self, i) {
  if i < 0 || i >= self.occupied.length() {
    false
  } else {
    self.occupied[i]
  }
}

///|
impl ScreenHost for FakeHost with fn apply_prefs(self, p) {
  self.applied_prefs = Some(p)
}

///|
fn button(label : String, action : @script.ScreenAction) -> @script.SNode {
  @script.SNode::Button(label~, action~)
}

///|
fn vbox(children : Array[@script.SNode]) -> @script.SNode {
  @script.SNode::VBox(x=None, y=None, children~)
}

///|
fn title_def() -> @script.ScreenDef {
  {
    name: "title",
    root: vbox([
      button("Start", @script.ScreenAction::StartGame),
      button("Load", @script.ScreenAction::ShowScreen(name="save_load", mode=Some("load"))),
      button("Quit", @script.ScreenAction::QuitToTitle),
    ]),
  }
}

///|
fn menu_def() -> @script.ScreenDef {
  {
    name: "game_menu",
    root: vbox([
      button("Save", @script.ScreenAction::ShowScreen(name="save_load", mode=Some("save"))),
      button("Settings", @script.ScreenAction::ShowScreen(name="settings", mode=None)),
      button("Return", @script.ScreenAction::Return),
    ]),
  }
}

///|
fn save_load_def() -> @script.ScreenDef {
  {
    name: "save_load",
    root: vbox([
      button("Slot 0", @script.ScreenAction::LoadSlot(0)),
      button("Slot 1", @script.ScreenAction::LoadSlot(1)),
      button("Slot 2", @script.ScreenAction::SaveSlot(2)),
      button("Back", @script.ScreenAction::Return),
    ]),
  }
}

///|
fn settings_def() -> @script.ScreenDef {
  {
    name: "settings",
    root: vbox([
      button("Faster", @script.ScreenAction::AdjustPref(key="text_speed", delta=0.5)),
      button("Auto on", @script.ScreenAction::SetPrefB(key="auto_mode", value=true)),
      button("Vol", @script.ScreenAction::SetPrefF(key="master_volume", value=0.4)),
      button("Back", @script.ScreenAction::Return),
    ]),
  }
}

///|
fn make_defs() -> Map[String, @script.ScreenDef] {
  {
    "title": title_def(),
    "game_menu": menu_def(),
    "save_load": save_load_def(),
    "settings": settings_def(),
  }
}

///|
test "screen push and pop return to playing" {
  let ss = ScreenState::new(make_defs())
  assert_true(ss.mode is Title)
  assert_eq(ss.stack.length(), 0)
  ss.show("title")
  assert_eq(ss.stack.length(), 1)
  assert_eq(ss.stack[0].name, "title")
  // Title mode is preserved when already Title
  assert_true(ss.mode is Title)
  // Simulate gameplay then open menu
  ss.mode = Playing
  ss.stack = []
  ss.show("game_menu")
  assert_true(ss.mode is Menu)
  assert_eq(ss.stack.length(), 1)
  ss.show("save_load", mode="save")
  assert_eq(ss.stack.length(), 2)
  assert_eq(ss.stack[1].name, "save_load")
  guard ss.stack[1].mode is Some("save") else { fail("mode") }
  ss.return_()
  assert_eq(ss.stack.length(), 1)
  assert_true(ss.mode is Menu)
  ss.return_()
  assert_eq(ss.stack.length(), 0)
  assert_true(ss.mode is Playing)
}

///|
test "screen focus wraps" {
  let ss = ScreenState::new(make_defs())
  let host = FakeHost::new()
  let h : &ScreenHost = host
  ss.show("title")
  assert_eq(ss.stack[0].focus, 0)
  ss.focus_delta(h, 1)
  assert_eq(ss.stack[0].focus, 1)
  ss.focus_delta(h, 1)
  assert_eq(ss.stack[0].focus, 2)
  ss.focus_delta(h, 1)
  assert_eq(ss.stack[0].focus, 0)
  ss.focus_delta(h, -1)
  assert_eq(ss.stack[0].focus, 2)
  let items = ss.focusables(h)
  assert_eq(items.length(), 3)
  assert_eq(items[0].0, "Start")
  assert_eq(items[2].0, "Quit")
}

///|
test "load mode empty slots not focusable" {
  // Slot 0 occupied, 1 empty
  let host = FakeHost::new(occupied=[true, false, false])
  let h : &ScreenHost = host
  let ss = ScreenState::new(make_defs())
  ss.mode = Playing
  ss.show("save_load", mode="load")
  let items = ss.focusables(h)
  // LoadSlot(0) kept, LoadSlot(1) dropped, SaveSlot(2) and Back kept
  assert_eq(items.length(), 3)
  assert_eq(items[0].0, "Slot 0")
  assert_eq(items[1].0, "Slot 2")
  assert_eq(items[2].0, "Back")
  // save mode keeps all including empty load slots if any
  ss.return_()
  ss.show("save_load", mode="save")
  let save_items = ss.focusables(h)
  assert_eq(save_items.length(), 4)
}

///|
test "activate start_game calls host" {
  let host = FakeHost::new()
  let h : &ScreenHost = host
  let ss = ScreenState::new(make_defs())
  ss.show("title")
  // focus 0 = Start → StartGame
  assert_eq(ss.stack[0].focus, 0)
  ss.activate(h)
  assert_eq(host.start_game_n, 1)
  // focus Quit
  ss.focus_delta(h, 2)
  ss.activate(h)
  assert_eq(host.quit_to_title_n, 1)
}

///|
test "activate return pops; show_screen pushes" {
  let host = FakeHost::new()
  let h : &ScreenHost = host
  let ss = ScreenState::new(make_defs())
  ss.mode = Playing
  ss.show("game_menu")
  // focus Settings (index 1) → ShowScreen settings
  ss.focus_delta(h, 1)
  ss.activate(h)
  assert_eq(ss.stack.length(), 2)
  assert_eq(ss.stack[1].name, "settings")
  // Back on settings
  ss.focus_delta(h, 3)
  ss.activate(h)
  assert_eq(ss.stack.length(), 1)
  assert_eq(ss.stack[0].name, "game_menu")
  // Return on game_menu
  ss.focus_delta(h, 2)
  // After pop focus may be stale; set Return focus explicitly
  let top = ss.stack[0]
  ss.stack[0] = { ..top, focus: 2 }
  ss.activate(h)
  assert_eq(ss.stack.length(), 0)
  assert_true(ss.mode is Playing)
}

///|
test "activate prefs mutates and applies" {
  let host = FakeHost::new()
  let h : &ScreenHost = host
  let ss = ScreenState::new(make_defs())
  ss.mode = Playing
  ss.show("settings")
  // Faster → adjust text_speed +0.5
  ss.activate(h)
  assert_eq(ss.prefs.text_speed, 1.5)
  guard host.applied_prefs is Some(p0) else { fail("applied") }
  assert_eq(p0.text_speed, 1.5)
  // Auto on
  ss.focus_delta(h, 1)
  ss.activate(h)
  assert_true(ss.prefs.auto_mode)
  // Vol 0.4
  ss.focus_delta(h, 1)
  ss.activate(h)
  assert_eq(ss.prefs.master_volume, 0.4)
}

///|
test "activate load and save slots" {
  let host = FakeHost::new(occupied=[true, false])
  let h : &ScreenHost = host
  let ss = ScreenState::new(make_defs())
  ss.mode = Playing
  ss.show("save_load", mode="load")
  // focusables: Slot0, Slot2(save), Back — activate load 0
  ss.activate(h)
  assert_eq(host.load_slot_calls.length(), 1)
  assert_eq(host.load_slot_calls[0], 0)
  // save mode, focus Slot 2 save
  ss.return_()
  ss.show("save_load", mode="save")
  ss.focus_delta(h, 2)
  ss.activate(h)
  assert_eq(host.save_slot_calls.length(), 1)
  assert_eq(host.save_slot_calls[0], 2)
}

///|
test "noop action does nothing" {
  let defs : Map[String, @script.ScreenDef] = {
    "n": { name: "n", root: vbox([button("X", @script.ScreenAction::Noop)]) },
  }
  let ss = ScreenState::new(defs)
  let host = FakeHost::new()
  let h : &ScreenHost = host
  ss.show("n")
  ss.activate(h)
  assert_eq(host.start_game_n, 0)
  assert_eq(ss.stack.length(), 1)
}
