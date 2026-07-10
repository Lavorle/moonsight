///|
/// High-level UI mode for narrative vs system screens.
pub(all) enum UiMode {
  Title
  Playing
  Menu
} derive(Debug, Eq)

///|
/// One modal screen instance on the stack.
pub(all) struct ScreenInstance {
  name : String
  /// Optional save/load mode for the `save_load` screen.
  mode : String?
  /// Index into the current focusable button list.
  focus : Int
} derive(Debug)

///|
/// Screen stack, focus, prefs, and registered screen definitions.
pub(all) struct ScreenState {
  mut mode : UiMode
  mut stack : Array[ScreenInstance]
  defs : Map[String, @script.ScreenDef]
  mut prefs : Prefs
  /// Number of save slots (default 6).
  save_slots : Int
} derive(Debug)

///|
/// Engine/host callbacks used by screen action dispatch.
///
/// Test doubles implement this first; `Engine` will in Task 9.
pub(open) trait ScreenHost {
  fn start_game(Self) -> Unit
  fn quit_to_title(Self) -> Unit
  fn save_slot(Self, Int) -> Unit
  fn load_slot(Self, Int) -> Unit
  fn slot_occupied(Self, Int) -> Bool
  fn apply_prefs(Self, Prefs) -> Unit
}

///|
/// Fresh screen state with empty stack, Title mode, and default prefs.
pub fn ScreenState::new(
  defs : Map[String, @script.ScreenDef],
  save_slots~ : Int = 6,
) -> ScreenState {
  {
    mode: Title,
    stack: [],
    defs,
    prefs: Prefs::default(),
    save_slots,
  }
}

///|
/// Push a screen instance (modal). From `Playing`, switches to `Menu`.
pub fn ScreenState::show(self : ScreenState, name : String, mode? : String) -> Unit {
  if self.mode is Playing {
    self.mode = Menu
  }
  self.stack.push({ name, mode, focus: 0 })
}

///|
/// Pop one screen. If the stack empties while in `Menu`, return to `Playing`.
pub fn ScreenState::return_(self : ScreenState) -> Unit {
  if self.stack.is_empty() {
    return
  }
  ignore(self.stack.pop())
  if self.stack.is_empty() && (self.mode is Menu) {
    self.mode = Playing
  }
}

///|
/// Focusable buttons on the top screen: `(label, action)`.
///
/// When the top instance has `mode=load`, `LoadSlot` buttons for empty slots
/// are omitted (not focusable).
pub fn ScreenState::focusables(
  self : ScreenState,
  host : &ScreenHost,
) -> Array[(String, @script.ScreenAction)] {
  guard self.stack.length() > 0 else { return [] }
  let inst = self.stack[self.stack.length() - 1]
  guard self.defs.get(inst.name) is Some(def) else { return [] }
  let raw : Array[(String, @script.ScreenAction)] = []
  collect_buttons(def.root, raw)
  let load_mode = match inst.mode {
    Some("load") => true
    _ => false
  }
  if !load_mode {
    return raw
  }
  let out : Array[(String, @script.ScreenAction)] = []
  for pair in raw {
    let (label, action) = pair
    match action {
      @script.ScreenAction::LoadSlot(i) => {
        if host.slot_occupied(i) {
          out.push((label, action))
        }
      }
      _ => out.push((label, action))
    }
  }
  out
}

///|
/// Move focus by `delta`, wrapping within the current focusable list.
pub fn ScreenState::focus_delta(
  self : ScreenState,
  host : &ScreenHost,
  delta : Int,
) -> Unit {
  if self.stack.is_empty() {
    return
  }
  let items = self.focusables(host)
  let n = items.length()
  if n == 0 {
    return
  }
  let i = self.stack.length() - 1
  let cur = self.stack[i]
  let next = wrap_index(cur.focus + delta, n)
  self.stack[i] = { ..cur, focus: next }
}

///|
/// Activate the focused button on the top screen and dispatch its action.
pub fn ScreenState::activate(self : ScreenState, host : &ScreenHost) -> Unit {
  if self.stack.is_empty() {
    return
  }
  let items = self.focusables(host)
  if items.is_empty() {
    return
  }
  let i = self.stack.length() - 1
  let cur = self.stack[i]
  let idx = wrap_index(cur.focus, items.length())
  // Clamp stored focus if the list shrank.
  if cur.focus != idx {
    self.stack[i] = { ..cur, focus: idx }
  }
  let (_, action) = items[idx]
  self.dispatch_action(host, action)
}

///|
/// Run a single screen action.
fn ScreenState::dispatch_action(
  self : ScreenState,
  host : &ScreenHost,
  action : @script.ScreenAction,
) -> Unit {
  match action {
    @script.ScreenAction::Return => self.return_()
    @script.ScreenAction::StartGame => host.start_game()
    @script.ScreenAction::QuitToTitle => host.quit_to_title()
    @script.ScreenAction::ShowScreen(name~, mode~) => self.show(name, mode?)
    @script.ScreenAction::HideScreen(name~) => self.hide_screen(name)
    @script.ScreenAction::SaveSlot(i) => host.save_slot(i)
    @script.ScreenAction::LoadSlot(i) => host.load_slot(i)
    @script.ScreenAction::SetPrefF(key~, value~) => {
      self.prefs = self.prefs.set(key, Float(value))
      host.apply_prefs(self.prefs)
    }
    @script.ScreenAction::SetPrefB(key~, value~) => {
      self.prefs = self.prefs.set(key, Bool(value))
      host.apply_prefs(self.prefs)
    }
    @script.ScreenAction::AdjustPref(key~, delta~) => {
      self.prefs = self.prefs.adjust(key, delta)
      host.apply_prefs(self.prefs)
    }
    @script.ScreenAction::Noop => ()
  }
}

///|
/// Hide by name (remove matching stack entries) or pop top when name is omitted/`None`.
pub fn ScreenState::hide(self : ScreenState, name? : String) -> Unit {
  self.hide_screen(name)
}

///|
/// Hide by name (remove matching stack entries) or pop top when name is `None`.
fn ScreenState::hide_screen(self : ScreenState, name : String?) -> Unit {
  match name {
    None => self.return_()
    Some(n) => {
      if self.stack.is_empty() {
        return
      }
      let kept : Array[ScreenInstance] = []
      for inst in self.stack {
        if inst.name != n {
          kept.push(inst)
        }
      }
      self.stack = kept
      if self.stack.is_empty() && (self.mode is Menu) {
        self.mode = Playing
      }
    }
  }
}

///|
/// Depth-first collect of buttons under a node.
fn collect_buttons(
  node : @script.SNode,
  out : Array[(String, @script.ScreenAction)],
) -> Unit {
  match node {
    @script.SNode::VBox(children~, ..) => {
      for c in children {
        collect_buttons(c, out)
      }
    }
    @script.SNode::HBox(children~, ..) => {
      for c in children {
        collect_buttons(c, out)
      }
    }
    @script.SNode::Fixed(children~, ..) => {
      for c in children {
        collect_buttons(c, out)
      }
    }
    @script.SNode::Text(_) => ()
    @script.SNode::Button(label~, action~) => out.push((label, action))
  }
}

///|
/// Positive modulo wrap into `0..n-1`.
fn wrap_index(i : Int, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  let m = i % n
  if m < 0 {
    m + n
  } else {
    m
  }
}
