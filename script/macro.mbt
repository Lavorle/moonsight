///|
/// Errors raised during macro expansion.
pub(all) suberror MacroError {
  RecursionLimit(name~ : String, span~ : SourceSpan)
} derive(Debug, Eq)

///|
let macro_max_depth : Int = 64

///|
/// Expand macro invocations in scene (and macro) bodies.
/// Commands whose name matches a `- macro` are replaced with the macro body
/// after binding call args (positional by order, named by key) and substituting
/// parameter identifiers. Nested macros expand up to `macro_max_depth`.
pub fn expand_macros(unit : ScriptUnit) -> ScriptUnit raise MacroError {
  let macros = macro_table(unit.macros)
  let scenes = Array::new(capacity=unit.scenes.length())
  for scene in unit.scenes {
    let items = expand_stmt_list(scene.items, macros, depth=0)
    scenes.push({
      name: scene.name,
      parent: scene.parent,
      items,
      span: scene.span,
    })
  }
  // Keep original macro decls (bodies still contain unexpanded calls);
  // only scene items are expanded at use sites. Screens pass through unchanged.
  {
    file: unit.file,
    externs: unit.externs,
    macros: unit.macros,
    scenes,
    screens: unit.screens,
  }
}

///|
fn macro_table(macros : Array[MacroDecl]) -> Map[String, MacroDecl] {
  let table : Map[String, MacroDecl] = {}
  for m in macros {
    table[m.name] = m
  }
  table
}

///|
fn expand_stmt_list(
  stmts : Array[Stmt],
  macros : Map[String, MacroDecl],
  depth~ : Int,
) -> Array[Stmt] raise MacroError {
  let out : Array[Stmt] = []
  for stmt in stmts {
    let expanded = expand_stmt(stmt, macros, depth~)
    for s in expanded {
      out.push(s)
    }
  }
  out
}

///|
fn expand_stmt(
  stmt : Stmt,
  macros : Map[String, MacroDecl],
  depth~ : Int,
) -> Array[Stmt] raise MacroError {
  match stmt {
    Command(cmd~, args~, span~) =>
      match macros.get(cmd) {
        Some(m) => {
          if depth >= macro_max_depth {
            raise RecursionLimit(name=cmd, span~)
          }
          let bindings = bind_macro_args(m.params, args)
          let substituted = Array::new(capacity=m.body.length())
          for body_stmt in m.body {
            substituted.push(subst_stmt(body_stmt, bindings, call_span=span))
          }
          expand_stmt_list(substituted, macros, depth=depth + 1)
        }
        None => [stmt]
      }
    Dialogue(speaker~, text~, span~) => {
      // Inline macros that expand to a single command become InlineCommand;
      // multi-stmt macro bodies are left as the original inline (Phase 1).
      let new_text = Array::new(capacity=text.length())
      for part in text {
        new_text.push(expand_text_part(part, macros, depth~))
      }
      [Dialogue(speaker~, text=new_text, span~)]
    }
  }
}

///|
fn expand_text_part(
  part : TextPart,
  macros : Map[String, MacroDecl],
  depth~ : Int,
) -> TextPart raise MacroError {
  match part {
    Literal(_) => part
    InlineCommand(cmd~, args~) =>
      match macros.get(cmd) {
        None => part
        Some(m) => {
          if depth >= macro_max_depth {
            raise RecursionLimit(name=cmd, span={
              file: "<inline>",
              line: 0,
              col: 0,
              end_line: 0,
              end_col: 0,
            })
          }
          let bindings = bind_macro_args(m.params, args)
          let substituted = Array::new(capacity=m.body.length())
          let call_span : SourceSpan = {
            file: "<inline>",
            line: 0,
            col: 0,
            end_line: 0,
            end_col: 0,
          }
          for body_stmt in m.body {
            substituted.push(subst_stmt(body_stmt, bindings, call_span~))
          }
          let expanded = expand_stmt_list(substituted, macros, depth=depth + 1)
          // Collapse only when the expansion is a single command.
          guard expanded is [Command(cmd=ecmd, args=eargs, ..)] else { part }
          InlineCommand(cmd=ecmd, args=eargs)
        }
      }
  }
}

///|
fn bind_macro_args(
  params : Array[ParamDecl],
  args : Array[Arg],
) -> Map[String, Expr] {
  let bindings : Map[String, Expr] = {}
  // Named bindings first.
  for arg in args {
    match arg {
      Named(name~, e) => bindings[name] = e
      Positional(_) | Flag(_) => ()
    }
  }
  // Positional bind to next unbound parameter by declaration order.
  let mut pi = 0
  for arg in args {
    match arg {
      Positional(e) => {
        while pi < params.length() && bindings.contains(params[pi].name) {
          pi = pi + 1
        }
        if pi < params.length() {
          bindings[params[pi].name] = e
          pi = pi + 1
        }
      }
      Named(_) | Flag(_) => ()
    }
  }
  // Defaults for remaining unbound params.
  for p in params {
    if !bindings.contains(p.name) {
      match p.default {
        Some(d) => bindings[p.name] = d
        None => ()
      }
    }
  }
  bindings
}

///|
fn subst_stmt(
  stmt : Stmt,
  bindings : Map[String, Expr],
  call_span~ : SourceSpan,
) -> Stmt {
  match stmt {
    Command(cmd~, args~, ..) => {
      let new_args = Array::new(capacity=args.length())
      for a in args {
        new_args.push(subst_arg(a, bindings))
      }
      Command(cmd~, args=new_args, span=call_span)
    }
    Dialogue(speaker~, text~, ..) => {
      let new_text = Array::new(capacity=text.length())
      for part in text {
        new_text.push(subst_text_part(part, bindings))
      }
      Dialogue(speaker~, text=new_text, span=call_span)
    }
  }
}

///|
fn subst_text_part(part : TextPart, bindings : Map[String, Expr]) -> TextPart {
  match part {
    Literal(_) => part
    InlineCommand(cmd~, args~) => {
      let new_args = Array::new(capacity=args.length())
      for a in args {
        new_args.push(subst_arg(a, bindings))
      }
      InlineCommand(cmd~, args=new_args)
    }
  }
}

///|
fn subst_arg(arg : Arg, bindings : Map[String, Expr]) -> Arg {
  match arg {
    Positional(e) => Positional(subst_expr(e, bindings))
    Named(name~, e) => Named(name~, subst_expr(e, bindings))
    Flag(_) => arg
  }
}

///|
fn subst_expr(e : Expr, bindings : Map[String, Expr]) -> Expr {
  match e {
    Ident(name) =>
      match bindings.get(name) {
        Some(v) => v
        None => e
      }
    Int(_) | Float(_) | Bool(_) | Str(_) => e
  }
}
