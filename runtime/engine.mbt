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
  /// Modal UI stack, UiMode, prefs, and retained UiApp trees.
  mut ui : UiRuntime
  /// Entry scene name for `start_game` / restart.
  ir_entry : String
  /// In-memory multi-slot save blobs (host may mirror to localStorage).
  mut slot_blobs : Array[String?]
  /// Session-only completed dialogue lines (not saved).
  mut backlog : BacklogStore
  /// Last recorded speaker+text key; avoids double-recording the same line.
  mut backlog_last_key : String
  /// Pending overwrite / quit confirm (None when no dialog active).
  mut pending_confirm : ConfirmKind?
}

///|
/// Load IR into an engine with built-in host handlers.
///
/// Pass `director` to inject a full registry (e.g. `@std_commands.standard_registry()`).
/// Pass `app` to register retained UI modals/HUD (title / game_menu / …).
///
/// Starts in **Playing** with an empty modal stack for backward-compatible scene
/// tests. Call `boot_title` for cold-start Title mode.
pub fn Engine::from_ir(
  ir : @script.IrModule,
  entry~ : String,
  director? : Director,
  app~ : UiApp = UiApp::new(),
  save_slots~ : Int = 6,
) -> Engine {
  let stage = Stage::new()
  stage.scene = entry
  let dir = match director {
    Some(d) => d
    None => Director::with_builtins()
  }
  let ui = UiRuntime::from_app(app, save_slots~)
  // Scene-first construction: Playing + empty stack (Title via `boot_title`).
  ui.mode = Playing
  let n = ui.save_slots
  let slot_blobs : Array[String?] = []
  for _ in 0..<n {
    slot_blobs.push(None)
  }
  let eng : Engine = {
    vm: Vm::from_module(ir, entry~),
    director: dir,
    stage,
    auto: false,
    ui,
    ir_entry: entry,
    slot_blobs,
    backlog: BacklogStore::new(),
    backlog_last_key: "",
    pending_confirm: None,
  }
  eng.sync_mixer_prefs()
  eng
}

///|
/// Push current prefs master/BGM/SE volumes into the global mixer gains.
fn Engine::sync_mixer_prefs(self : Engine) -> Unit {
  let p = self.ui.prefs
  @audio.global_mixer().set_pref_gains(
    master=p.master_volume,
    bgm=p.bgm_volume,
    se=p.se_volume,
  )
}

///|
/// Cold start: enter `Title` and push `title` only when a modal is registered.
/// Without a `title` modal, leave mode as `Playing` (scene-first fallback).
pub fn Engine::boot_title(self : Engine) -> Unit {
  self.ui.stack = []
  if self.ui.app.modals.contains("title") {
    self.ui.mode = Title
    self.ui.show_modal("title")
  } else {
    self.ui.mode = Playing
  }
}

///|
/// Start (or restart) narrative at `ir_entry`: clear stack, `Playing`, fresh stage/VM.
pub fn Engine::start_game(self : Engine) -> Unit {
  self.ui.stack = []
  self.ui.mode = Playing
  self.pending_confirm = None
  let stage = Stage::new()
  stage.scene = self.ir_entry
  self.stage = stage
  self.vm = Vm::from_module(self.vm.ir, entry=self.ir_entry)
  self.auto = self.ui.prefs.auto_mode
  self.backlog.clear()
  self.backlog_last_key = ""
}

///|
/// Tear down narrative, clear stack, enter Title and show `title` when defined.
pub fn Engine::quit_to_title(self : Engine) -> Unit {
  self.ui.stack = []
  self.ui.mode = Title
  self.pending_confirm = None
  let stage = Stage::new()
  stage.scene = self.ir_entry
  self.stage = stage
  self.vm = Vm::from_module(self.vm.ir, entry=self.ir_entry)
  self.auto = self.ui.prefs.auto_mode
  self.backlog.clear()
  self.backlog_last_key = ""
  if self.ui.app.modals.contains("title") {
    self.ui.show_modal("title")
  }
}

///|
pub impl Capabilities for Engine with fn start_game(self) {
  self.start_game()
}

///|
pub impl Capabilities for Engine with fn quit_to_title(self) {
  self.quit_to_title()
}

///|
pub impl Capabilities for Engine with fn show_modal(self, name, mode~) {
  self.ui.show_modal(name, mode?)
}

///|
pub impl Capabilities for Engine with fn return_modal(self) {
  self.ui.return_modal()
}

///|
pub impl Capabilities for Engine with fn hide_modal(self, name~) {
  self.ui.hide_modal(name?)
}

///|
/// Write `i` immediately (no confirm). Used by empty-slot save and confirm_yes.
fn Engine::write_slot(self : Engine, i : Int) -> Unit {
  if i < 0 {
    return
  }
  while self.slot_blobs.length() <= i {
    self.slot_blobs.push(None)
  }
  self.slot_blobs[i] = Some(self.save(slot=i))
}

///|
/// True when the top modal is `"confirm"`.
fn Engine::confirm_is_top(self : Engine) -> Bool {
  self.ui.stack_depth() > 0 &&
    self.ui.stack[self.ui.stack_depth() - 1].name == "confirm"
}

///|
/// Pop confirm modal when it is on top of the stack.
fn Engine::pop_confirm_if_top(self : Engine) -> Unit {
  if self.confirm_is_top() {
    self.ui.return_modal()
  }
}

///|
pub impl Capabilities for Engine with fn save_slot(self, i) {
  if i < 0 {
    return
  }
  while self.slot_blobs.length() <= i {
    self.slot_blobs.push(None)
  }
  // Occupied → confirm; empty → write immediately.
  if self.slot_blobs[i] is Some(_) {
    self.pending_confirm = Some(OverwriteSave(i))
    // Idempotent: already showing confirm → only refresh pending kind.
    if self.confirm_is_top() {
      return
    }
    self.ui.show_modal("confirm")
    return
  }
  self.write_slot(i)
}

///|
pub impl Capabilities for Engine with fn load_slot(self, i) {
  if i < 0 || i >= self.slot_blobs.length() {
    return
  }
  match self.slot_blobs[i] {
    None => ()
    Some(blob) => {
      self.load(blob) catch {
        _ => return
      }
      // Engine::load already clears UI to Playing; keep explicit for clarity.
      self.clear_screens_to_playing()
    }
  }
}

///|
/// Drop all modal screens and force `Playing` (used after a successful load).
pub fn Engine::clear_screens_to_playing(self : Engine) -> Unit {
  self.ui.stack = []
  self.ui.mode = Playing
  self.pending_confirm = None
}

///|
pub impl Capabilities for Engine with fn slot_occupied(self, i) {
  if i < 0 || i >= self.slot_blobs.length() {
    false
  } else {
    self.slot_blobs[i] is Some(_)
  }
}

///|
pub impl Capabilities for Engine with fn slot_label(self, i) {
  if i < 0 || i >= self.slot_blobs.length() {
    return slot_label(None)
  }
  match self.slot_blobs[i] {
    None => slot_label(None)
    Some(blob) =>
      try {
        slot_label(Some(parse_save_game(blob)))
      } catch {
        _ => "Slot \{i}"
      }
  }
}

///|
pub impl Capabilities for Engine with fn set_pref_f(self, key, value) {
  self.ui.prefs = self.ui.prefs.set(key, Float(value))
  self.auto = self.ui.prefs.auto_mode
  self.sync_mixer_prefs()
}

///|
pub impl Capabilities for Engine with fn set_pref_b(self, key, value) {
  self.ui.prefs = self.ui.prefs.set(key, Bool(value))
  self.auto = self.ui.prefs.auto_mode
  self.sync_mixer_prefs()
}

///|
pub impl Capabilities for Engine with fn adjust_pref(self, key, delta) {
  self.ui.prefs = self.ui.prefs.adjust(key, delta)
  self.auto = self.ui.prefs.auto_mode
  self.sync_mixer_prefs()
}

///|
pub impl Capabilities for Engine with fn confirm_choice(self, index) {
  self.confirm_choice(index)
}

///|
pub impl Capabilities for Engine with fn advance(self) {
  self.apply_intent(Advance)
}

///|
pub impl Capabilities for Engine with fn prefs(self) {
  self.ui.prefs
}

///|
pub impl Capabilities for Engine with fn confirm_yes(self) {
  let kind = self.pending_confirm
  self.pending_confirm = None
  match kind {
    Some(OverwriteSave(i)) => {
      self.write_slot(i)
      self.pop_confirm_if_top()
    }
    Some(QuitToTitle) => {
      // Teardown clears stack and enters Title.
      self.quit_to_title()
    }
    None => self.pop_confirm_if_top()
  }
}

///|
pub impl Capabilities for Engine with fn confirm_no(self) {
  self.pending_confirm = None
  self.pop_confirm_if_top()
}

///|
pub impl Capabilities for Engine with fn request_quit_to_title(self) {
  self.pending_confirm = Some(QuitToTitle)
  // Idempotent: already showing confirm → only refresh pending kind.
  if self.confirm_is_top() {
    return
  }
  self.ui.show_modal("confirm")
}

///|
/// Update save slot count (and grow `slot_blobs`). Retained UI trees come from
/// `UiApp` at `from_ir` time. Optional host path for slot count overrides.
pub fn Engine::set_save_slots(self : Engine, save_slots : Int) -> Unit {
  let n = if save_slots < 1 {
    1
  } else if save_slots > 20 {
    20
  } else {
    save_slots
  }
  self.ui.save_slots = n
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
  self.ui.prefs.to_json_string()
}

///|
/// Apply prefs JSON (0 ok, 1 error). Updates auto flag.
pub fn Engine::set_prefs_json(self : Engine, json : String) -> Int {
  try {
    let p = Prefs::from_json_string(json)
    self.ui.prefs = p
    self.auto = p.auto_mode
    self.sync_mixer_prefs()
    0
  } catch {
    _ => 1
  }
}

///|
/// Occupancy flags for each save slot (length = `ui.save_slots`).
pub fn Engine::occupied_slots(self : Engine) -> Array[Bool] {
  let n = self.ui.save_slots
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
/// Max Yield→run cycles per frame while `skip_held` (prevents one-frame script thrash).
let skip_burst_max : Int = 8

///|
/// Apply player intent, run the VM until it waits or halts, then tick transitions.
///
/// `dt` is frame delta in seconds (default ≈ 1/60) for fade, tweens, wait, typewriter.
/// `skip_held` (Ctrl hold): complete typewriter / burst-advance Yields; does not skip
/// timed waits or auto-select choices. Ignored while UI/Title is active.
///
/// Tick order (Phase 4): UI intents when stack/Title → else Playing narrative path;
/// layer tweens only while Playing; always tick BGM fade.
pub fn Engine::tick(
  self : Engine,
  intent : Intent,
  dt? : Double = 1.0 / 60.0,
  skip_held~ : Bool = false,
) -> Unit {
  let ui_active =
    self.ui.stack_depth() > 0 || (self.ui.mode is Title)
  if ui_active {
    self.tick_ui(intent)
    @audio.global_mixer().tick(dt)
    self.drain_ui_ops()
    return
  }

  // Playing (no modal stack): OpenMenu / OpenBacklog open system modals
  // without advancing narrative.
  let effective = self.effective_intent(intent)
  if effective is OpenMenu {
    self.ui.show_modal("game_menu")
    @audio.global_mixer().tick(dt)
    self.drain_ui_ops()
    return
  }
  if effective is OpenBacklog {
    self.ui.show_modal("backlog")
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
  // If @ui.show opened a modal this frame, freeze narrative presentation.
  // Also gate on pending ui_ops: Show is queued until drain_ui_ops, so stack
  // may still be empty while a modal is about to open.
  let playing =
    self.ui.stack.is_empty() &&
    !(self.ui.mode is Title) &&
    self.stage.ui_ops.is_empty()
  if skip_held && playing && self.stage.wait_remaining <= 0.0 {
    self.tick_skip_burst()
  }
  self.drain_ui_ops()
  // Re-check playing: skip burst or host ops may have opened a modal.
  let playing =
    self.ui.stack.is_empty() && !(self.ui.mode is Title)
  if playing {
    self.tick_transitions(dt)
    self.stage.tick_layer_tweens(dt)
    self.tick_typewriter(dt)
  }
  @audio.global_mixer().tick(dt)
}

///|
/// Hold-skip burst: complete incomplete typewriter once, or advance Yields up to
/// `skip_burst_max` times. Stops on Choose, Halted, timed wait, or pending
/// `@ui.show` (ops drained after the burst so stack is still empty mid-loop).
fn Engine::tick_skip_burst(self : Engine) -> Unit {
  let mut bursts = 0
  while bursts < skip_burst_max {
    if self.stage.wait_remaining > 0.0 {
      break
    }
    // Modal open or pending @ui.show / hide: stop narrative skip.
    if self.ui.stack_depth() > 0 ||
      (self.ui.mode is Title) ||
      !self.stage.ui_ops.is_empty() {
      break
    }
    match self.vm.wait {
      Halted | Choose => break
      Running => {
        self.vm.run_until_wait(self.director, self.stage)
        // Budget stall: avoid spinning if still Running.
        if self.vm.wait is Running {
          break
        }
        // @ui.show may have queued ops during this run.
        if !self.stage.ui_ops.is_empty() {
          break
        }
      }
      Yield =>
        match self.stage.text {
          Some({ complete: false, .. }) => {
            // Reuse SkipTyping path (complete_text + backlog); one complete per frame.
            self.apply_intent(SkipTyping)
            break
          }
          _ => {
            self.apply_intent(SkipTyping)
            if self.vm.wait is Running {
              self.vm.run_until_wait(self.director, self.stage)
            }
            bursts = bursts + 1
            // SkipTyping+run may have hit @ui.show; do not advance past its Yield.
            if !self.stage.ui_ops.is_empty() {
              break
            }
          }
        }
    }
  }
}

///|
/// Build UiBindCtx from stage + prefs + slots and store on UiRuntime.
///
/// Hosts should call this before `ui.paint_modal` / `ui.paint_hud` each frame
/// so HUD dialogue/choices reflect the current stage.
pub fn Engine::sync_ui_bind(self : Engine) -> Unit {
  let occupied = self.occupied_slots()
  let (has_text, dialogue_name, dialogue_body) = match self.stage.text {
    None => (false, "", "")
    Some(t) => {
      let name = match t.speaker {
        Some(s) => s
        None => ""
      }
      // Typewriter: expose only the visible prefix so HUD body tracks reveal.
      let body = visible_text_prefix(t.full_text, t.visible_chars)
      (true, name, body)
    }
  }
  let (has_choices, choice_labels) = match self.stage.choices {
    None => {
      let empty : Array[String] = []
      (false, empty)
    }
    Some(c) => (true, c.options.copy())
  }
  // Playing + empty modal stack: HUD paints focus from ui.hud_focus, but
  // MenuUp/Down move Stage choice focus. Keep the paint highlight aligned.
  match self.stage.choice_focus() {
    Some(i) => self.ui.hud_focus = i
    None => ()
  }
  let modal_mode = if self.ui.stack.is_empty() {
    None
  } else {
    self.ui.stack[self.ui.stack.length() - 1].mode
  }
  // Last 12 backlog lines (oldest first among the window; newest last).
  let backlog_lines = format_backlog_lines(self.backlog, 12)
  self.ui.sync_bind(
    {
      has_text,
      has_choices,
      prefs: self.ui.prefs,
      occupied,
      modal_mode,
      vars: {},
      choice_labels,
      dialogue_name,
      dialogue_body,
      backlog_lines,
    },
  )
}

///|
/// Preformat the last `max` backlog entries as "Name: text" (or bare text).
fn format_backlog_lines(store : BacklogStore, max : Int) -> Array[String] {
  let n = store.len()
  let start = if n > max { n - max } else { 0 }
  let out : Array[String] = []
  for i in start..<n {
    let e = store.get(i)
    let line = match e.speaker {
      Some(s) => "\{s}: \{e.text}"
      None => e.text
    }
    out.push(line)
  }
  out
}

///|
/// Screen / Title input path: no narrative VM, typewriter, or wait skip.
fn Engine::tick_ui(self : Engine, intent : Intent) -> Unit {
  self.sync_ui_bind()
  let caps : &Capabilities = self
  match intent {
    OpenMenu =>
      // Esc while modal: pop one level. Root Title only ignores Esc.
      // Confirm: same as confirm_no (clear pending + pop) so Esc cannot leave
      // a stale pending_confirm after the dialog is gone.
      if self.ui.mode is Title && self.ui.stack_depth() <= 1 {
        ()
      } else if self.confirm_is_top() {
        self.pending_confirm = None
        self.ui.return_modal()
      } else if self.ui.stack_depth() > 0 {
        self.ui.return_modal()
      }
    Advance | SkipTyping => self.ui.activate(caps)
    MenuUp => self.ui.focus_delta(caps, -1)
    MenuDown => self.ui.focus_delta(caps, 1)
    MenuLeft => self.ui.slider_delta(caps, -1)
    MenuRight => self.ui.slider_delta(caps, 1)
    // OpenBacklog is handled on the Playing path (empty stack).
    OpenBacklog => ()
    ToggleAuto => self.apply_intent(ToggleAuto)
    Select(n) => {
      // Optional: jump focus to index n when in range.
      if !self.ui.stack.is_empty() {
        let items = self.ui.focusables_top(self.ui.bind)
        if n >= 0 && n < items.length() {
          let i = self.ui.stack.length() - 1
          let cur = self.ui.stack[i]
          self.ui.stack[i] = { ..cur, focus: n }
        }
      }
    }
    None_ => ()
  }
}

///|
/// Apply queued `@ui.*` host ops from Stage onto `ui`.
fn Engine::drain_ui_ops(self : Engine) -> Unit {
  if self.stage.ui_ops.is_empty() {
    return
  }
  let ops = self.stage.ui_ops
  self.stage.ui_ops = []
  for op in ops {
    match op {
      UiHostOp::Show(name~, mode~) => self.ui.show_modal(name, mode?)
      UiHostOp::Hide(name~) => self.ui.hide_modal(name?)
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
      self.ui.prefs = self.ui.prefs.set("auto_mode", Bool(self.auto))
    }
    _ => ()
  }
  match self.vm.wait {
    Yield =>
      match intent {
        Advance | SkipTyping =>
          // Typewriter: first Advance completes incomplete text; stay on Yield.
          match self.stage.text {
            Some({ complete: false, .. }) => {
              self.stage.complete_text()
              self.maybe_record_backlog()
            }
            _ => self.vm.wait = Running
          }
        None_
        | Select(_)
        | OpenMenu
        | OpenBacklog
        | ToggleAuto
        | MenuUp
        | MenuDown
        | MenuLeft
        | MenuRight => ()
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
        // Also update hud_focus so mid-tick paint matches Stage authority.
        MenuUp => {
          self.stage.move_choice_focus(-1)
          match self.stage.choice_focus() {
            Some(i) => self.ui.hud_focus = i
            None => ()
          }
        }
        MenuDown => {
          self.stage.move_choice_focus(1)
          match self.stage.choice_focus() {
            Some(i) => self.ui.hud_focus = i
            None => ()
          }
        }
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
/// Visible typewriter prefix of `full` up to `visible_chars` code units.
fn visible_text_prefix(full : String, visible_chars : Int) -> String {
  if visible_chars <= 0 {
    ""
  } else if visible_chars >= full.length() {
    full
  } else {
    full.unsafe_substring(start=0, end=visible_chars)
  }
}

///|
/// Gradual typewriter reveal when text is incomplete (base chars/sec ≈ 40 × prefs).
fn Engine::tick_typewriter(self : Engine, dt : Double) -> Unit {
  match self.stage.text {
    Some({ complete: false, .. }) => {
      let speed = self.ui.prefs.text_speed
      let n = (40.0 * speed * dt).to_int()
      let chars = if n < 1 { 1 } else { n }
      // Only advance when dt is positive; skip zero-dt frames.
      if dt > 0.0 {
        self.stage.reveal_chars(chars)
      }
    }
    _ => ()
  }
  self.maybe_record_backlog()
}

///|
/// If the stage text block is complete and non-empty, append it to the session
/// backlog once (deduped by speaker + full_text key).
fn Engine::maybe_record_backlog(self : Engine) -> Unit {
  match self.stage.text {
    Some({ complete: true, full_text, speaker, .. }) => {
      if full_text.length() == 0 {
        return
      }
      let sp = match speaker {
        Some(s) => s
        None => "-"
      }
      let key = "\{sp}-\{full_text}"
      if key == self.backlog_last_key {
        return
      }
      self.backlog_last_key = key
      self.backlog.push(speaker~, text=full_text)
    }
    _ => ()
  }
}
