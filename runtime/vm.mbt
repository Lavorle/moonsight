///|
/// Why the VM is paused (or finished).
pub(all) enum WaitKind {
  Running
  Yield
  Choose
  Halted
} derive(Debug, Eq, ToJson, FromJson)

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
  /// Last soft host/VM error message (missing scene, host Error, …).
  mut last_error : String?
} derive(Debug)

///|
/// Create a VM positioned at `entry` scene.
pub fn Vm::from_module(ir : @script.IrModule, entry~ : String) -> Vm {
  match load_scene_ops(ir, entry) {
    Some(ops) =>
      {
        ir,
        ops,
        ip: 0,
        scene: entry,
        stack: [],
        halted: false,
        wait: Running,
        choose_result_var: None,
        last_error: None,
      }
    None =>
      {
        ir,
        ops: [],
        ip: 0,
        scene: entry,
        stack: [],
        halted: true,
        wait: Halted,
        choose_result_var: None,
        last_error: Some("unknown scene: \{entry}"),
      }
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
            self.last_error = Some(msg)
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
  match load_scene_ops(self.ir, name) {
    Some(ops) => {
      self.ops = ops
      self.ip = 0
      self.scene = name
      stage.scene = name
      self.halted = false
      self.wait = Running
      self.choose_result_var = None
      self.last_error = None
    }
    None => {
      self.last_error = Some("unknown scene: \{name}")
      self.halted = true
      self.wait = Halted
    }
  }
}

///|
fn load_scene_ops(ir : @script.IrModule, name : String) -> Array[@script.IrOp]? {
  match ir.scenes.get(name) {
    Some(scene) => Some(@script.linearize_ops(scene.ops))
    None => None
  }
}

///|
/// Resolve host-call arguments only.
/// Unbound identifiers become string keywords (`kind=background` → Str("background"))
/// so bare named keywords work; bound vars still pass their runtime value.
fn resolve_args(args : Array[@script.IrValue], stage : Stage) -> Array[Value] {
  let out : Array[Value] = []
  for v in args {
    out.push(resolve_host_arg(v, stage))
  }
  out
}

///|
/// Host-arg resolution: unbound `Var` → `Str(name)` keyword; bound → actual value.
fn resolve_host_arg(v : @script.IrValue, stage : Stage) -> Value {
  match v {
    Int(n) => Int(n)
    Float(f) => Float(f)
    Bool(b) => Bool(b)
    Str(s) => Str(s)
    Var(name) =>
      match stage.vars.get(name) {
        Some(val) => val
        None => Str(name)
      }
    None_ => None_
  }
}

///|
/// Condition/value resolution for JumpIf etc.: unbound vars → `None_`.
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
