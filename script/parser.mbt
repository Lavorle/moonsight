///|
pub(all) suberror ParseError {
  ParseError(span~ : SourceSpan, message~ : String)
} derive(Debug, Eq)

///|
/// Parse full source into a `ScriptUnit`. Raises `ParseError` on syntax errors.
pub fn parse_source(
  src : String,
  file~ : String,
) -> ScriptUnit raise ParseError {
  let tokens = lex(src, file~)
  parse_tokens(tokens, file~)
}

///|
priv struct Parser {
  tokens : Array[Token]
  file : String
  mut pos : Int
}

///|
fn Parser::new(tokens : Array[Token], file~ : String) -> Parser {
  { tokens, file, pos: 0 }
}

///|
fn Parser::peek(self : Parser) -> Token {
  match self.tokens.get(self.pos) {
    Some(t) => t
    None => {
      // Should not happen if lexer always emits Eof
      let span = span_at(self.file, 1, 1)
      { kind: Eof, span }
    }
  }
}

///|
fn Parser::at_eof(self : Parser) -> Bool {
  self.peek().kind is Eof
}

///|
fn Parser::advance(self : Parser) -> Token {
  let t = self.peek()
  if !(t.kind is Eof) {
    self.pos += 1
  }
  t
}

///|
fn Parser::raise_here(self : Parser, message : String) -> Unit raise ParseError {
  raise ParseError::ParseError(span=self.peek().span, message~)
}

///|
fn Parser::raise_at(
  _self : Parser,
  span : SourceSpan,
  message : String,
) -> Unit raise ParseError {
  raise ParseError::ParseError(span~, message~)
}

///|
fn Parser::skip_newlines(self : Parser) -> Unit {
  while self.peek().kind is Newline {
    self.advance() |> ignore
  }
}

///|
fn parse_tokens(
  tokens : Array[Token],
  file~ : String,
) -> ScriptUnit raise ParseError {
  let p = Parser::new(tokens, file~)
  let externs : Array[ExternDecl] = []
  let macros : Array[MacroDecl] = []
  let scenes : Array[SceneDecl] = []
  p.skip_newlines()
  while !p.at_eof() {
    match p.peek().kind {
      Minus => parse_top_decl(p, externs, macros, scenes)
      Error(msg) => p.raise_here(msg)
      _ =>
        p.raise_here(
          "expected top-level declaration starting with `-` (extern/macro/scene)",
        )
    }
    p.skip_newlines()
  }
  { file, externs, macros, scenes }
}

///|
fn parse_top_decl(
  p : Parser,
  externs : Array[ExternDecl],
  macros : Array[MacroDecl],
  scenes : Array[SceneDecl],
) -> Unit raise ParseError {
  let minus = p.advance() // Minus
  let kw_tok = p.advance()
  match kw_tok.kind {
    Ident("extern") => {
      let decl = parse_extern_rest(p, minus.span)
      externs.push(decl)
    }
    Ident("macro") => {
      let decl = parse_macro_rest(p, minus.span)
      macros.push(decl)
    }
    Ident("scene") => {
      let decl = parse_scene_rest(p, minus.span)
      scenes.push(decl)
    }
    Ident(other) =>
      p.raise_at(
        kw_tok.span,
        "unknown declaration `\{other}` (expected extern, macro, or scene)",
      )
    Error(msg) => p.raise_at(kw_tok.span, msg)
    _ => p.raise_at(kw_tok.span, "expected declaration keyword after `-`")
  }
}

///|
fn parse_extern_rest(
  p : Parser,
  start : SourceSpan,
) -> ExternDecl raise ParseError {
  let name_tok = p.advance()
  let name = expect_ident(p, name_tok, "expected extern name")
  let params = parse_param_list(p)
  let end_span = p.peek().span
  expect_line_end(p)
  { name, params, span: merge_span(start, end_span) }
}

///|
fn parse_macro_rest(
  p : Parser,
  start : SourceSpan,
) -> MacroDecl raise ParseError {
  let name_tok = p.advance()
  let name = expect_ident(p, name_tok, "expected macro name")
  let params = parse_param_list(p)
  expect_line_end(p)
  let body = parse_body(p)
  let end_span = match body.last() {
    Some(stmt) => stmt_span(stmt)
    None => start
  }
  { name, params, body, span: merge_span(start, end_span) }
}

///|
fn parse_scene_rest(
  p : Parser,
  start : SourceSpan,
) -> SceneDecl raise ParseError {
  let name_tok = p.advance()
  let name = match name_tok.kind {
    StringLit(s) => s
    Ident(s) => s
    Error(msg) => {
      p.raise_at(name_tok.span, msg)
      panic() // unreachable
    }
    _ => {
      p.raise_at(name_tok.span, "expected scene name string")
      panic()
    }
  }
  let mut parent : String? = None
  if p.peek().kind is Ident("inherit") {
    p.advance() |> ignore
    let parent_tok = p.advance()
    parent = Some(
      match parent_tok.kind {
        StringLit(s) => s
        Ident(s) => s
        Error(msg) => {
          p.raise_at(parent_tok.span, msg)
          panic()
        }
        _ => {
          p.raise_at(
            parent_tok.span,
            "expected parent scene name after `inherit`",
          )
          panic()
        }
      },
    )
  }
  expect_line_end(p)
  let items = parse_body(p)
  let end_span = match items.last() {
    Some(stmt) => stmt_span(stmt)
    None => start
  }
  { name, parent, items, span: merge_span(start, end_span) }
}

///|
/// Body lines until the next top-level `-` declaration or EOF. Blank lines skipped.
fn parse_body(p : Parser) -> Array[Stmt] raise ParseError {
  let items : Array[Stmt] = []
  for ;; {
    p.skip_newlines()
    if p.at_eof() {
      break
    }
    // Next top-level declaration ends this body
    if p.peek().kind is Minus {
      break
    }
    items.push(parse_stmt_line(p))
  }
  items
}

///|
fn parse_stmt_line(p : Parser) -> Stmt raise ParseError {
  match p.peek().kind {
    At => parse_command_line(p)
    DialogueSpeaker(_) => parse_dialogue_line(p)
    Error(msg) => {
      p.raise_here(msg)
      panic()
    }
    _ => {
      p.raise_here("expected command (`@...`) or dialogue (`speaker:text`)")
      panic()
    }
  }
}

///|
fn parse_command_line(p : Parser) -> Stmt raise ParseError {
  let at = p.advance() // At
  let name_tok = p.advance()
  let cmd = expect_ident(p, name_tok, "expected command name after `@`")
  let args = parse_arg_list(p)
  let end_span = p.peek().span
  expect_line_end(p)
  Command(cmd~, args~, span=merge_span(at.span, end_span))
}

///|
fn parse_dialogue_line(p : Parser) -> Stmt raise ParseError {
  let spk_tok = p.advance()
  let speaker = match spk_tok.kind {
    DialogueSpeaker(s) => Some(s)
    _ => None
  }
  let text_tok = p.advance()
  let raw = match text_tok.kind {
    DialogueText(t) => t
    Error(msg) => {
      p.raise_at(text_tok.span, msg)
      panic()
    }
    _ => {
      p.raise_at(text_tok.span, "expected dialogue text")
      panic()
    }
  }
  let text = parse_dialogue_text(raw, text_tok.span, p.file)
  expect_line_end(p)
  Dialogue(speaker~, text~, span=merge_span(spk_tok.span, text_tok.span))
}

///|
/// Split dialogue text into literals and `[cmd args...]` inline commands.
fn parse_dialogue_text(
  raw : String,
  span : SourceSpan,
  file : String,
) -> Array[TextPart] raise ParseError {
  let parts : Array[TextPart] = []
  let mut i = 0
  let len = raw.length()
  let mut lit_start = 0
  while i < len {
    match raw.get_char(i) {
      Some('[') => {
        // flush literal
        if i > lit_start {
          let lit = raw[lit_start:i].to_owned()
          if lit != "" {
            parts.push(Literal(lit))
          }
        }
        // find matching ]
        let content_start = i + 1
        let mut j = content_start
        let mut found = false
        while j < len {
          if raw.get_char(j) is Some(']') {
            found = true
            break
          }
          // advance by code units carefully
          match raw.get_char(j) {
            Some(c) => j += c.utf16_len()
            None => break
          }
        }
        if !found {
          raise ParseError::ParseError(
            span~,
            message="unclosed inline command `[...` in dialogue",
          )
        }
        let content = raw[content_start:j].to_owned()
        parts.push(parse_inline_command(content, span, file))
        // skip ]
        i = j + 1
        lit_start = i
      }
      Some(c) => i += c.utf16_len()
      None => break
    }
  }
  if lit_start < len {
    let lit = raw[lit_start:len].to_owned()
    if lit != "" {
      parts.push(Literal(lit))
    }
  }
  if parts.is_empty() {
    parts.push(Literal(""))
  }
  parts
}

///|
fn parse_inline_command(
  content : String,
  span : SourceSpan,
  file : String,
) -> TextPart raise ParseError {
  // Re-lex as a synthetic command line so flag/named-arg rules match top-level.
  let synthetic = "@" + content.trim().to_owned() + "\n"
  let tokens = lex(synthetic, file~)
  let p = Parser::new(tokens, file~)
  match p.advance().kind {
    At => ()
    _ => p.raise_at(span, "invalid inline command")
  }
  let name_tok = p.advance()
  let cmd = match name_tok.kind {
    Ident(s) => s
    Error(msg) => {
      raise ParseError::ParseError(span~, message=msg)
      panic()
    }
    _ => {
      raise ParseError::ParseError(
        span~,
        message="expected command name in inline `[...]`",
      )
      panic()
    }
  }
  let args = parse_arg_list(p)
  // rest should be newline/eof
  InlineCommand(cmd~, args~)
}

///|
fn parse_param_list(p : Parser) -> Array[ParamDecl] raise ParseError {
  let params : Array[ParamDecl] = []
  for ;; {
    match p.peek().kind {
      Newline | Eof => break
      Ident(name) => {
        p.advance() |> ignore
        // Defaults are only literals (and unary-minus numbers). Bare Ident is
        // the next param name, not a default expression.
        let default = match try_peek_param_default(p) {
          Some(_) => Some(parse_expr(p))
          None => None
        }
        params.push({ name, default })
      }
      Error(msg) => p.raise_here(msg)
      _ =>
        // e.g. unexpected token on header line
        p.raise_here("expected parameter name")
    }
  }
  params
}

///|
/// Peek for a param default value. Unlike `try_peek_expr`, bare `Ident` is not
/// a default (it starts the next parameter).
fn try_peek_param_default(p : Parser) -> Unit? {
  match p.peek().kind {
    IntLit(_) | FloatLit(_) | BoolLit(_) | StringLit(_) => Some(())
    Minus =>
      match p.tokens.get(p.pos + 1) {
        Some({ kind: IntLit(_) | FloatLit(_), .. }) => Some(())
        _ => None
      }
    _ => None
  }
}

///|
fn parse_arg_list(p : Parser) -> Array[Arg] raise ParseError {
  let args : Array[Arg] = []
  for ;; {
    match p.peek().kind {
      Newline | Eof => break
      Flag(name) => {
        p.advance() |> ignore
        args.push(Flag(name))
      }
      Ident(name) => {
        // Named if a value token follows; otherwise positional Ident.
        p.advance() |> ignore
        if try_peek_expr(p) is Some(_) {
          let value = parse_expr(p)
          args.push(Named(name~, value))
        } else {
          args.push(Positional(Ident(name)))
        }
      }
      Error(msg) => p.raise_here(msg)
      Minus | IntLit(_) | FloatLit(_) | BoolLit(_) | StringLit(_) => {
        let value = parse_expr(p)
        args.push(Positional(value))
      }
      _ => p.raise_here("unexpected token in argument list")
    }
  }
  args
}

///|
fn try_peek_expr(p : Parser) -> Unit? {
  match p.peek().kind {
    IntLit(_) | FloatLit(_) | BoolLit(_) | StringLit(_) | Ident(_) => Some(())
    Minus =>
      // negative number: Minus followed by IntLit/FloatLit
      match p.tokens.get(p.pos + 1) {
        Some({ kind: IntLit(_) | FloatLit(_), .. }) => Some(())
        _ => None
      }
    _ => None
  }
}

///|
fn parse_expr(p : Parser) -> Expr raise ParseError {
  let t = p.advance()
  match t.kind {
    IntLit(n) => Int(n)
    FloatLit(f) => Float(f)
    BoolLit(b) => Bool(b)
    StringLit(s) => Str(s)
    Ident(s) => Ident(s)
    Minus => {
      let ntok = p.advance()
      match ntok.kind {
        IntLit(n) => Int(-n)
        FloatLit(f) => Float(0.0 - f)
        Error(msg) => {
          p.raise_at(ntok.span, msg)
          panic()
        }
        _ => {
          p.raise_at(ntok.span, "expected number after `-`")
          panic()
        }
      }
    }
    Error(msg) => {
      p.raise_at(t.span, msg)
      panic()
    }
    _ => {
      p.raise_at(t.span, "expected expression")
      panic()
    }
  }
}

///|
fn expect_ident(
  p : Parser,
  tok : Token,
  message : String,
) -> String raise ParseError {
  match tok.kind {
    Ident(s) => s
    Error(msg) => {
      p.raise_at(tok.span, msg)
      panic()
    }
    _ => {
      p.raise_at(tok.span, message)
      panic()
    }
  }
}

///|
fn expect_line_end(p : Parser) -> Unit raise ParseError {
  match p.peek().kind {
    Newline => p.advance() |> ignore
    Eof => ()
    Error(msg) => p.raise_here(msg)
    _ => p.raise_here("expected end of line")
  }
}

///|
fn stmt_span(stmt : Stmt) -> SourceSpan {
  match stmt {
    Command(span~, ..) => span
    Dialogue(span~, ..) => span
  }
}

///|
fn merge_span(a : SourceSpan, b : SourceSpan) -> SourceSpan {
  {
    file: a.file,
    line: a.line,
    col: a.col,
    end_line: b.end_line,
    end_col: b.end_col,
  }
}
