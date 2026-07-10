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
} derive(Debug)

///|
/// Load IR into an engine with built-in host handlers.
///
/// Pass `director` to inject a full registry (e.g. `@std_commands.standard_registry()`).
pub fn Engine::from_ir(
  ir : @script.IrModule,
  entry~ : String,
  director? : Director,
) -> Engine {
  let stage = Stage::new()
  stage.scene = entry
  let dir = match director {
    Some(d) => d
    None => Director::with_builtins()
  }
  { vm: Vm::from_module(ir, entry~), director: dir, stage, auto: false }
}

///|
/// Apply player intent, run the VM until it waits or halts, then tick transitions.
///
/// `dt` is frame delta in seconds (default ≈ 1/60) for fade and typewriter pacing.
pub fn Engine::tick(
  self : Engine,
  intent : Intent,
  dt? : Double = 1.0 / 60.0,
) -> Unit {
  let effective = self.effective_intent(intent)
  self.apply_intent(effective)
  if self.vm.wait is Running {
    self.vm.run_until_wait(self.director, self.stage)
  }
  self.tick_transitions(dt)
  self.tick_typewriter(dt)
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
    ToggleAuto => self.auto = !self.auto
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
        None_ | Select(_) | OpenMenu | ToggleAuto => ()
      }
    Choose =>
      match intent {
        Select(index) => {
          self.stage.select_choice(index)
          match self.vm.choose_result_var {
            Some(name) => self.stage.set_var(name, Int(index))
            None => ()
          }
          self.stage.clear_choices()
          self.vm.choose_result_var = None
          self.vm.wait = Running
        }
        _ => ()
      }
    Running | Halted => ()
  }
}

///|
/// Ease `overlay_opacity` toward `fade_to` using `fade_duration` seconds per unit range.
fn Engine::tick_transitions(self : Engine, dt : Double) -> Unit {
  let target = self.stage.fade_to
  let cur = self.stage.overlay_opacity
  let diff = target - cur
  if diff == 0.0 {
    return
  }
  let duration = self.stage.fade_duration
  if duration <= 0.0 || dt <= 0.0 {
    self.stage.overlay_opacity = target
    return
  }
  // Unit opacity range takes `duration` seconds (matches from→to of size 1.0).
  let step = dt / duration
  if diff.abs() <= step {
    self.stage.overlay_opacity = target
  } else if diff > 0.0 {
    self.stage.overlay_opacity = cur + step
  } else {
    self.stage.overlay_opacity = cur - step
  }
}

///|
/// Gradual typewriter reveal when text is incomplete (chars/sec ≈ 40).
fn Engine::tick_typewriter(self : Engine, dt : Double) -> Unit {
  match self.stage.text {
    Some({ complete: false, .. }) => {
      let n = (40.0 * dt).to_int()
      let chars = if n < 1 { 1 } else { n }
      // Only advance when dt is positive; skip zero-dt frames.
      if dt > 0.0 {
        self.stage.reveal_chars(chars)
      }
    }
    _ => ()
  }
}
