///|
/// `flow.jump scene` — VM switches IrScene and resets ip.
pub fn cmd_flow_jump(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  ignore(stage)
  match args {
    [Str(scene), ..] => JumpScene(scene)
    _ => Error("flow.jump: expected scene Str")
  }
}

///|
/// `flow.wait time` — yield control (duration used later by engine frame).
pub fn cmd_flow_wait(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  ignore(stage)
  match args {
    [t, ..] =>
      match @runtime.value_as_double(t) {
        Some(_) => Yield
        None => Error("flow.wait: expected numeric time")
      }
    [] => Yield
  }
}

///|
/// `flow.yield` — explicit host-level yield.
pub fn cmd_flow_yield(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  ignore(stage)
  ignore(args)
  Yield
}

///|
/// `flow.choice` — stub host form; IR may also use dedicated Choose op.
///
/// With string args, presents them as choice options and yields.
pub fn cmd_flow_choice(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let options : Array[String] = []
  for a in args {
    match a {
      Str(s) => options.push(s)
      _ => ()
    }
  }
  if options.length() > 0 {
    stage.set_choices(options)
  }
  // Host-level choice pauses the interpreter; full Choose wait is IR Choose.
  Yield
}

///|
/// Runtime fallback for `@flow.jump_if` (normally lowered to `JumpIf` + `flow.jump`).
///
/// Forms: `[cond, scene]` (truthy) or `[lhs, rhs, scene]` (equality).
pub fn cmd_flow_jump_if(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  ignore(stage)
  match args {
    [lhs, rhs, Str(scene), ..] => if lhs == rhs { JumpScene(scene) } else { Ok }
    [cond, Str(scene), ..] => if cond.truthy() { JumpScene(scene) } else { Ok }
    _ => Error("flow.jump_if: expected cond [value] scene Str")
  }
}

///|
/// Runtime fallback for `@flow.jump_if_not` (normally lowered to `JumpIfNot` + `flow.jump`).
pub fn cmd_flow_jump_if_not(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  ignore(stage)
  match args {
    [lhs, rhs, Str(scene), ..] => if lhs == rhs { Ok } else { JumpScene(scene) }
    [cond, Str(scene), ..] => if cond.truthy() { Ok } else { JumpScene(scene) }
    _ => Error("flow.jump_if_not: expected cond [value] scene Str")
  }
}
