///|
/// Errors raised during name resolution of a script unit.
pub(all) suberror ResolveError {
  UnknownCommand(name~ : String, span~ : SourceSpan)
  DuplicateScene(name~ : String, span~ : SourceSpan)
  UnknownParent(name~ : String, parent~ : String, span~ : SourceSpan)
} derive(Debug, Eq)

///|
/// Fully resolved compilation unit: extern table, scenes, and scene name index.
pub(all) struct ResolvedUnit {
  file : String
  externs : Map[String, ExternDecl]
  scenes : Array[SceneDecl]
  scene_table : Map[String, Int]
} derive(Debug)

///|
/// Minimal host extern stubs for the compile path.
/// Full runtime semantics live in `std_commands`; names must stay aligned.
pub fn builtin_externs() -> Array[ExternDecl] {
  let span = builtin_span()
  [
    stub_extern("text.begin", span~, params=[]),
    stub_extern("text.type", span~, params=[param("text")]),
    stub_extern("text.end", span~, params=[]),
    stub_extern("flow.jump", span~, params=[param("scene")]),
    stub_extern("flow.jump_if", span~, params=[]),
    stub_extern("flow.jump_if_not", span~, params=[]),
    stub_extern("flow.yield", span~, params=[]),
    stub_extern("flow.choice", span~, params=[]),
    stub_extern("flow.wait", span~, params=[param("time")]),
    stub_extern("layer.show", span~, params=[param("id")]),
    stub_extern("layer.hide", span~, params=[param("id")]),
    stub_extern("layer.move", span~, params=[param("id")]),
    stub_extern("layer.set", span~, params=[param("id")]),
    stub_extern("trans.fade", span~, params=[]),
    stub_extern("trans.dissolve", span~, params=[param("duration")]),
    stub_extern("var.set", span~, params=[param("name"), param("value")]),
    stub_extern("audio.bgm", span~, params=[param("resource")]),
    stub_extern("audio.se", span~, params=[param("resource")]),
    stub_extern("sys.save_hint", span~, params=[]),
    stub_extern("ui.show", span~, params=[param("name")]),
    stub_extern("ui.hide", span~, params=[]),
  ]
}

///|
/// Resolve a (typically macro-expanded) unit against file + builtin externs.
///
/// - Builds extern map: builtins first, file declarations override/add.
/// - Scene names must be unique; `parent` names must refer to a known scene.
/// - Every command / inline command must name a known extern (or remaining macro).
pub fn resolve_unit(
  unit : ScriptUnit,
  builtins : Array[ExternDecl],
) -> ResolvedUnit raise ResolveError {
  let externs : Map[String, ExternDecl] = {}
  for e in builtins {
    externs[e.name] = e
  }
  for e in unit.externs {
    externs[e.name] = e
  }

  let macros : Map[String, MacroDecl] = {}
  for m in unit.macros {
    macros[m.name] = m
  }

  let scene_table : Map[String, Int] = {}
  for i, scene in unit.scenes {
    if scene_table.contains(scene.name) {
      raise DuplicateScene(name=scene.name, span=scene.span)
    }
    scene_table[scene.name] = i
  }

  for scene in unit.scenes {
    match scene.parent {
      Some(parent) =>
        if !scene_table.contains(parent) {
          raise UnknownParent(name=scene.name, parent~, span=scene.span)
        }
      None => ()
    }
    for item in scene.items {
      resolve_stmt(item, externs, macros)
    }
  }

  { file: unit.file, externs, scenes: unit.scenes, scene_table }
}

///|
fn resolve_stmt(
  stmt : Stmt,
  externs : Map[String, ExternDecl],
  macros : Map[String, MacroDecl],
) -> Unit raise ResolveError {
  match stmt {
    Command(cmd~, span~, ..) => resolve_command_name(cmd, span, externs, macros)
    Dialogue(text~, span~, ..) =>
      for part in text {
        match part {
          Literal(_) => ()
          InlineCommand(cmd~, ..) =>
            resolve_command_name(cmd, span, externs, macros)
        }
      }
  }
}

///|
fn resolve_command_name(
  name : String,
  span : SourceSpan,
  externs : Map[String, ExternDecl],
  macros : Map[String, MacroDecl],
) -> Unit raise ResolveError {
  if externs.contains(name) || macros.contains(name) {
    return
  }
  raise UnknownCommand(name~, span~)
}

///|
fn builtin_span() -> SourceSpan {
  { file: "<builtin>", line: 0, col: 0, end_line: 0, end_col: 0 }
}

///|
fn stub_extern(
  name : String,
  span~ : SourceSpan,
  params~ : Array[ParamDecl],
) -> ExternDecl {
  { name, params, span }
}

///|
fn param(name : String) -> ParamDecl {
  { name, default: None }
}
