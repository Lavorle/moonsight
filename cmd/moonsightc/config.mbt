///|
/// Project config from `moonsight.json` (Phase 1 pin — no TOML dependency).
struct ProjectConfig {
  name : String
  entry : String
  logical_width : Int
  logical_height : Int
  /// Multi-slot save capacity (default 6, clamp 1..20).
  save_slots : Int
  /// Locale used when no persisted/user preference is available.
  default_locale : String
  /// Complete locale set shipped by the project package.
  supported_locales : Array[String]
  /// Optional MoonBit UI package path relative to the project root.
  /// When set, moonsightc copies its `*.mbt` into `host_web/project_ui` before
  /// rebuilding the host wasm (restored to the no-op stub after build).
  ui_package : String?
} derive(Debug)

///|
fn default_config() -> ProjectConfig {
  {
    name: "moonsight",
    entry: "main.yuki",
    logical_width: 1920,
    logical_height: 1080,
    save_slots: 6,
    default_locale: "en",
    supported_locales: ["en"],
    ui_package: None,
  }
}

///|
fn chars_all(s : String, pred : (Char) -> Bool) -> Bool {
  for c in s {
    if !pred(c) {
      return false
    }
  }
  true
}

///|
fn is_ascii_lower(c : Char) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn is_ascii_upper(c : Char) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
fn is_title_script(s : String) -> Bool {
  if s.length() != 4 {
    return false
  }
  let mut index = 0
  for c in s {
    if (index == 0 && !is_ascii_upper(c)) || (index > 0 && !is_ascii_lower(c)) {
      return false
    }
    index = index + 1
  }
  true
}

///|
fn is_formal_locale_tag(tag : String) -> Bool {
  let parts = tag.split("-").to_array()
  if parts.length() < 1 || parts.length() > 3 {
    return false
  }
  let language = parts[0].to_owned()
  if (language.length() != 2 && language.length() != 3) ||
    !chars_all(language, is_ascii_lower) {
    return false
  }
  let mut index = 1
  if index < parts.length() && parts[index].length() == 4 {
    let script = parts[index].to_owned()
    if !is_title_script(script) {
      return false
    }
    index = index + 1
  }
  if index < parts.length() {
    let region = parts[index].to_owned()
    let valid_region = (
        region.length() == 2 && chars_all(region, is_ascii_upper)
      ) ||
      (region.length() == 3 && chars_all(region, fn(c) { c.is_ascii_digit() }))
    if !valid_region {
      return false
    }
    index = index + 1
  }
  index == parts.length()
}

///|
fn validate_project_locales(cfg : ProjectConfig) -> Unit raise {
  if cfg.supported_locales.length() == 0 {
    fail("moonsight.json: supported_locales must not be empty")
  }
  let seen : Map[String, Bool] = {}
  let mut contains_default = false
  for locale in cfg.supported_locales {
    if !is_formal_locale_tag(locale) {
      fail(
        "moonsight.json: invalid locale tag '\{locale}' (expected Formal 1.0 BCP-47 core profile)",
      )
    }
    if seen.contains(locale) {
      fail("moonsight.json: duplicate supported locale '\{locale}'")
    }
    seen[locale] = true
    if locale == cfg.default_locale {
      contains_default = true
    }
  }
  if !is_formal_locale_tag(cfg.default_locale) {
    fail(
      "moonsight.json: invalid default_locale '\{cfg.default_locale}' (expected Formal 1.0 BCP-47 core profile)",
    )
  }
  if !contains_default {
    fail(
      "moonsight.json: default_locale '\{cfg.default_locale}' must appear in supported_locales",
    )
  }
}

///|
/// Clamp save slot count into the legal range 1..20.
fn clamp_save_slots(n : Int) -> Int {
  if n < 1 {
    1
  } else if n > 20 {
    20
  } else {
    n
  }
}

///|
fn parse_project_config(text : String) -> ProjectConfig raise {
  let j = @json.parse(text)
  guard j is Object(map) else { fail("moonsight.json: expected object") }
  let mut cfg = default_config()
  match map.get("name") {
    Some(Json::String(s)) => cfg = { ..cfg, name: s }
    Some(_) => fail("moonsight.json: name must be a string")
    None => ()
  }
  match map.get("entry") {
    Some(Json::String(s)) => cfg = { ..cfg, entry: s }
    Some(_) => fail("moonsight.json: entry must be a string")
    None => ()
  }
  match map.get("logical_width") {
    Some(Json::Number(n, ..)) => cfg = { ..cfg, logical_width: n.to_int() }
    Some(_) => fail("moonsight.json: logical_width must be a number")
    None => ()
  }
  match map.get("logical_height") {
    Some(Json::Number(n, ..)) => cfg = { ..cfg, logical_height: n.to_int() }
    Some(_) => fail("moonsight.json: logical_height must be a number")
    None => ()
  }
  match map.get("save_slots") {
    Some(Json::Number(n, ..)) =>
      cfg = { ..cfg, save_slots: clamp_save_slots(n.to_int()) }
    Some(_) => fail("moonsight.json: save_slots must be a number")
    None => ()
  }
  match map.get("default_locale") {
    Some(Json::String(s)) => cfg = { ..cfg, default_locale: s }
    Some(_) => fail("moonsight.json: default_locale must be a string")
    None => ()
  }
  match map.get("supported_locales") {
    Some(Json::Array(items)) => {
      let locales : Array[String] = []
      for item in items {
        match item {
          Json::String(s) => locales.push(s)
          _ => fail("moonsight.json: supported_locales must contain strings")
        }
      }
      cfg = { ..cfg, supported_locales: locales }
    }
    Some(_) => fail("moonsight.json: supported_locales must be an array")
    None => ()
  }
  match map.get("ui_package") {
    Some(Json::String(s)) => {
      let t = s.trim().to_owned()
      if t.length() == 0 {
        cfg = { ..cfg, ui_package: None }
      } else {
        cfg = { ..cfg, ui_package: Some(t) }
      }
    }
    Some(Json::Null) => cfg = { ..cfg, ui_package: None }
    Some(_) => fail("moonsight.json: ui_package must be a string")
    None => ()
  }
  validate_project_locales(cfg)
  cfg
}

///|
fn load_project_config(project_dir : String) -> ProjectConfig raise IoError {
  let path = join_path(project_dir, "moonsight.json")
  guard path_exists(path) else {
    raise IoError("missing moonsight.json in \{project_dir}")
  }
  let text = read_file_to_string(path)
  parse_project_config(text) catch {
    e => raise IoError("failed to parse moonsight.json: \{to_repr(e)}")
  }
}
