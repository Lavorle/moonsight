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
    Command(cmd~, args~, ..) =>
      if cmd == "flow.choice" {
        lower_choice(args, ops)
      } else {
        ops.push(Host(name=cmd, args=lower_args(args)))
      }
    Dialogue(speaker~, text~, ..) => lower_dialogue(speaker, text, ops)
  }
}

///|
/// Lower `@flow.choice` to `IrOp::Choose`.
///
/// Supported forms:
/// - `@flow.choice "Yes" "No" --result c`
/// - `@flow.choice result="c" "Yes" "No"`
/// - `@flow.choice "Yes" "No" result=c`
///
/// Positional string/ident args become option labels. Missing result defaults to `"_"`.
fn lower_choice(args : Array[Arg], ops : Array[IrOp]) -> Unit {
  let options : Array[String] = []
  let mut result_var = "_"
  let mut i = 0
  while i < args.length() {
    match args[i] {
      Named(name="result", e) => result_var = result_name_from_expr(e)
      Flag("result") => {
        i = i + 1
        if i < args.length() {
          match args[i] {
            Positional(e) | Named(e, ..) =>
              result_var = result_name_from_expr(e)
            Flag(_) => ()
          }
        }
      }
      Positional(Str(s)) | Positional(Ident(s)) => options.push(s)
      Named(_, ..) | Flag(_) | Positional(_) => ()
    }
    i = i + 1
  }
  ops.push(Choose(options~, result_var~))
}

///|
fn result_name_from_expr(e : Expr) -> String {
  match e {
    Ident(s) | Str(s) => s
    _ => "_"
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
