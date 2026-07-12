///|
/// User preferences (text speed, auto mode, volumes, locale).
///
/// Pure value type: host persists via `to_json_string` / `from_json_string`.
/// All mutators clamp into valid ranges.
pub(all) struct Prefs {
  /// Typewriter speed multiplier (default 1.0, clamp 0.25..3.0).
  text_speed : Double
  /// Auto-advance dialogue when true.
  auto_mode : Bool
  /// Master gain 0..1.
  master_volume : Double
  /// BGM gain 0..1 (relative to master).
  bgm_volume : Double
  /// SE gain 0..1 (relative to master).
  se_volume : Double
  /// Canonical Formal 1.0 locale tag, or empty until a project default resolves.
  locale : String
} derive(Debug, Eq, ToJson)

///|
/// Factory defaults: speed 1.0, auto off, all volumes 1.0.
pub fn Prefs::default() -> Prefs {
  {
    text_speed: 1.0,
    auto_mode: false,
    master_volume: 1.0,
    bgm_volume: 1.0,
    se_volume: 1.0,
    locale: "",
  }
}

///|
fn clamp_range(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// Clamp every field into its legal range.
pub fn Prefs::clamp(self : Prefs) -> Prefs {
  {
    text_speed: clamp_range(self.text_speed, 0.25, 3.0),
    auto_mode: self.auto_mode,
    master_volume: clamp_range(self.master_volume, 0.0, 1.0),
    bgm_volume: clamp_range(self.bgm_volume, 0.0, 1.0),
    se_volume: clamp_range(self.se_volume, 0.0, 1.0),
    locale: self.locale,
  }
}

///|
/// Serialize prefs to a JSON object string.
pub fn Prefs::to_json_string(self : Prefs) -> String {
  self.to_json().stringify()
}

///|
/// Parse prefs JSON. Missing fields fall back to defaults; always clamps.
///
/// Raises on invalid JSON or non-object root.
pub fn Prefs::from_json_string(s : String) -> Prefs raise {
  let json = @json.parse(s) catch { err => fail("invalid prefs JSON: \{err}") }
  guard json is Object(map) else { fail("invalid prefs JSON: expected object") }
  let mut p = Prefs::default()
  match map.get("text_speed") {
    Some(Number(n, ..)) => p = { ..p, text_speed: n }
    _ => ()
  }
  match map.get("auto_mode") {
    Some(True) => p = { ..p, auto_mode: true }
    Some(False) => p = { ..p, auto_mode: false }
    _ => ()
  }
  match map.get("master_volume") {
    Some(Number(n, ..)) => p = { ..p, master_volume: n }
    _ => ()
  }
  match map.get("bgm_volume") {
    Some(Number(n, ..)) => p = { ..p, bgm_volume: n }
    _ => ()
  }
  match map.get("se_volume") {
    Some(Number(n, ..)) => p = { ..p, se_volume: n }
    _ => ()
  }
  match map.get("locale") {
    Some(String(locale)) =>
      if locale == "" || is_formal_locale(locale) {
        p = { ..p, locale }
      } else {
        fail("invalid prefs locale: \{locale}")
      }
    _ => ()
  }
  p.clamp()
}

///|
/// Nudge a numeric pref by `delta`, then clamp.
///
/// Keys: `text_speed`, `master_volume`, `bgm_volume`, `se_volume`.
/// Unknown keys (including `auto_mode`) leave prefs unchanged.
pub fn Prefs::adjust(self : Prefs, key : String, delta : Double) -> Prefs {
  let updated = match key {
    "text_speed" => { ..self, text_speed: self.text_speed + delta }
    "master_volume" => { ..self, master_volume: self.master_volume + delta }
    "bgm_volume" => { ..self, bgm_volume: self.bgm_volume + delta }
    "se_volume" => { ..self, se_volume: self.se_volume + delta }
    _ => self
  }
  updated.clamp()
}

///|
/// Set a pref from a runtime `Value`, then clamp.
///
/// Accepts Int/Float for numeric keys, Bool for `auto_mode`, and a canonical
/// Formal 1.0 locale string (or empty) for `locale`.
/// Unknown keys or wrong types leave prefs unchanged.
pub fn Prefs::set(self : Prefs, key : String, value : Value) -> Prefs {
  let updated = match (key, value) {
    ("text_speed", Float(v)) => { ..self, text_speed: v }
    ("text_speed", Int(v)) => { ..self, text_speed: v.to_double() }
    ("auto_mode", Bool(v)) => { ..self, auto_mode: v }
    ("master_volume", Float(v)) => { ..self, master_volume: v }
    ("master_volume", Int(v)) => { ..self, master_volume: v.to_double() }
    ("bgm_volume", Float(v)) => { ..self, bgm_volume: v }
    ("bgm_volume", Int(v)) => { ..self, bgm_volume: v.to_double() }
    ("se_volume", Float(v)) => { ..self, se_volume: v }
    ("se_volume", Int(v)) => { ..self, se_volume: v.to_double() }
    ("locale", Str(v)) if v == "" || is_formal_locale(v) => { ..self, locale: v }
    _ => self
  }
  updated.clamp()
}
