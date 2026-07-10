///|
/// Why the VM is paused (or finished).
pub(all) enum WaitKind {
  Running
  Yield
  Choose
  Halted
} derive(Debug, Eq)

///|
/// IR interpreter: control flow + host calls through Director.
pub(all) struct Vm {
  ir : @script.IrModule
  /// Linearized ops for the current scene (labels resolved).
  mut ops : Array[@script.IrOp]
  mut ip : Int
  mut scene : String
  mut stack : Array[Value]
  mut halted : Bool
  mut wait : WaitKind
  /// Variable name that receives the selected choice index (while waiting Choose).
  mut choose_result_var : String?
} derive(Debug)

///|
/// Headless engine: VM + Director + Stage with intent-driven ticks.
pub(all) struct Engine {
  mut vm : Vm
  director : Director
  mut stage : Stage
} derive(Debug)

///|
/// Create a VM positioned at `entry` scene.
pub fn Vm::from_module(ir : @script.IrModule, entry~ : String) -> Vm {
  let ops = load_scene_ops(ir, entry)
  {
    ir,
    ops,
    ip: 0,
    scene: entry,
    stack: [],
    halted: false,
    wait: Running,
    choose_result_var: None,
  }
}

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
  { vm: Vm::from_module(ir, entry~), director: dir, stage }
}

///|
/// Apply player intent, then run the VM until it waits or halts.
pub fn Engine::tick(self : Engine, intent : Intent) -> Unit {
  self.apply_intent(intent)
  if self.vm.wait is Running {
    self.vm.run_until_wait(self.director, self.stage)
  }
}

///|
fn Engine::apply_intent(self : Engine, intent : Intent) -> Unit {
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
/// Execute ops until Yield / Choose / Halted or instruction budget exhausted.
pub fn Vm::run_until_wait(
  self : Vm,
  director : Director,
  stage : Stage,
  budget? : Int = 10000,
) -> Unit {
  if self.halted {
    self.wait = Halted
    return
  }
  self.wait = Running
  for _ in 0..<budget {
    if self.wait is (Yield | Choose | Halted) {
      break
    }
    if self.ip < 0 || self.ip >= self.ops.length() {
      self.halted = true
      self.wait = Halted
      break
    }
    let op = self.ops[self.ip]
    match op {
      Nop | Label(_) =>
        // Labels should already be stripped by linearize; skip if present.
        self.ip = self.ip + 1
      Host(name~, args~) => {
        let values = resolve_args(args, stage)
        let result = director.call(name, stage, values)
        self.ip = self.ip + 1
        match result {
          Ok => ()
          Yield => self.wait = Yield
          JumpScene(scene) =>
            // jump_scene resets ip/ops; ignore the pre-increment above.
            self.jump_scene(scene, stage)
          Error(msg) => {
            // Soft-fail: halt so tests can observe; no panic in Phase 1 kernel.
            ignore(msg)
            self.halted = true
            self.wait = Halted
          }
        }
      }
      Jump(label~) => self.ip = label
      JumpIf(cond~, label~) =>
        if resolve_ir_value(cond, stage).truthy() {
          self.ip = label
        } else {
          self.ip = self.ip + 1
        }
      JumpIfNot(cond~, label~) =>
        if resolve_ir_value(cond, stage).truthy() {
          self.ip = self.ip + 1
        } else {
          self.ip = label
        }
      Yield => {
        self.ip = self.ip + 1
        self.wait = Yield
      }
      Choose(options~, result_var~) => {
        stage.set_choices(options)
        self.choose_result_var = Some(result_var)
        self.ip = self.ip + 1
        self.wait = Choose
      }
      Return => {
        self.ip = self.ip + 1
        self.halted = true
        self.wait = Halted
      }
    }
  }
}

///|
/// Switch to another scene by name (used later by flow.jump / JumpScene).
pub fn Vm::jump_scene(self : Vm, name : String, stage : Stage) -> Unit {
  self.ops = load_scene_ops(self.ir, name)
  self.ip = 0
  self.scene = name
  stage.scene = name
  self.halted = false
  self.wait = Running
  self.choose_result_var = None
}

///|
fn load_scene_ops(ir : @script.IrModule, name : String) -> Array[@script.IrOp] {
  match ir.scenes.get(name) {
    Some(scene) => @script.linearize_ops(scene.ops)
    None => []
  }
}

///|
fn resolve_args(args : Array[@script.IrValue], stage : Stage) -> Array[Value] {
  let out : Array[Value] = []
  for v in args {
    out.push(resolve_ir_value(v, stage))
  }
  out
}

///|
fn resolve_ir_value(v : @script.IrValue, stage : Stage) -> Value {
  match v {
    Int(n) => Int(n)
    Float(f) => Float(f)
    Bool(b) => Bool(b)
    Str(s) => Str(s)
    Var(name) => stage.get_var(name)
    None_ => None_
  }
}
