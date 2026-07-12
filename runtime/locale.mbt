///|
/// Return whether `tag` is in the frozen Formal 1.0 BCP-47 profile:
/// `language[-Script][-REGION]`, with canonical ASCII casing.
pub fn is_formal_locale(tag : String) -> Bool {
  let parts = tag.split("-").to_array()
  if parts.length() < 1 || parts.length() > 3 {
    return false
  }
  let language = parts[0].to_owned()
  if (language.length() != 2 && language.length() != 3) ||
    !all_chars(language, fn(c) { c.is_ascii_lowercase() }) {
    return false
  }
  let mut next = 1
  if next < parts.length() {
    let candidate = parts[next].to_owned()
    if candidate.length() == 4 {
      guard candidate.get_char(0) is Some(first) else { return false }
      if !first.is_ascii_uppercase() ||
        !all_chars_from(candidate, 1, fn(c) { c.is_ascii_lowercase() }) {
        return false
      }
      next += 1
    }
  }
  if next < parts.length() {
    let region = parts[next].to_owned()
    let alpha_region = region.length() == 2 &&
      all_chars(region, fn(c) { c.is_ascii_uppercase() })
    let numeric_region = region.length() == 3 &&
      all_chars(region, fn(c) { c.is_ascii_digit() })
    if !alpha_region && !numeric_region {
      return false
    }
    next += 1
  }
  next == parts.length()
}

///|
fn all_chars(s : String, predicate : (Char) -> Bool) -> Bool {
  all_chars_from(s, 0, predicate)
}

///|
fn all_chars_from(s : String, start : Int, predicate : (Char) -> Bool) -> Bool {
  let mut i = start
  while i < s.length() {
    guard s.get_char(i) is Some(c) else { return false }
    if !predicate(c) {
      return false
    }
    i += c.utf16_len()
  }
  true
}

///|
/// Resolve an exact supported locale, otherwise use the declared default.
/// Invalid project locale metadata is rejected rather than normalized silently.
pub fn resolve_locale(
  requested : String,
  supported : Array[String],
  default_locale : String,
) -> String raise {
  if !is_formal_locale(default_locale) {
    fail("invalid default locale: \{default_locale}")
  }
  let mut default_supported = false
  let mut requested_supported = false
  for locale in supported {
    if !is_formal_locale(locale) {
      fail("invalid supported locale: \{locale}")
    }
    if locale == default_locale {
      default_supported = true
    }
    if locale == requested {
      requested_supported = true
    }
  }
  if !default_supported {
    fail("default locale is not supported: \{default_locale}")
  }
  if requested_supported { requested } else { default_locale }
}
