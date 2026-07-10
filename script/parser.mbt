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
  // Keep raw lines: the lexer strips leading spaces, so indent-based
  // `- screen` bodies are parsed from source lines (see parse_screen_body).
  let lines : Array[String] = []
  for line in src.split("\n") {
    lines.push(line.to_owned())
  }
  parse_tokens(tokens, lines, file~)
}

///|
priv struct Parser {
  tokens : Array[Token]
  lines : Array[String]
  file : String
  mut pos : Int
}

///|
fn Parser::new(
  tokens : Array[Token],
  lines : Array[String],
  file~ : String,
) -> Parser {
  { tokens, lines, file, pos: 0 }
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
  lines : Array[String],
  file~ : String,
) -> ScriptUnit raise ParseError {
  let p = Parser::new(tokens, lines, file~)
  let externs : Array[ExternDecl] = []
  let macros : Array[MacroDecl] = []
  let scenes : Array[SceneDecl] = []
  let screens : Array[ScreenDecl] = []
  p.skip_newlines()
  while !p.at_eof() {
    match p.peek().kind {
      Minus => parse_top_decl(p, externs, macros, scenes, screens)
      Error(msg) => p.raise_here(msg)
      _ =>
        p.raise_here(
          "expected top-level declaration starting with `-` (extern/macro/scene/screen)",
        )
    }
    p.skip_newlines()
  }
  { file, externs, macros, scenes, screens }
}

///|
fn parse_top_decl(
  p : Parser,
  externs : Array[ExternDecl],
  macros : Array[MacroDecl],
  scenes : Array[SceneDecl],
  screens : Array[ScreenDecl],
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
    Ident("screen") => {
      let decl = parse_screen_rest(p, minus.span)
      screens.push(decl)
    }
    Ident(other) =>
      p.raise_at(
        kw_tok.span,
        "unknown declaration `\{other}` (expected extern, macro, scene, or screen)",
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
  let p = Parser::new(tokens, [], file~)
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

// ---------------------------------------------------------------------------
// Screen DSL: indent-based body from raw source lines
// Approach: lexer strips leading spaces, so screen bodies are scanned from
// raw lines (2 spaces per indent level). After the `- screen "name"` header
// (token stream), parse_screen_body walks lines until the next top-level `-`
// decl; the token cursor is then advanced past consumed body lines.
// ---------------------------------------------------------------------------

///|
fn parse_screen_rest(
  p : Parser,
  start : SourceSpan,
) -> ScreenDecl raise ParseError {
  let name_tok = p.advance()
  let name = match name_tok.kind {
    StringLit(s) => s
    Ident(s) => s
    Error(msg) => {
      p.raise_at(name_tok.span, msg)
      panic()
    }
    _ => {
      p.raise_at(name_tok.span, "expected screen name string")
      panic()
    }
  }
  expect_line_end(p)
  // Body starts on the physical line after the header (1-based line → 0-based idx).
  let body_start_idx = start.line
  let (root_children, next_idx) = parse_screen_body(
    p.lines,
    body_start_idx,
    p.file,
  )
  // Skip tokens belonging to consumed body lines (1-based line < next_idx+1).
  while !p.at_eof() && p.peek().span.line < next_idx + 1 {
    p.advance() |> ignore
  }
  let end_span = match root_children.last() {
    Some(node) => screen_node_span(node)
    None => name_tok.span
  }
  { name, root_children, span: merge_span(start, end_span) }
}

///|
/// Parse root children of a screen body starting at `start_idx` (0-based).
/// Returns `(children, next_idx)` where `next_idx` is the first unconsumed line.
fn parse_screen_body(
  lines : Array[String],
  start_idx : Int,
  file : String,
) -> (Array[ScreenNode], Int) raise ParseError {
  parse_screen_children(lines, start_idx, parent_indent=0, file~)
}

///|
fn parse_screen_children(
  lines : Array[String],
  start_idx : Int,
  parent_indent~ : Int,
  file~ : String,
) -> (Array[ScreenNode], Int) raise ParseError {
  let children : Array[ScreenNode] = []
  let mut idx = start_idx
  while idx < lines.length() {
    let line = lines[idx]
    if screen_line_ignored(line) {
      idx = idx + 1
      continue
    }
    let indent = screen_leading_spaces(line)
    if indent == 0 && screen_is_top_decl(line) {
      break
    }
    if indent <= parent_indent {
      break
    }
    let (node, next) = parse_screen_node(lines, idx, indent, file)
    children.push(node)
    idx = next
  }
  (children, idx)
}

///|
fn parse_screen_node(
  lines : Array[String],
  idx : Int,
  indent : Int,
  file : String,
) -> (ScreenNode, Int) raise ParseError {
  let line = lines[idx]
  let line_no = idx + 1
  let span = make_span(file, line_no, indent + 1, line.length() + 1)
  let sc = ScreenLine::new(line, file~, line_no~, pos=indent)
  sc.skip_spaces()
  let kw = sc.expect_ident("expected screen widget (vbox/hbox/fixed/text/button)")
  match kw {
    "vbox" => parse_screen_box(sc, lines, idx, indent, file, is_hbox=false, span~)
    "hbox" => parse_screen_box(sc, lines, idx, indent, file, is_hbox=true, span~)
    "fixed" => parse_screen_fixed(sc, lines, idx, indent, file, span~)
    "text" => {
      let src = parse_screen_text_src(sc)
      sc.expect_eol("unexpected trailing tokens after text")
      (Text(src~, span~), idx + 1)
    }
    "button" => {
      let label = sc.expect_string("expected button label string")
      sc.skip_spaces()
      let action_name = sc.expect_ident("expected `action=` on button")
      if action_name != "action" {
        sc.fail_here("expected `action=` after button label")
      }
      sc.expect_char('=', "expected `=` after action")
      sc.skip_spaces()
      let action = parse_screen_action(sc)
      sc.expect_eol("unexpected trailing tokens after button")
      (Button(label~, action~, span~), idx + 1)
    }
    other => {
      sc.fail_here("unknown screen widget `\{other}`")
      panic()
    }
  }
}

///|
fn parse_screen_box(
  sc : ScreenLine,
  lines : Array[String],
  idx : Int,
  indent : Int,
  file : String,
  is_hbox~ : Bool,
  span~ : SourceSpan,
) -> (ScreenNode, Int) raise ParseError {
  let mut x : Double? = None
  let mut y : Double? = None
  sc.skip_spaces()
  while sc.peek() is Some(c) && is_ident_start(c) {
    let key = sc.scan_ident()
    sc.expect_char('=', "expected `=` after `\{key}`")
    sc.skip_spaces()
    let val = sc.expect_number("expected number for `\{key}`")
    match key {
      "x" => x = Some(val)
      "y" => y = Some(val)
      other => sc.fail_here("unknown box attribute `\{other}` (expected x or y)")
    }
    sc.skip_spaces()
  }
  sc.expect_char(':', "expected `:` after vbox/hbox header")
  sc.expect_eol("unexpected trailing tokens after vbox/hbox")
  let (children, next) = parse_screen_children(
    lines,
    idx + 1,
    parent_indent=indent,
    file~,
  )
  let end_span = match children.last() {
    Some(n) => screen_node_span(n)
    None => span
  }
  let full = merge_span(span, end_span)
  if is_hbox {
    (HBox(x~, y~, children~, span=full), next)
  } else {
    (VBox(x~, y~, children~, span=full), next)
  }
}

///|
fn parse_screen_fixed(
  sc : ScreenLine,
  lines : Array[String],
  idx : Int,
  indent : Int,
  file : String,
  span~ : SourceSpan,
) -> (ScreenNode, Int) raise ParseError {
  let mut x : Double? = None
  let mut y : Double? = None
  let mut w : Double? = None
  let mut h : Double? = None
  sc.skip_spaces()
  while sc.peek() is Some(c) && is_ident_start(c) {
    let key = sc.scan_ident()
    sc.expect_char('=', "expected `=` after `\{key}`")
    sc.skip_spaces()
    let val = sc.expect_number("expected number for `\{key}`")
    match key {
      "x" => x = Some(val)
      "y" => y = Some(val)
      "w" => w = Some(val)
      "h" => h = Some(val)
      other =>
        sc.fail_here("unknown fixed attribute `\{other}` (expected x, y, w, or h)")
    }
    sc.skip_spaces()
  }
  let xv = match x {
    Some(v) => v
    None => {
      sc.fail_here("fixed requires x=")
      panic()
    }
  }
  let yv = match y {
    Some(v) => v
    None => {
      sc.fail_here("fixed requires y=")
      panic()
    }
  }
  sc.expect_char(':', "expected `:` after fixed header")
  sc.expect_eol("unexpected trailing tokens after fixed")
  let (children, next) = parse_screen_children(
    lines,
    idx + 1,
    parent_indent=indent,
    file~,
  )
  let end_span = match children.last() {
    Some(n) => screen_node_span(n)
    None => span
  }
  (
    Fixed(x=xv, y=yv, w~, h~, children~, span=merge_span(span, end_span)),
    next,
  )
}

///|
fn parse_screen_text_src(sc : ScreenLine) -> ScreenTextSrc raise ParseError {
  sc.skip_spaces()
  match sc.peek() {
    Some('"') => {
      let s = sc.expect_string("expected text string")
      Literal(s)
    }
    Some(c) if is_ident_start(c) => {
      let name = sc.scan_ident()
      match name {
        "slot_label" => {
          sc.expect_char('(', "expected `(` after slot_label")
          sc.skip_spaces()
          let n = sc.expect_int("expected slot index")
          sc.skip_spaces()
          sc.expect_char(')', "expected `)` after slot_label index")
          SlotLabel(n)
        }
        "pref" => {
          sc.expect_char('(', "expected `(` after pref")
          sc.skip_spaces()
          let key = sc.expect_string("expected pref key string")
          sc.skip_spaces()
          sc.expect_char(')', "expected `)` after pref key")
          Pref(key)
        }
        other => {
          sc.fail_here(
            "unknown text source `\{other}` (expected string, slot_label, or pref)",
          )
          panic()
        }
      }
    }
    _ => {
      sc.fail_here("expected text string or binding (slot_label/pref)")
      panic()
    }
  }
}

///|
fn parse_screen_action(sc : ScreenLine) -> ScreenActionAst raise ParseError {
  sc.skip_spaces()
  let name = sc.expect_ident("expected action name")
  match name {
    "return" => Return
    "start_game" => StartGame
    "quit_to_title" => QuitToTitle
    "noop" => Noop
    "hide_screen" => {
      sc.skip_spaces()
      if sc.peek() is Some('(') {
        sc.advance()
        sc.skip_spaces()
        let n = sc.expect_string("expected screen name in hide_screen(...)")
        sc.skip_spaces()
        sc.expect_char(')', "expected `)` after hide_screen name")
        HideScreen(name=Some(n))
      } else {
        HideScreen(name=None)
      }
    }
    "show_screen" => {
      sc.expect_char('(', "expected `(` after show_screen")
      sc.skip_spaces()
      let n = sc.expect_string("expected screen name in show_screen(...)")
      sc.skip_spaces()
      let mut mode : String? = None
      if sc.peek() is Some(',') {
        sc.advance()
        sc.skip_spaces()
        let key = sc.expect_ident("expected `mode=` in show_screen")
        if key != "mode" {
          sc.fail_here("expected `mode=` in show_screen, got `\{key}`")
        }
        sc.expect_char('=', "expected `=` after mode")
        sc.skip_spaces()
        let mv = sc.expect_ident("expected mode value (save|load)")
        mode = Some(mv)
      }
      sc.skip_spaces()
      sc.expect_char(')', "expected `)` after show_screen args")
      ShowScreen(name=n, mode~)
    }
    "save_slot" => {
      sc.expect_char('(', "expected `(` after save_slot")
      sc.skip_spaces()
      let n = sc.expect_int("expected slot index")
      sc.skip_spaces()
      sc.expect_char(')', "expected `)` after save_slot index")
      SaveSlot(n)
    }
    "load_slot" => {
      sc.expect_char('(', "expected `(` after load_slot")
      sc.skip_spaces()
      let n = sc.expect_int("expected slot index")
      sc.skip_spaces()
      sc.expect_char(')', "expected `)` after load_slot index")
      LoadSlot(n)
    }
    "set_pref" => {
      sc.expect_char('(', "expected `(` after set_pref")
      sc.skip_spaces()
      let key = sc.expect_string("expected pref key string")
      sc.skip_spaces()
      sc.expect_char(',', "expected `,` after set_pref key")
      sc.skip_spaces()
      let value = sc.expect_expr_lit("expected pref value literal")
      sc.skip_spaces()
      sc.expect_char(')', "expected `)` after set_pref value")
      SetPref(key~, value~)
    }
    "adjust_pref" => {
      sc.expect_char('(', "expected `(` after adjust_pref")
      sc.skip_spaces()
      let key = sc.expect_string("expected pref key string")
      sc.skip_spaces()
      sc.expect_char(',', "expected `,` after adjust_pref key")
      sc.skip_spaces()
      let delta = sc.expect_number("expected adjust_pref delta number")
      sc.skip_spaces()
      sc.expect_char(')', "expected `)` after adjust_pref delta")
      AdjustPref(key~, delta~)
    }
    other => {
      sc.fail_here("unknown screen action `\{other}`")
      panic()
    }
  }
}

///|
fn screen_node_span(node : ScreenNode) -> SourceSpan {
  match node {
    VBox(span~, ..) => span
    HBox(span~, ..) => span
    Fixed(span~, ..) => span
    Text(span~, ..) => span
    Button(span~, ..) => span
  }
}

///|
fn screen_leading_spaces(line : String) -> Int {
  let mut i = 0
  while line.get_char(i) is Some(' ') {
    i = i + 1
  }
  i
}

///|
fn screen_line_ignored(line : String) -> Bool {
  let mut i = 0
  while line.get_char(i) is Some(c) && (c == ' ' || c == '\t' || c == '\r') {
    i = i + 1
  }
  match line.get_char(i) {
    None => true
    Some('#') => true
    _ => false
  }
}

///|
fn screen_is_top_decl(line : String) -> Bool {
  // Unindented `-` starts the next top-level declaration.
  match line.get_char(0) {
    Some('-') => true
    _ => false
  }
}

///|
/// Minimal cursor over one physical screen-DSL line (raw source, keeps columns).
priv struct ScreenLine {
  text : String
  file : String
  line_no : Int
  mut pos : Int
}

///|
fn ScreenLine::new(
  text : String,
  file~ : String,
  line_no~ : Int,
  pos~ : Int,
) -> ScreenLine {
  { text, file, line_no, pos }
}

///|
fn ScreenLine::peek(self : ScreenLine) -> Char? {
  self.text.get_char(self.pos)
}

///|
fn ScreenLine::advance(self : ScreenLine) -> Unit {
  match self.peek() {
    Some(c) => self.pos += c.utf16_len()
    None => ()
  }
}

///|
fn ScreenLine::skip_spaces(self : ScreenLine) -> Unit {
  while self.peek() is Some(c) && (c == ' ' || c == '\t') {
    self.advance()
  }
}

///|
fn ScreenLine::col(self : ScreenLine) -> Int {
  self.pos + 1
}

///|
fn ScreenLine::fail_here(self : ScreenLine, message : String) -> Unit raise ParseError {
  raise ParseError::ParseError(
    span=make_span(self.file, self.line_no, self.col(), self.col()),
    message~,
  )
}

///|
fn ScreenLine::expect_char(
  self : ScreenLine,
  want : Char,
  message : String,
) -> Unit raise ParseError {
  self.skip_spaces()
  match self.peek() {
    Some(c) if c == want => self.advance()
    _ => self.fail_here(message)
  }
}

///|
fn ScreenLine::expect_eol(
  self : ScreenLine,
  message : String,
) -> Unit raise ParseError {
  self.skip_spaces()
  // Trailing line comment ok
  match self.peek() {
    None | Some('#') => ()
    _ => self.fail_here(message)
  }
}

///|
fn ScreenLine::scan_ident(self : ScreenLine) -> String {
  let start = self.pos
  while self.peek() is Some(c) && is_ident_continue(c) {
    self.advance()
  }
  self.text[start:self.pos].to_owned()
}

///|
fn ScreenLine::expect_ident(
  self : ScreenLine,
  message : String,
) -> String raise ParseError {
  self.skip_spaces()
  match self.peek() {
    Some(c) if is_ident_start(c) => self.scan_ident()
    _ => {
      self.fail_here(message)
      panic()
    }
  }
}

///|
fn ScreenLine::expect_string(
  self : ScreenLine,
  message : String,
) -> String raise ParseError {
  self.skip_spaces()
  match self.peek() {
    Some('"') => {
      self.advance()
      let start = self.pos
      let mut closed = false
      while self.peek() is Some(c) {
        if c == '"' {
          closed = true
          break
        }
        if c == '\\' {
          self.advance()
          if self.peek() is Some(_) {
            self.advance()
          }
        } else {
          self.advance()
        }
      }
      if !closed {
        self.fail_here("unterminated string literal")
        panic()
      }
      let s = self.text[start:self.pos].to_owned()
      self.advance() // closing quote
      s
    }
    _ => {
      self.fail_here(message)
      panic()
    }
  }
}

///|
fn ScreenLine::expect_number(
  self : ScreenLine,
  message : String,
) -> Double raise ParseError {
  self.skip_spaces()
  let start = self.pos
  if self.peek() is Some('-') {
    self.advance()
  }
  let mut saw_digit = false
  while self.peek() is Some(c) && c.is_ascii_digit() {
    saw_digit = true
    self.advance()
  }
  if self.peek() is Some('.') {
    self.advance()
    while self.peek() is Some(c) && c.is_ascii_digit() {
      saw_digit = true
      self.advance()
    }
  }
  if !saw_digit {
    self.fail_here(message)
    panic()
  }
  let text = self.text[start:self.pos]
  match try_parse_double(text) {
    Some(f) => f
    None =>
      match try_parse_int(text) {
        Some(n) => n.to_double()
        None => {
          self.fail_here(message)
          panic()
        }
      }
  }
}

///|
fn ScreenLine::expect_int(
  self : ScreenLine,
  message : String,
) -> Int raise ParseError {
  self.skip_spaces()
  let start = self.pos
  if self.peek() is Some('-') {
    self.advance()
  }
  let mut saw = false
  while self.peek() is Some(c) && c.is_ascii_digit() {
    saw = true
    self.advance()
  }
  if !saw {
    self.fail_here(message)
    panic()
  }
  let text = self.text[start:self.pos]
  match try_parse_int(text) {
    Some(n) => n
    None => {
      self.fail_here(message)
      panic()
    }
  }
}

///|
fn ScreenLine::expect_expr_lit(
  self : ScreenLine,
  message : String,
) -> Expr raise ParseError {
  self.skip_spaces()
  match self.peek() {
    Some('"') => Str(self.expect_string(message))
    Some(c) if c.is_ascii_digit() || c == '-' => {
      // Prefer int when no fractional part
      let start = self.pos
      if self.peek() is Some('-') {
        self.advance()
      }
      while self.peek() is Some(ch) && ch.is_ascii_digit() {
        self.advance()
      }
      if self.peek() is Some('.') {
        // rewind and parse as float via expect_number path
        self.pos = start
        Float(self.expect_number(message))
      } else {
        let text = self.text[start:self.pos]
        match try_parse_int(text) {
          Some(n) => Int(n)
          None => {
            self.fail_here(message)
            panic()
          }
        }
      }
    }
    Some(c) if is_ident_start(c) => {
      let id = self.scan_ident()
      if id == "true" {
        Bool(true)
      } else if id == "false" {
        Bool(false)
      } else {
        self.fail_here(message)
        panic()
      }
    }
    _ => {
      self.fail_here(message)
      panic()
    }
  }
}
