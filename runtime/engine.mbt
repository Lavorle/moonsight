///|
/// Immutable snapshot of theater state for the renderer.
///
/// Built each frame via `Engine::view`; hosts must not mutate Stage through this.
pub(all) struct StageView {
  layers : Array[LayerState]
  text : TextBlock?
  choices : ChoiceState?
  scene : String
  overlay_opacity : Double
  bgm : String?
  se : String?
  wait : WaitKind
  auto : Bool
} derive(Debug)

///|
/// Headless engine: VM + Director + Stage with intent-driven frame ticks.
pub(all) struct Engine {
  mut vm : Vm
  director : Director
  mut stage : Stage
  /// When true, a bare `None_` intent while waiting on Yield advances dialogue.
  mut auto : Bool
  /// Modal screen stack, UiMode, prefs, and screen defs.
  mut screens : ScreenState
  /// Entry scene name for `start_game` / restart.
  ir_entry : String
  /// In-memory multi-slot save blobs (host may mirror to localStorage).
  mut slot_blobs : Array[String?]
} derive(Debug)

///|
/// Load IR into an engine with built-in host handlers.
///
/// Pass `director` to inject a full registry (e.g. `@std_commands.standard_registry()`).
/// Pass `screen_defs` to register Screen DSL definitions (title / game_menu / …).
///
/// Starts in **Playing** with an empty screen stack for backward-compatible scene
/// tests. Call `boot_title` for cold-start Title mode.
pub fn Engine::from_ir(
  ir : @script.IrModule,
  entry~ : String,
  director? : Director,
  screen_defs? : Map[String, @script.ScreenDef],
) -> Engine {
  let stage = Stage::new()
  stage.scene = entry
  let dir = match director {
    Some(d) => d
    None => Director::with_builtins()
  }
  let defs = match screen_defs {
    Some(d) => d
    None => ({} : Map[String, @script.ScreenDef])
  }
  let screens = ScreenState::new(defs)
  // Scene-first construction: Playing + empty stack (Title via `boot_title`).
  screens.mode = Playing
  let n = screens.save_slots
  let slot_blobs : Array[String?] = []
  for _ in 0..<n {
    slot_blobs.push(None)
  }
  {
    vm: Vm::from_module(ir, entry~),
    director: dir,
    stage,
    auto: false,
    screens,
    ir_entry: entry,
    slot_blobs,
  }
}

///|
/// Cold start: enter `Title` and push `title` only when a def is registered.
/// Without a `title` screen, leave mode as `Playing` (scene-first fallback).
pub fn Engine::boot_title(self : Engine) -> Unit {
  self.screens.stack = []
  if self.screens.defs.contains("title") {
    self.screens.mode = Title
    self.screens.show("title")
  } else {
    self.screens.mode = Playing
  }
}

///|
/// Start (or restart) narrative at `ir_entry`: clear stack, `Playing`, fresh stage/VM.
pub fn Engine::start_game(self : Engine) -> Unit {
  self.screens.stack = []
  self.screens.mode = Playing
  let stage = Stage::new()
  stage.scene = self.ir_entry
  self.stage = stage
  self.vm = Vm::from_module(self.vm.ir, entry=self.ir_entry)
  self.auto = self.screens.prefs.auto_mode
}

///|
/// Tear down narrative, clear stack, enter Title and show `title` when defined.
pub fn Engine::quit_to_title(self : Engine) -> Unit {
  self.screens.stack = []
  self.screens.mode = Title
  let stage = Stage::new()
  stage.scene = self.ir_entry
  self.stage = stage
  self.vm = Vm::from_module(self.vm.ir, entry=self.ir_entry)
  self.auto = self.screens.prefs.auto_mode
  if self.screens.defs.contains("title") {
    self.screens.show("title")
  }
}

///|
impl ScreenHost for Engine with fn start_game(self) {
  self.start_game()
}

///|
impl ScreenHost for Engine with fn quit_to_title(self) {
  self.quit_to_title()
}

///|
impl ScreenHost for Engine with fn save_slot(self, i) {
  if i < 0 {
    return
  }
  while self.slot_blobs.length() <= i {
    self.slot_blobs.push(None)
  }
  self.slot_blobs[i] = Some(self.save(slot=i))
}

///|
impl ScreenHost for Engine with fn load_slot(self, i) {
  if i < 0 || i >= self.slot_blobs.length() {
    return
  }
  match self.slot_blobs[i] {
    None => ()
    Some(blob) => {
      self.load(blob) catch {
        _ => return
      }
      // Engine::load already clears screens to Playing; keep explicit for clarity.
      self.clear_screens_to_playing()
    }
  }
}

///|
/// Drop all modal screens and force `Playing` (used after a successful load).
pub fn Engine::clear_screens_to_playing(self : Engine) -> Unit {
  self.screens.stack = []
  self.screens.mode = Playing
}

///|
impl ScreenHost for Engine with fn slot_occupied(self, i) {
  if i < 0 || i >= self.slot_blobs.length() {
    false
  } else {
    self.slot_blobs[i] is Some(_)
  }
}

///|
impl ScreenHost for Engine with fn apply_prefs(self, p) {
  self.auto = p.auto_mode
  self.screens.prefs = p
}

///|
/// Install screen defs (from host `screens.json`) and optional save_slots.
///
/// Preserves UiMode / stack / prefs. Resizes `slot_blobs` when slot count grows.
pub fn Engine::install_screens(
  self : Engine,
  defs : Map[String, @script.ScreenDef],
  save_slots? : Int,
) -> Unit {
  self.screens = self.screens.with_defs(defs, save_slots?)
  let n = self.screens.save_slots
  while self.slot_blobs.length() < n {
    self.slot_blobs.push(None)
  }
}

///|
/// Read/write in-memory slot blobs (host mirrors to localStorage).
pub fn Engine::get_slot_blob(self : Engine, i : Int) -> String? {
  if i < 0 || i >= self.slot_blobs.length() {
    None
  } else {
    self.slot_blobs[i]
  }
}

///|
pub fn Engine::set_slot_blob(self : Engine, i : Int, blob : String) -> Unit {
  if i < 0 {
    return
  }
  while self.slot_blobs.length() <= i {
    self.slot_blobs.push(None)
  }
  if blob.length() == 0 {
    self.slot_blobs[i] = None
  } else {
    self.slot_blobs[i] = Some(blob)
  }
}

///|
/// Current prefs as JSON string.
pub fn Engine::prefs_json(self : Engine) -> String {
  self.screens.prefs.to_json_string()
}

///|
/// Apply prefs JSON (0 ok, 1 error). Updates auto flag.
pub fn Engine::set_prefs_json(self : Engine, json : String) -> Int {
  try {
    let p = Prefs::from_json_string(json)
    self.screens.prefs = p
    self.auto = p.auto_mode
    0
  } catch {
    _ => 1
  }
}

///|
/// Occupancy flags for each save slot (length = `screens.save_slots`).
pub fn Engine::occupied_slots(self : Engine) -> Array[Bool] {
  let n = self.screens.save_slots
  let out : Array[Bool] = []
  for i in 0..<n {
    out.push(
      if i < self.slot_blobs.length() {
        self.slot_blobs[i] is Some(_)
      } else {
        false
      },
    )
  }
  out
}

///|
/// Apply player intent, run the VM until it waits or halts, then tick transitions.
///
/// `dt` is frame delta in seconds (default ≈ 1/60) for fade, tweens, wait, typewriter.
///
/// Tick order (Phase 3): UI intents when stack/Title → else Playing narrative path;
/// layer tweens only while Playing; always tick BGM fade.
pub fn Engine::tick(
  self : Engine,
  intent : Intent,
  dt? : Double = 1.0 / 60.0,
) -> Unit {
  let ui_active =
    self.screens.stack.length() > 0 || (self.screens.mode is Title)
  if ui_active {
    self.tick_ui(intent)
    @audio.global_mixer().tick(dt)
    self.drain_ui_ops()
    return
  }

  // Playing (no modal stack): OpenMenu opens game_menu without advancing narrative.
  let effective = self.effective_intent(intent)
  if effective is OpenMenu {
    self.screens.show("game_menu")
    @audio.global_mixer().tick(dt)
    self.drain_ui_ops()
    return
  }

  // Timed wait: swallow Advance/Select/SkipTyping so the countdown cannot be skipped.
  let gated =
    if self.stage.wait_remaining > 0.0 {
      match effective {
        Advance | SkipTyping | Select(_) => Intent::None_
        other => other
      }
    } else {
      effective
    }
  self.apply_intent(gated)
  self.tick_wait(dt)
  if self.vm.wait is Running {
    self.vm.run_until_wait(self.director, self.stage)
  }
  self.drain_ui_ops()
  // If @ui.show opened a modal this frame, freeze narrative presentation.
  let playing =
    self.screens.stack.is_empty() && !(self.screens.mode is Title)
  if playing {
    self.tick_transitions(dt)
    self.stage.tick_layer_tweens(dt)
    self.tick_typewriter(dt)
  }
  @audio.global_mixer().tick(dt)
}

///|
/// Screen / Title input path: no narrative VM, typewriter, or wait skip.
fn Engine::tick_ui(self : Engine, intent : Intent) -> Unit {
  let host : &ScreenHost = self
  match intent {
    OpenMenu =>
      // Esc while modal: pop one level. Root Title only ignores Esc.
      if self.screens.mode is Title && self.screens.stack.length() <= 1 {
        ()
      } else if self.screens.stack.length() > 0 {
        self.screens.return_()
      }
    Advance | SkipTyping => self.screens.activate(host)
    MenuUp => self.screens.focus_delta(host, -1)
    MenuDown => self.screens.focus_delta(host, 1)
    ToggleAuto => self.apply_intent(ToggleAuto)
    Select(n) => {
      // Optional: jump focus to index n when in range.
      if !self.screens.stack.is_empty() {
        let items = self.screens.focusables(host)
        if n >= 0 && n < items.length() {
          let i = self.screens.stack.length() - 1
          let cur = self.screens.stack[i]
          self.screens.stack[i] = { ..cur, focus: n }
        }
      }
    }
    None_ => ()
  }
}

///|
/// Apply queued `@ui.*` host ops from Stage onto `screens`.
fn Engine::drain_ui_ops(self : Engine) -> Unit {
  if self.stage.ui_ops.is_empty() {
    return
  }
  let ops = self.stage.ui_ops
  self.stage.ui_ops = []
  for op in ops {
    match op {
      UiHostOp::Show(name~, mode~) => self.screens.show(name, mode?)
      UiHostOp::Hide(name~) => self.screens.hide(name?)
    }
  }
}

///|
/// Count down timed `@flow.wait`; when remaining hits 0 and wait is Yield, resume.
fn Engine::tick_wait(self : Engine, dt : Double) -> Unit {
  if self.stage.wait_remaining > 0.0 {
    let left = self.stage.wait_remaining - dt
    if left <= 0.0 {
      self.stage.wait_remaining = 0.0
      if self.vm.wait is Yield {
        self.vm.wait = Running
      }
    } else {
      self.stage.wait_remaining = left
    }
  }
}

///|
/// Immutable render snapshot from the live stage (+ wait/auto flags).
pub fn Engine::view(self : Engine) -> StageView {
  StageView::from_stage(self.stage, wait=self.vm.wait, auto=self.auto)
}

///|
/// Build a `StageView` from live stage state.
pub fn StageView::from_stage(
  stage : Stage,
  wait~ : WaitKind,
  auto~ : Bool,
) -> StageView {
  let choices = match stage.choices {
    None => None
    Some(c) => Some({ options: c.options.copy(), selected: c.selected })
  }
  {
    layers: stage.snapshot_layers(),
    text: stage.text,
    choices,
    scene: stage.scene,
    overlay_opacity: stage.overlay_opacity,
    bgm: stage.bgm,
    se: stage.se,
    wait,
    auto,
  }
}

///|
fn Engine::effective_intent(self : Engine, intent : Intent) -> Intent {
  match intent {
    ToggleAuto => intent
    None_ => if self.auto && self.vm.wait is Yield { Advance } else { None_ }
    other => other
  }
}

///|
fn Engine::apply_intent(self : Engine, intent : Intent) -> Unit {
  match intent {
    ToggleAuto => {
      self.auto = !self.auto
      self.screens.prefs = self.screens.prefs.set("auto_mode", Bool(self.auto))
    }
    _ => ()
  }
  match self.vm.wait {
    Yield =>
      match intent {
        Advance | SkipTyping =>
          // Typewriter: first Advance completes incomplete text; stay on Yield.
          match self.stage.text {
            Some({ complete: false, .. }) => self.stage.complete_text()
            _ => self.vm.wait = Running
          }
        None_
        | Select(_)
        | OpenMenu
        | ToggleAuto
        | MenuUp
        | MenuDown => ()
      }
    Choose =>
      match intent {
        // Number keys / click on a row: commit that index.
        Select(index) => self.confirm_choice(index)
        // Enter / Space / click canvas (Advance): commit focused row.
        Advance | SkipTyping =>
          match self.stage.choice_focus() {
            Some(i) => self.confirm_choice(i)
            None => ()
          }
        // ↑↓ move focus while waiting on narrative choices (not system screens).
        MenuUp => self.stage.move_choice_focus(-1)
        MenuDown => self.stage.move_choice_focus(1)
        _ => ()
      }
    Running | Halted => ()
  }
}

///|
/// Commit a narrative choice by index and resume the VM.
fn Engine::confirm_choice(self : Engine, index : Int) -> Unit {
  match self.stage.choices {
    None => ()
    Some(c) => {
      if c.options.length() == 0 {
        return
      }
      let mut i = index
      if i < 0 {
        i = 0
      } else if i >= c.options.length() {
        i = c.options.length() - 1
      }
      self.stage.select_choice(i)
      match self.vm.choose_result_var {
        Some(name) => self.stage.set_var(name, Int(i))
        None => ()
      }
      self.stage.clear_choices()
      self.vm.choose_result_var = None
      self.vm.wait = Running
    }
  }
}

///|
/// Ease `overlay_opacity` toward `fade_to` over wall-clock `fade_remaining` seconds.
fn Engine::tick_transitions(self : Engine, dt : Double) -> Unit {
  let target = self.stage.fade_to
  let cur = self.stage.overlay_opacity
  if cur == target {
    self.stage.fade_remaining = 0.0
    return
  }
  let rem = self.stage.fade_remaining
  if rem <= 0.0 || dt <= 0.0 {
    self.stage.overlay_opacity = target
    self.stage.fade_remaining = 0.0
    return
  }
  let step_t = if dt < rem { dt } else { rem }
  let frac = step_t / rem
  self.stage.overlay_opacity = cur + (target - cur) * frac
  self.stage.fade_remaining = rem - step_t
  if self.stage.fade_remaining <= 0.0 {
    self.stage.overlay_opacity = target
    self.stage.fade_remaining = 0.0
  }
}

///|
/// Gradual typewriter reveal when text is incomplete (base chars/sec ≈ 40 × prefs).
fn Engine::tick_typewriter(self : Engine, dt : Double) -> Unit {
  match self.stage.text {
    Some({ complete: false, .. }) => {
      let speed = self.screens.prefs.text_speed
      let n = (40.0 * speed * dt).to_int()
      let chars = if n < 1 { 1 } else { n }
      // Only advance when dt is positive; skip zero-dt frames.
      if dt > 0.0 {
        self.stage.reveal_chars(chars)
      }
    }
    _ => ()
  }
}
