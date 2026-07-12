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
/// Lower author-ID directives together with executable IR. Grammar:
/// `@meta.id "operation.id" presentation="presentation.id" choices="a,b"`
/// immediately precedes the dialogue, choice, or host operation it identifies.
/// The directive is metadata only and is removed from executable operations.
pub fn lower_unit_with_ids(
  unit : ResolvedUnit,
) -> IdentifiedIrModule raise AuthorIdError {
  let stable_operations : Array[StableOperationId] = []
  let stripped_scenes : Array[SceneDecl] = []
  for scene in unit.scenes {
    let items : Array[Stmt] = []
    let mut pending : (AuthorId, AuthorId?, Array[AuthorId], SourceSpan)? = None
    let mut ordinal = 0
    for item in scene.items {
      match item {
        Command(cmd="meta.id", args~, span~) =>
          pending = Some(parse_id_directive(args, span))
        _ => {
          match pending {
            Some((operation_id, presentation_id, choice_ids, span)) => {
              stable_operations.push({
                operation_id,
                presentation_id,
                choice_ids,
                scene: scene.name,
                ordinal,
                kind: stable_kind(item),
                span,
              })
              pending = None
            }
            None => ()
          }
          items.push(item)
          ordinal = ordinal + 1
        }
      }
    }
    stripped_scenes.push({
      name: scene.name,
      parent: scene.parent,
      items,
      span: scene.span,
    })
  }
  let stripped : ResolvedUnit = {
    file: unit.file,
    externs: unit.externs,
    scenes: stripped_scenes,
    scene_table: unit.scene_table,
  }
  { ir: lower_unit(stripped), stable_operations }
}

///|
fn parse_id_directive(
  args : Array[Arg],
  span : SourceSpan,
) -> (AuthorId, AuthorId?, Array[AuthorId], SourceSpan) raise AuthorIdError {
  let mut operation = ""
  let mut presentation : String? = None
  let choices : Array[AuthorId] = []
  for arg in args {
    match arg {
      Positional(Str(id)) | Positional(Ident(id)) => operation = id
      Named(name="presentation", Str(id))
      | Named(name="presentation", Ident(id)) => presentation = Some(id)
      Named(name="choices", Str(ids)) =>
        for id in ids.split(",") {
          choices.push(parse_author_id(id.to_owned()))
        }
      _ => ()
    }
  }
  let operation_id = parse_author_id(operation)
  let presentation_id = match presentation {
    Some(id) => Some(parse_author_id(id))
    None => None
  }
  (operation_id, presentation_id, choices, span)
}

///|
fn stable_kind(stmt : Stmt) -> StablePresentationKind {
  match stmt {
    Dialogue(..) => Dialogue
    Command(cmd="flow.choice", ..) => Choice
    Command(..) => Operation
  }
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
    match a {
      Positional(e) => out.push(lower_expr(e))
      Named(name~, e) => {
        out.push(Str("#:\{name}"))
        out.push(lower_expr(e))
      }
      // Flag presence as named string so hosts can inspect which flag was set.
      Flag(name) => out.push(Str(name))
    }
  }
  out
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
