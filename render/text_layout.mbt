///|
/// One laid-out line (or fragment) in logical coordinates relative to origin (0,0).
pub(all) struct TextRun {
  text : String
  x : Float
  y : Float
  width : Float
  height : Float
} derive(Debug)

///|
/// Constant advance for every codepoint — useful in tests without real font metrics.
pub fn fixed_width_measure(advance : Float) -> (Char) -> Float {
  fn(_ch : Char) { advance }
}

///|
/// Approximate proportional advance as a fraction of `font_size` (em).
///
/// Used when the host has not supplied real `measureText` metrics. Latin
/// widths are rough averages for a sans face; CJK / other wide scripts use a
/// full em so ideographs stay square.
pub fn approximate_advance_em(ch : Char) -> Float {
  let cp = ch.to_int()
  // CJK Unified Ideographs and common fullwidth ranges → 1.0 em
  if (cp >= 0x2E80 && cp <= 0x9FFF) ||
      (cp >= 0xF900 && cp <= 0xFAFF) ||
      (cp >= 0xFF00 && cp <= 0xFFEF) {
    return 1.0
  }
  match ch {
    ' ' | '\t' => 0.33
    'i' | 'l' | 'I' | 'j' | '|' | '.' | ',' | '\'' | '`' | '!' | ':' | ';' =>
      0.30
    'f' | 't' | 'r' => 0.38
    'm' | 'w' | 'M' | 'W' => 0.90
    '@' | '%' | 'Ö' | '—' => 0.95
    _ => {
      // Uppercase slightly wider on average
      if ch >= 'A' && ch <= 'Z' {
        0.62
      } else if ch >= '0' && ch <= '9' {
        0.55
      } else {
        0.52
      }
    }
  }
}

///|
/// Build a measure function: `advance ≈ em * font_size`.
pub fn approximate_measure(font_size : Float) -> (Char) -> Float {
  fn(ch : Char) {
    let em = approximate_advance_em(ch)
    let a = em * font_size
    if a < 1.0 {
      1.0
    } else {
      a
    }
  }
}

///|
/// Measure a string with a per-glyph advance function.
pub fn measure_string(text : String, measure~ : (Char) -> Float) -> Float {
  let mut w : Float = 0.0
  for ch in text {
    w = w + measure(ch)
  }
  w
}

///|
/// Word-wrap `text` into runs within `max_width`.
///
/// - Soft wrap on spaces; hard-break overlong tokens.
/// - Explicit `\\n` forces a new line.
/// - `y` advances by `font_size * 1.2` per line; `x` is always 0 for left-aligned runs.
/// - Empty input yields an empty array.
pub fn layout_text(
  text : String,
  max_width~ : Float,
  font_size~ : Float,
  measure~ : (Char) -> Float,
) -> Array[TextRun] {
  let runs : Array[TextRun] = []
  if text.length() == 0 {
    return runs
  }
  let line_h : Float = font_size * 1.2
  let mut line_chars : Array[Char] = []
  let mut line_w : Float = 0.0
  let mut line_y : Float = 0.0

  fn flush_line() -> Unit {
    if line_chars.length() == 0 {
      // Still advance for blank lines from explicit newlines.
      return
    }
    let s = String::from_array(line_chars[:])
    // Trim trailing spaces from the run for cleaner draw lists.
    let trimmed = s.trim_end(chars=" ").to_owned()
    let tw = measure_string(trimmed, measure~)
    runs.push({ text: trimmed, x: 0.0, y: line_y, width: tw, height: line_h })
    line_chars = []
    line_w = 0.0
    line_y = line_y + line_h
  }

  fn flush_blank() -> Unit {
    // Explicit empty line: advance y without emitting a run.
    line_chars = []
    line_w = 0.0
    line_y = line_y + line_h
  }

  fn append_char(ch : Char) -> Unit {
    let aw = measure(ch)
    if line_w + aw > max_width && line_chars.length() > 0 {
      flush_line()
    }
    line_chars.push(ch)
    line_w = line_w + aw
  }

  // Process token-by-token for soft wrap; tokens are space-delimited.
  let mut token : Array[Char] = []
  let mut token_w : Float = 0.0

  fn flush_token() -> Unit {
    if token.length() == 0 {
      return
    }
    // Soft wrap before token if it does not fit on the current line.
    if line_chars.length() > 0 && line_w + token_w > max_width {
      flush_line()
    }
    // Hard-break if a single token is wider than max_width.
    if token_w > max_width {
      for ch in token {
        append_char(ch)
      }
    } else {
      for ch in token {
        line_chars.push(ch)
      }
      line_w = line_w + token_w
    }
    token = []
    token_w = 0.0
  }

  for ch in text {
    if ch == '\n' {
      flush_token()
      if line_chars.length() == 0 {
        flush_blank()
      } else {
        flush_line()
      }
    } else if ch == ' ' {
      flush_token()
      // Keep spaces only when the line already has content.
      if line_chars.length() > 0 {
        let sw = measure(ch)
        if line_w + sw > max_width {
          flush_line()
        } else {
          line_chars.push(ch)
          line_w = line_w + sw
        }
      }
    } else {
      token.push(ch)
      token_w = token_w + measure(ch)
    }
  }
  flush_token()
  if line_chars.length() > 0 {
    flush_line()
  }
  runs
}

///|
/// Visible typewriter prefix using UTF-16 code unit count (matches Stage).
pub fn visible_prefix(full : String, visible_chars : Int) -> String {
  if visible_chars <= 0 {
    return ""
  }
  let len = full.length()
  if visible_chars >= len {
    full
  } else {
    full.unsafe_substring(start=0, end=visible_chars)
  }
}
