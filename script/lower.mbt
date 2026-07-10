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
  let label_id : Ref[Int] = Ref(0)
  for item in scene.items {
    lower_stmt(item, ops, label_id)
  }
  // Ensure scenes always end cleanly for the VM.
  match ops {
    [.., Return] | [.., Yield] => ()
    _ => ops.push(Return)
  }
  { name: scene.name, ops }
}

///|
fn lower_stmt(stmt : Stmt, ops : Array[IrOp], label_id : Ref[Int]) -> Unit {
  match stmt {
    Command(cmd~, args~, ..) =>
      if cmd == "flow.choice" {
        lower_choice(args, ops)
      } else if cmd == "flow.jump_if" {
        lower_jump_if(args, ops, label_id, invert=false)
      } else if cmd == "flow.jump_if_not" {
        lower_jump_if(args, ops, label_id, invert=true)
      } else {
        ops.push(Host(name=cmd, args=lower_args(args)))
      }
    Dialogue(speaker~, text~, ..) => lower_dialogue(speaker, text, ops)
  }
}

///|
fn next_label(label_id : Ref[Int]) -> Int {
  let id = label_id.val
  label_id.val = id + 1
  id
}

///|
/// Lower `@flow.jump_if` / `@flow.jump_if_not` to `JumpIf`/`JumpIfNot` + scene jump.
///
/// Forms:
/// - `@flow.jump_if <cond> "scene"` — jump when `cond` is truthy
/// - `@flow.jump_if <lhs> <rhs> "scene"` — jump when `lhs == rhs` (via temp + `var.eq`)
/// - `@flow.jump_if_not …` — inverted condition
fn lower_jump_if(
  args : Array[Arg],
  ops : Array[IrOp],
  label_id : Ref[Int],
  invert~ : Bool,
) -> Unit {
  // Parser treats `name value` as Named(name, value). Flatten to:
  //   Named(n, e) → Var(n), lower(e)   so `act 0 "talk"` → act, 0, "talk"
  //   Positional(e) → lower(e)
  let pos : Array[IrValue] = []
  for a in args {
    match a {
      Named(name~, e) => {
        pos.push(Var(name))
        pos.push(lower_expr(e))
      }
      Positional(e) => pos.push(lower_expr(e))
      Flag(_) => ()
    }
  }
  match pos {
    [cond, scene_v] => {
      let scene = scene_name_from_value(scene_v)
      let skip = next_label(label_id)
      if invert {
        // jump_if_not: scene jump when cond is falsey
        ops.push(JumpIf(cond~, label=skip))
      } else {
        ops.push(JumpIfNot(cond~, label=skip))
      }
      ops.push(Host(name="flow.jump", args=[Str(scene)]))
      ops.push(Label(skip))
    }
    [lhs, rhs, scene_v] => {
      let scene = scene_name_from_value(scene_v)
      let skip = next_label(label_id)
      let tmp = "__eq_\{skip}"
      ops.push(Host(name="var.eq", args=[Str(tmp), lhs, rhs]))
      if invert {
        ops.push(JumpIf(cond=Var(tmp), label=skip))
      } else {
        ops.push(JumpIfNot(cond=Var(tmp), label=skip))
      }
      ops.push(Host(name="flow.jump", args=[Str(scene)]))
      ops.push(Label(skip))
    }
    _ =>
      // Malformed args: leave a host call so the runtime can soft-error.
      ops.push(
        Host(
          name=if invert { "flow.jump_if_not" } else { "flow.jump_if" },
          args=pos,
        ),
      )
  }
}

///|
/// Scene name from a lowered positional (string literal or bare ident → Var).
fn scene_name_from_value(v : IrValue) -> String {
  match v {
    Str(s) | Var(s) => s
    _ => "_"
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
