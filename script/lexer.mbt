///|
/// Lex full source into tokens. Line-oriented: each physical line starts fresh.
/// Declaration lines begin with `-`; command lines with `@`; `speaker:text` is dialogue.
pub fn lex(src : String, file~ : String) -> Array[Token] {
  let out : Array[Token] = []
  let lines = src.split("\n").to_array()
  for i, line in lines {
    let line_no = i + 1
    lex_line(line, file~, line_no~, out)
    out.push({ kind: Newline, span: span_at(file, line_no, 1) })
  }
  out.push({ kind: Eof, span: span_at(file, lines.length() + 1, 1) })
  out
}

///|
fn span_at(file : String, line : Int, col : Int) -> SourceSpan {
  { file, line, col, end_line: line, end_col: col }
}

///|
fn make_span(file : String, line : Int, col : Int, end_col : Int) -> SourceSpan {
  { file, line, col, end_line: line, end_col }
}

///|
fn is_ident_start(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c == '_'
}

///|
fn is_ident_continue(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_'
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
/// Scanner over a single physical line (UTF-16 code unit indices).
priv struct LineScanner {
  file : String
  line_no : Int
  text : String
  mut pos : Int
}

///|
fn LineScanner::new(
  text : StringView,
  file~ : String,
  line_no~ : Int,
) -> LineScanner {
  { file, line_no, text: text.to_owned(), pos: 0 }
}

///|
fn LineScanner::len(self : LineScanner) -> Int {
  self.text.length()
}

///|
fn LineScanner::peek(self : LineScanner) -> Char? {
  self.text.get_char(self.pos)
}

///|
fn LineScanner::peek_at(self : LineScanner, offset : Int) -> Char? {
  self.text.get_char(self.pos + offset)
}

///|
fn LineScanner::col(self : LineScanner) -> Int {
  self.pos + 1
}

///|
fn LineScanner::skip_spaces(self : LineScanner) -> Unit {
  while self.peek() is Some(c) && is_space(c) {
    self.pos += 1
  }
}

///|
fn LineScanner::advance(self : LineScanner) -> Unit {
  if self.pos < self.len() {
    // Advance by one code unit for BMP; multi-unit chars rare in syntax
    match self.peek() {
      Some(c) => self.pos += c.utf16_len()
      None => ()
    }
  }
}

///|
fn LineScanner::push_token(
  self : LineScanner,
  out : Array[Token],
  kind : TokenKind,
  start_col : Int,
  end_col : Int,
) -> Unit {
  out.push({
    kind,
    span: make_span(self.file, self.line_no, start_col, end_col),
  })
}

///|
fn LineScanner::scan_ident_text(self : LineScanner) -> String {
  let start = self.pos
  while self.peek() is Some(c) && is_ident_continue(c) {
    self.advance()
  }
  self.text[start:self.pos].to_owned()
}

///|
fn LineScanner::scan_string(self : LineScanner, out : Array[Token]) -> Unit {
  let start_col = self.col()
  // consume opening quote
  self.advance()
  let content_start = self.pos
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
  let content = self.text[content_start:self.pos].to_owned()
  if closed {
    self.advance() // closing quote
    self.push_token(out, StringLit(content), start_col, self.col())
  } else {
    self.push_token(
      out,
      Error("unterminated string literal"),
      start_col,
      self.col(),
    )
  }
}

///|
fn try_parse_int(text : StringView) -> Int? {
  Some(@str.parse_int(text)) catch {
    _ => None
  }
}

///|
fn try_parse_double(text : StringView) -> Double? {
  Some(@str.parse_double(text)) catch {
    _ => None
  }
}

///|
fn LineScanner::scan_number(self : LineScanner, out : Array[Token]) -> Unit {
  let start = self.pos
  let start_col = self.col()
  let mut is_float = false
  while self.peek() is Some(c) && c.is_ascii_digit() {
    self.advance()
  }
  if self.peek() is Some('.') &&
    self.peek_at(1) is Some(d) &&
    d.is_ascii_digit() {
    is_float = true
    self.advance() // dot
    while self.peek() is Some(c) && c.is_ascii_digit() {
      self.advance()
    }
  }
  let text = self.text[start:self.pos]
  let end_col = self.col()
  if is_float {
    match try_parse_double(text) {
      Some(f) => self.push_token(out, FloatLit(f), start_col, end_col)
      None =>
        self.push_token(out, Error("invalid float literal"), start_col, end_col)
    }
  } else {
    match try_parse_int(text) {
      Some(n) => self.push_token(out, IntLit(n), start_col, end_col)
      None =>
        self.push_token(out, Error("invalid int literal"), start_col, end_col)
    }
  }
}

///|
fn LineScanner::scan_ident_or_bool(
  self : LineScanner,
  out : Array[Token],
) -> Unit {
  let start_col = self.col()
  let name = self.scan_ident_text()
  let end_col = self.col()
  if name == "true" {
    self.push_token(out, BoolLit(true), start_col, end_col)
  } else if name == "false" {
    self.push_token(out, BoolLit(false), start_col, end_col)
  } else {
    self.push_token(out, Ident(name), start_col, end_col)
  }
}

///|
fn LineScanner::scan_flag(self : LineScanner, out : Array[Token]) -> Unit {
  // assumes current char is first '-' of "--"
  let start_col = self.col()
  self.advance() // first -
  self.advance() // second -
  if self.peek() is Some(c) && is_ident_start(c) {
    let name = self.scan_ident_text()
    self.push_token(out, Flag(name), start_col, self.col())
  } else {
    self.push_token(
      out,
      Error("expected flag name after --"),
      start_col,
      self.col(),
    )
  }
}

///|
fn LineScanner::scan_value(self : LineScanner, out : Array[Token]) -> Unit {
  self.skip_spaces()
  match self.peek() {
    Some('"') => self.scan_string(out)
    Some(c) if c.is_ascii_digit() => self.scan_number(out)
    Some(c) if is_ident_start(c) => self.scan_ident_or_bool(out)
    Some(_) => {
      let start_col = self.col()
      self.advance()
      self.push_token(
        out,
        Error("unexpected character in value"),
        start_col,
        self.col(),
      )
    }
    None => ()
  }
}

///|
fn LineScanner::scan_tokens(self : LineScanner, out : Array[Token]) -> Unit {
  for ;; {
    self.skip_spaces()
    match self.peek() {
      None => break
      Some('#') =>
        // line comment: rest of line ignored
        break
      Some('-') =>
        if self.peek_at(1) is Some('-') {
          self.scan_flag(out)
        } else {
          let start_col = self.col()
          self.advance()
          self.push_token(out, Minus, start_col, self.col())
        }
      Some('@') => {
        let start_col = self.col()
        self.advance()
        self.push_token(out, At, start_col, self.col())
      }
      Some(':') => {
        let start_col = self.col()
        self.advance()
        self.push_token(out, Colon, start_col, self.col())
      }
      Some('=') => {
        // named-arg separator: skip, next token is the value
        self.advance()
        self.scan_value(out)
      }
      Some('"') => self.scan_string(out)
      Some(c) if c.is_ascii_digit() => self.scan_number(out)
      Some(c) if is_ident_start(c) => self.scan_ident_or_bool(out)
      Some(_) => {
        let start_col = self.col()
        self.advance()
        self.push_token(
          out,
          Error("unexpected character"),
          start_col,
          self.col(),
        )
      }
    }
  }
}

///|
fn looks_like_dialogue(line : StringView) -> Bool {
  // After leading spaces: ident then ':' and not declaration/command
  let s = line.to_owned()
  let mut i = 0
  while s.get_char(i) is Some(c) && is_space(c) {
    i += 1
  }
  match s.get_char(i) {
    Some('-') | Some('@') | Some('#') | None => false
    Some(c) if is_ident_start(c) => {
      i += 1
      while s.get_char(i) is Some(ch) && is_ident_continue(ch) {
        i += 1
      }
      s.get_char(i) is Some(':')
    }
    _ => false
  }
}

///|
fn lex_dialogue(sc : LineScanner, out : Array[Token]) -> Unit {
  sc.skip_spaces()
  let start_col = sc.col()
  let speaker = sc.scan_ident_text()
  sc.push_token(out, DialogueSpeaker(speaker), start_col, sc.col())
  // consume ':'
  if sc.peek() is Some(':') {
    sc.advance()
  }
  // rest of line is dialogue text (trim trailing spaces not required)
  let text_start = sc.pos
  let text_col = sc.col()
  sc.pos = sc.len()
  let text = sc.text[text_start:sc.pos].to_owned()
  sc.push_token(out, DialogueText(text), text_col, sc.col())
}

///|
fn lex_line(
  line : StringView,
  file~ : String,
  line_no~ : Int,
  out : Array[Token],
) -> Unit {
  if line.is_blank() {
    return
  }
  let sc = LineScanner::new(line, file~, line_no~)
  if looks_like_dialogue(line) {
    lex_dialogue(sc, out)
  } else {
    sc.scan_tokens(out)
  }
}
