///|
/// VM-owned logical snapshot. Runtime diagnostics and decoded scene ops are
/// prepared from the target module rather than persisted as authority.
pub struct VmLogicalState {
  scene : String
  ip : Int
  stack : Array[Value]
  halted : Bool
  wait : WaitKind
  choose_result_var : String?
}

///|
/// Stage-owned logical snapshot. Host op queues and save hints are transient.
pub struct StageLogicalState {
  scene : String
  vars : Map[String, Value]
  layers : Array[LayerState]
  text : TextBlock?
  choices : ChoiceState?
  overlay_opacity : Double
  fade_to : Double
  fade_remaining : Double
  wait_remaining : Double
  dissolve_phase : Int
  dissolve_total : Double
  bgm : String?
  se : String?
}

///|
/// UI-owned semantic state. Preferences, slots, bind/layout caches, hover,
/// pointer gestures, and transient confirmation modals are excluded.
pub struct UiLogicalState {
  mode : UiMode
  stack : Array[ModalInstance]
  hud_focus : Int
  scroll_y : Double
}

///|
/// Backlog-owned session state used by rollback, but not the save projection.
pub struct BacklogLogicalState {
  entries : Array[BacklogEntry]
  capacity : Int
  last_key : String
}

///|
/// Sole aggregate logical snapshot facade. Save and rollback adapters consume
/// this type instead of reading live Engine fields independently.
pub struct EngineLogicalState {
  module_id : String
  vm : VmLogicalState
  stage : StageLogicalState
  ui : UiLogicalState
  backlog : BacklogLogicalState
  audio : AudioLogicState
  auto : Bool
}

///|
/// Fully validated replacement objects. Publishing this aggregate performs no
/// decoding, lookup, or validation and therefore cannot partially reject.
priv struct PreparedEngineLogicalState {
  vm : Vm
  stage : Stage
  ui : UiRuntime
  backlog : BacklogStore
  backlog_last_key : String
  audio : AudioLogicState
  auto : Bool
}

///|
fn copy_layer_states(layers : Array[LayerState]) -> Array[LayerState] {
  layers.map(layer => { ..layer, tweens: layer.tweens.copy() })
}

///|
fn VmLogicalState::capture(vm : Vm) -> VmLogicalState {
  {
    scene: vm.scene,
    ip: vm.ip,
    stack: vm.stack.copy(),
    halted: vm.halted,
    wait: vm.wait,
    choose_result_var: vm.choose_result_var,
  }
}

///|
fn VmLogicalState::prepare(
  self : VmLogicalState,
  current : Vm,
) -> Vm raise SaveError {
  let ops = match load_scene_ops(current.ir, self.scene) {
    Some(ops) => ops
    None => raise SaveError::UnknownScene(scene=self.scene)
  }
  let max_ip = ops.length()
  if self.ip < 0 || self.ip > max_ip {
    raise SaveError::InvalidInstructionPointer(
      scene=self.scene,
      ip=self.ip,
      max_ip~,
    )
  }
  {
    ir: current.ir,
    ops,
    ip: self.ip,
    scene: self.scene,
    stack: self.stack.copy(),
    halted: self.halted,
    wait: self.wait,
    choose_result_var: self.choose_result_var,
    last_error: None,
  }
}

///|
fn StageLogicalState::capture(stage : Stage) -> StageLogicalState {
  let vars : Map[String, Value] = {}
  for key, value in stage.vars {
    vars[key] = value
  }
  let choices = match stage.choices {
    Some(choice) =>
      Some({
        options: choice.options.copy(),
        option_ids: choice.option_ids.copy(),
        selected: choice.selected,
      })
    None => None
  }
  {
    scene: stage.scene,
    vars,
    layers: copy_layer_states(stage.layers),
    text: stage.text,
    choices,
    overlay_opacity: stage.overlay_opacity,
    fade_to: stage.fade_to,
    fade_remaining: stage.fade_remaining,
    wait_remaining: stage.wait_remaining,
    dissolve_phase: stage.dissolve_phase,
    dissolve_total: stage.dissolve_total,
    bgm: stage.bgm,
    se: stage.se,
  }
}

///|
fn StageLogicalState::prepare(
  self : StageLogicalState,
) -> Stage raise SaveError {
  if self.dissolve_phase < 0 || self.dissolve_phase > 2 {
    raise SaveError::InvalidLogicalState(
      message="dissolve_phase must be 0, 1, or 2",
    )
  }
  if self.fade_remaining < 0.0 ||
    self.wait_remaining < 0.0 ||
    self.dissolve_total < 0.0 {
    raise SaveError::InvalidLogicalState(
      message="logical durations must be non-negative",
    )
  }
  let vars : Map[String, Value] = {}
  for key, value in self.vars {
    vars[key] = value
  }
  let choices = match self.choices {
    Some(choice) =>
      Some({
        options: choice.options.copy(),
        option_ids: choice.option_ids.copy(),
        selected: choice.selected,
      })
    None => None
  }
  {
    layers: copy_layer_states(self.layers),
    text: self.text,
    choices,
    vars,
    scene: self.scene,
    overlay_opacity: self.overlay_opacity,
    fade_to: self.fade_to,
    wait_remaining: self.wait_remaining,
    fade_remaining: self.fade_remaining,
    dissolve_phase: self.dissolve_phase,
    dissolve_total: self.dissolve_total,
    bgm: self.bgm,
    se: self.se,
    save_hint: false,
    ui_ops: [],
  }
}

///|
fn UiLogicalState::capture(ui : UiRuntime) -> UiLogicalState {
  let stack : Array[ModalInstance] = []
  for modal in ui.stack {
    if modal.name != "confirm" {
      stack.push(modal)
    }
  }
  { mode: ui.mode, stack, hud_focus: ui.hud_focus, scroll_y: ui.scroll_y }
}

///|
fn UiLogicalState::prepare(
  self : UiLogicalState,
  current : UiRuntime,
) -> UiRuntime {
  {
    app: current.app,
    mode: self.mode,
    stack: self.stack.copy(),
    save_slots: current.save_slots,
    prefs: current.prefs,
    bind: current.bind,
    hud_focus: self.hud_focus,
    hover: -1,
    scroll_y: self.scroll_y,
    scroll_content_h: 0.0,
    scroll_vp_x: 0.0,
    scroll_vp_y: 0.0,
    scroll_vp_w: 0.0,
    scroll_vp_h: 0.0,
    scroll_bar_w: ui_scroll_bar_w,
    pin_on_next_layout: false,
    scroll_drag: Idle,
  }
}

///|
fn BacklogLogicalState::capture(
  backlog : BacklogStore,
  last_key : String,
) -> BacklogLogicalState {
  { entries: backlog.entries.copy(), capacity: backlog.capacity, last_key }
}

///|
fn BacklogLogicalState::prepare(self : BacklogLogicalState) -> BacklogStore {
  {
    entries: self.entries.copy(),
    capacity: if self.capacity < 1 {
      1
    } else {
      self.capacity
    },
  }
}

///|
fn AudioLogicState::capture(stage : Stage) -> AudioLogicState {
  audio_logic_from_mixer(stage.bgm, stage.se)
}

///|
fn EngineLogicalState::capture(eng : Engine) -> EngineLogicalState {
  {
    module_id: eng.module_id,
    vm: VmLogicalState::capture(eng.vm),
    stage: StageLogicalState::capture(eng.stage),
    ui: UiLogicalState::capture(eng.ui),
    backlog: BacklogLogicalState::capture(eng.backlog, eng.backlog_last_key),
    audio: AudioLogicState::capture(eng.stage),
    auto: eng.auto,
  }
}

///|
/// Conservative in-memory payload estimate used by the frozen rollback budget.
/// It intentionally counts fixed subsystem overhead plus retained string data;
/// backend handles and derived caches are excluded from the logical snapshot.
fn EngineLogicalState::estimated_rollback_bytes(
  self : EngineLogicalState,
) -> Int {
  let mut bytes = 512
  bytes += self.module_id.length() * 2
  bytes += self.vm.scene.length() * 2
  bytes += self.stage.scene.length() * 2
  for layer in self.stage.layers {
    bytes += 128 + (layer.id.length() + layer.resource.length()) * 2
    bytes += layer.tweens.length() * 32
  }
  match self.stage.text {
    Some(text) => {
      bytes += 64 + text.full_text.length() * 2
      match text.speaker {
        Some(speaker) => bytes += speaker.length() * 2
        None => ()
      }
    }
    None => ()
  }
  match self.stage.choices {
    Some(choices) =>
      for option in choices.options {
        bytes += 32 + option.length() * 2
      }
    None => ()
  }
  for modal in self.ui.stack {
    bytes += 96 + modal.name.length() * 2
  }
  for entry in self.backlog.entries {
    bytes += 64 + entry.text.length() * 2
    match entry.speaker {
      Some(speaker) => bytes += speaker.length() * 2
      None => ()
    }
  }
  bytes
}

///|
fn Engine::prepare_logical_state(
  self : Engine,
  state : EngineLogicalState,
) -> PreparedEngineLogicalState raise SaveError {
  if state.module_id != "" && state.module_id != self.module_id {
    raise SaveError::ModuleMismatch(
      expected=self.module_id,
      found=state.module_id,
    )
  }
  if state.vm.scene != state.stage.scene {
    raise SaveError::InvalidLogicalState(
      message="VM and Stage scene identities differ",
    )
  }
  match state.vm.wait {
    Choose =>
      if state.stage.choices is None || state.vm.choose_result_var is None {
        raise SaveError::InvalidContinuation(
          message="Choose requires choices and choose_result_var",
        )
      }
    _ =>
      if state.stage.choices is Some(_) || state.vm.choose_result_var is Some(_) {
        raise SaveError::InvalidContinuation(
          message="non-Choose wait cannot carry choice state",
        )
      }
  }
  {
    vm: state.vm.prepare(self.vm),
    stage: state.stage.prepare(),
    ui: state.ui.prepare(self.ui),
    backlog: state.backlog.prepare(),
    backlog_last_key: state.backlog.last_key,
    audio: state.audio,
    auto: state.auto,
  }
}

///|
/// Publish the already-prepared aggregate. The only post-commit work is backend
/// reconciliation, whose pending snapshot remains available for retry.
fn Engine::publish_prepared_logical_state(
  self : Engine,
  prepared : PreparedEngineLogicalState,
) -> Unit {
  self.vm = prepared.vm
  self.stage = prepared.stage
  self.ui = prepared.ui
  self.backlog = prepared.backlog
  self.backlog_last_key = prepared.backlog_last_key
  self.auto = prepared.auto
  self.pending_backend_audio = Some(prepared.audio)
  self.pending_confirm = None
}

///|
/// Idempotently reconcile external audio from the committed logical snapshot.
/// If a future backend raises, the pending snapshot remains set for retry.
pub fn Engine::reconcile_backends(self : Engine) -> Unit {
  match self.pending_backend_audio {
    None => ()
    Some(audio) => {
      restore_mixer_from_audio(audio)
      self.sync_mixer_prefs()
      self.pending_backend_audio = None
    }
  }
}

///|
fn Engine::restore_logical_state(
  self : Engine,
  state : EngineLogicalState,
) -> Unit raise SaveError {
  let prepared = self.prepare_logical_state(state)
  self.publish_prepared_logical_state(prepared)
  self.reconcile_backends()
}
