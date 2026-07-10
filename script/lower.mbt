///|
/// Lower a resolved unit to IR (one `IrScene` per source scene).
pub fn lower_unit(unit : ResolvedUnit) -> IrModule {
  let scenes : Map[String, IrScene] = {}
  for scene in unit.scenes {
    scenes[scene.name] = lower_scene(scene)
  }
  { scenes, entry: pick_entry(unit.scenes) }
}

///|
fn pick_entry(scenes : Array[SceneDecl]) -> String {
  for s in scenes {
    if s.name == "entrypoint" {
      return "entrypoint"
    }
  }
  match scenes {
    [first, ..] => first.name
    [] => "entrypoint"
  }
}

///|
fn lower_scene(scene : SceneDecl) -> IrScene {
  let ops : Array[IrOp] = []
  for item in scene.items {
    lower_stmt(item, ops)
  }
  // Ensure scenes always end cleanly for the VM.
  match ops {
    [.., Return] | [.., Yield] => ()
    _ => ops.push(Return)
  }
  { name: scene.name, ops }
}

///|
fn lower_stmt(stmt : Stmt, ops : Array[IrOp]) -> Unit {
  match stmt {
    Command(cmd~, args~, ..) => ops.push(Host(name=cmd, args=lower_args(args)))
    Dialogue(speaker~, text~, ..) => lower_dialogue(speaker, text, ops)
  }
}

///|
fn lower_dialogue(
  speaker : String?,
  text : Array[TextPart],
  ops : Array[IrOp],
) -> Unit {
  let begin_args : Array[IrValue] = match speaker {
    Some(s) => [Str(s)]
    None => [None_]
  }
  ops.push(Host(name="text.begin", args=begin_args))
  for part in text {
    match part {
      Literal(s) =>
        if s != "" {
          ops.push(Host(name="text.type", args=[Str(s)]))
        }
      InlineCommand(cmd~, args~) =>
        ops.push(Host(name=cmd, args=lower_args(args)))
    }
  }
  ops.push(Host(name="text.end", args=[]))
  ops.push(Yield)
}

///|
fn lower_args(args : Array[Arg]) -> Array[IrValue] {
  let out : Array[IrValue] = []
  for a in args {
    out.push(lower_arg(a))
  }
  out
}

///|
fn lower_arg(arg : Arg) -> IrValue {
  match arg {
    Positional(e) => lower_expr(e)
    Named(e, ..) => lower_expr(e)
    // Flag presence as named string so hosts can inspect which flag was set.
    Flag(name) => Str(name)
  }
}

///|
fn lower_expr(e : Expr) -> IrValue {
  match e {
    Int(n) => Int(n)
    Float(f) => Float(f)
    Bool(b) => Bool(b)
    Str(s) => Str(s)
    Ident(name) => Var(name)
  }
}
