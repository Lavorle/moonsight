///|
/// Project config from `moonsight.json` (Phase 1 pin — no TOML dependency).
struct ProjectConfig {
  name : String
  entry : String
  logical_width : Int
  logical_height : Int
  /// Multi-slot save capacity (default 6, clamp 1..20).
  save_slots : Int
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
    ui_package: None,
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
