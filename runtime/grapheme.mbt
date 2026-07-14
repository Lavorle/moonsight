///|
/// Grapheme boundary helpers (UAX #29 practical subset).
///
/// Supports: scalar bases, common combining marks (Extend), regional-indicator
/// pairs, ZWJ emoji sequences (GB11), CR×LF, and CJK single-scalar graphemes.
/// Not a full ICU segmenter; Hangul jamo complex sequences and uncommon
/// SpacingMark / Prepend classes are best-effort (often treated as separate
/// clusters). `visible_chars` contract: always a grapheme-aligned UTF-16 end
/// index in `0 … text.length()`.

///|
/// UTF-16 end indices of each extended grapheme cluster, including leading 0
/// and trailing `text.length()`. Empty text yields `[0]`.
pub fn grapheme_boundaries(text : String) -> Array[Int] {
  let out : Array[Int] = [0]
  if text.length() == 0 {
    return out
  }
  let codes : Array[Int] = []
  let ends : Array[Int] = []
  let mut i = 0
  while i < text.length() {
    match text.get_char(i) {
      Some(c) => {
        let w = c.utf16_len()
        codes.push(c.to_int())
        ends.push(i + w)
        i += w
      }
      None => break
    }
  }
  if codes.length() == 0 {
    return out
  }
  // State for GB11 (emoji ZWJ) and GB12/13 (regional indicator pairs).
  let mut in_emoji = is_extended_pictographic(codes[0])
  let mut gb11_ready = false
  let mut ri_count = if is_regional_indicator(codes[0]) { 1 } else { 0 }
  let mut j = 1
  while j < codes.length() {
    let prev = codes[j - 1]
    let curr = codes[j]
    let mut brk = true
    if is_cr(prev) && is_lf(curr) {
      brk = false
    } else if is_control_cr_lf(prev) || is_control_cr_lf(curr) {
      brk = true
    } else if is_extend(curr) || is_zwj(curr) {
      // GB9: × (Extend | ZWJ)
      brk = false
    } else if gb11_ready && is_extended_pictographic(curr) {
      // GB11: EP Extend* ZWJ × EP
      brk = false
    } else if is_regional_indicator(prev) &&
      is_regional_indicator(curr) &&
      ri_count % 2 == 1 {
      // GB12/13: pair of RIs
      brk = false
    } else {
      brk = true
    }
    if brk {
      out.push(ends[j - 1])
    }
    // Update state after consuming `curr` (inside or starting a cluster).
    if is_regional_indicator(curr) {
      if !brk && is_regional_indicator(prev) {
        ri_count = ri_count + 1
      } else {
        ri_count = 1
      }
      in_emoji = false
      gb11_ready = false
    } else if is_extended_pictographic(curr) {
      ri_count = 0
      in_emoji = true
      gb11_ready = false
    } else if is_extend(curr) {
      ri_count = 0
      // Keep in_emoji; extends after EP still allow later ZWJ link.
      gb11_ready = false
    } else if is_zwj(curr) {
      ri_count = 0
      gb11_ready = in_emoji
    } else {
      ri_count = 0
      in_emoji = false
      gb11_ready = false
    }
    j = j + 1
  }
  out.push(text.length())
  out
}

///|
/// Number of extended grapheme clusters in `text`.
pub fn grapheme_count(text : String) -> Int {
  let b = grapheme_boundaries(text)
  if b.length() == 0 {
    0
  } else {
    b.length() - 1
  }
}

///|
/// Floor `utf16` to the greatest grapheme boundary ≤ `utf16` (clamped to
/// `[0, text.length()]`).
pub fn clamp_to_grapheme_boundary(text : String, utf16 : Int) -> Int {
  let b = grapheme_boundaries(text)
  let mut best = 0
  for x in b {
    if x <= utf16 {
      best = x
    }
  }
  best
}

///|
/// Advance `grapheme_delta` clusters from the grapheme boundary at or below
/// `current_utf16`. Negative or zero delta only clamps.
pub fn advance_visible_utf16(
  text : String,
  current_utf16 : Int,
  grapheme_delta : Int,
) -> Int {
  if grapheme_delta <= 0 {
    return clamp_to_grapheme_boundary(text, current_utf16)
  }
  let b = grapheme_boundaries(text)
  // Index of largest boundary ≤ current.
  let mut idx = 0
  let mut i = 0
  while i < b.length() {
    if b[i] <= current_utf16 {
      idx = i
    }
    i = i + 1
  }
  let next = idx + grapheme_delta
  if next >= b.length() {
    text.length()
  } else {
    b[next]
  }
}

///|
/// Grapheme-safe visible prefix of `text` up to `visible_utf16` (floored).
pub fn visible_prefix(text : String, visible_utf16 : Int) -> String {
  let end = clamp_to_grapheme_boundary(text, visible_utf16)
  if end <= 0 {
    ""
  } else if end >= text.length() {
    text
  } else {
    text.unsafe_substring(start=0, end=end)
  }
}

// --- category helpers (practical subset of UAX #29 / Unicode props) ---

///|
fn is_cr(cp : Int) -> Bool {
  cp == 0x000D
}

///|
fn is_lf(cp : Int) -> Bool {
  cp == 0x000A
}

///|
fn is_zwj(cp : Int) -> Bool {
  cp == 0x200D
}

///|
fn is_regional_indicator(cp : Int) -> Bool {
  cp >= 0x1F1E6 && cp <= 0x1F1FF
}

///|
/// Control | CR | LF for GB4/GB5 (subset: Cc + common format controls).
fn is_control_cr_lf(cp : Int) -> Bool {
  if is_cr(cp) || is_lf(cp) {
    return true
  }
  // C0 / DEL
  if cp <= 0x001F || cp == 0x007F {
    return true
  }
  // C1
  if cp >= 0x0080 && cp <= 0x009F {
    return true
  }
  // Common Cf that break graphemes like Control in practice for typewriter
  // (LINE/PARAGRAPH SEPARATOR). Soft hyphen / bidi marks treated as Other.
  cp == 0x2028 || cp == 0x2029
}

///|
/// Grapheme_Extend subset: combining marks, variation selectors, emoji
/// modifiers, tag characters used in flag sequences.
fn is_extend(cp : Int) -> Bool {
  // Combining Diacritical Marks
  if cp >= 0x0300 && cp <= 0x036F {
    return true
  }
  // Combining Diacritical Marks Extended
  if cp >= 0x1AB0 && cp <= 0x1AFF {
    return true
  }
  // Combining Diacritical Marks Supplement
  if cp >= 0x1DC0 && cp <= 0x1DFF {
    return true
  }
  // Combining Diacritical Marks for Symbols
  if cp >= 0x20D0 && cp <= 0x20FF {
    return true
  }
  // Combining Half Marks
  if cp >= 0xFE20 && cp <= 0xFE2F {
    return true
  }
  // Variation Selectors
  if cp >= 0xFE00 && cp <= 0xFE0F {
    return true
  }
  // Variation Selectors Supplement
  if cp >= 0xE0100 && cp <= 0xE01EF {
    return true
  }
  // Emoji skin-tone modifiers
  if cp >= 0x1F3FB && cp <= 0x1F3FF {
    return true
  }
  // Hebrew / Arabic / Syriac common marks (Mn)
  if cp >= 0x0483 && cp <= 0x0489 {
    return true
  }
  if cp >= 0x0591 && cp <= 0x05BD {
    return true
  }
  if cp == 0x05BF || cp == 0x05C7 {
    return true
  }
  if cp >= 0x05C1 && cp <= 0x05C2 {
    return true
  }
  if cp >= 0x05C4 && cp <= 0x05C5 {
    return true
  }
  if cp >= 0x0610 && cp <= 0x061A {
    return true
  }
  if cp >= 0x064B && cp <= 0x065F {
    return true
  }
  if cp == 0x0670 {
    return true
  }
  if cp >= 0x06D6 && cp <= 0x06DC {
    return true
  }
  if cp >= 0x06DF && cp <= 0x06E4 {
    return true
  }
  if cp >= 0x06E7 && cp <= 0x06E8 {
    return true
  }
  if cp >= 0x06EA && cp <= 0x06ED {
    return true
  }
  // Devanagari virama + common Mn (not full Mc SpacingMark)
  if cp >= 0x0900 && cp <= 0x0902 {
    return true
  }
  if cp == 0x093C || cp == 0x094D {
    return true
  }
  if cp >= 0x0941 && cp <= 0x0948 {
    return true
  }
  if cp >= 0x0951 && cp <= 0x0957 {
    return true
  }
  // Zero width non-joiner / joiner-like format used as extend in some data
  if cp == 0x200C {
    return true
  }
  // Emoji tag sequences (flag tags)
  if cp >= 0xE0020 && cp <= 0xE007F {
    return true
  }
  false
}

///|
/// Extended_Pictographic practical ranges for ZWJ emoji (GB11).
fn is_extended_pictographic(cp : Int) -> Bool {
  // Copyright / registered / trademark often EP in modern Unicode
  if cp == 0x00A9 || cp == 0x00AE || cp == 0x203C || cp == 0x2049 {
    return true
  }
  if cp == 0x2122 || cp == 0x2139 {
    return true
  }
  if cp >= 0x2194 && cp <= 0x2199 {
    return true
  }
  if cp >= 0x21A9 && cp <= 0x21AA {
    return true
  }
  if cp >= 0x231A && cp <= 0x231B {
    return true
  }
  if cp == 0x2328 || cp == 0x23CF {
    return true
  }
  if cp >= 0x23E9 && cp <= 0x23F3 {
    return true
  }
  if cp >= 0x23F8 && cp <= 0x23FA {
    return true
  }
  if cp == 0x24C2 || cp == 0x25B6 || cp == 0x25C0 {
    return true
  }
  if cp >= 0x25AA && cp <= 0x25AB {
    return true
  }
  if cp >= 0x25FB && cp <= 0x25FE {
    return true
  }
  if cp >= 0x2600 && cp <= 0x27BF {
    return true
  }
  if cp >= 0x2934 && cp <= 0x2935 {
    return true
  }
  if cp >= 0x2B05 && cp <= 0x2B07 {
    return true
  }
  if cp >= 0x2B1B && cp <= 0x2B1C {
    return true
  }
  if cp == 0x2B50 || cp == 0x2B55 {
    return true
  }
  if cp == 0x3030 || cp == 0x303D || cp == 0x3297 || cp == 0x3299 {
    return true
  }
  // Misc symbols and pictographs, emoticons, transport, supplemental
  if cp >= 0x1F000 && cp <= 0x1FAFF {
    return true
  }
  // Additional supplemental symbols
  if cp >= 0x1FC00 && cp <= 0x1FFFD {
    return true
  }
  false
}
