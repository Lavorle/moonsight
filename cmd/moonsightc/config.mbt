///|
/// Project config from `moonsight.json` (Phase 1 pin — no TOML dependency).
struct ProjectConfig {
  name : String
  entry : String
  logical_width : Int
  logical_height : Int
} derive(Debug)

///|
fn default_config() -> ProjectConfig {
  {
    name: "moonsight",
    entry: "main.yuki",
    logical_width: 1920,
    logical_height: 1080,
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
