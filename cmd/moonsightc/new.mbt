///|
/// True if `dir` looks like the monorepo `templates/minimal` root.
fn is_minimal_template(dir : String) -> Bool {
  path_exists(dir) && path_exists(join_path(dir, "moonsight.json"))
}

///|
/// Resolve monorepo `templates/minimal` by walking parents of cwd
/// (same idea as `find_host_shell`).
fn find_minimal_template() -> String? {
  let candidates = [
    "templates/minimal", "./templates/minimal", "../templates/minimal",
  ]
  for c in candidates {
    if is_minimal_template(c) {
      return Some(c)
    }
  }
  match @env.current_dir() {
    Some(cwd) => {
      let mut dir = cwd
      for _ in 0..<8 {
        let t = join_path(dir, "templates/minimal")
        if is_minimal_template(t) {
          return Some(t)
        }
        let parent = dirname(dir)
        if parent == dir {
          break
        }
        dir = parent
      }
      None
    }
    None => None
  }
}

///|
/// `moonsightc new <name> [-o <parent_dir>]`
fn cmd_new(name : String, parent_dir : String) -> Int {
  if name.length() == 0 || name.contains("/") || name.contains("\\") {
    println("error: invalid project name: \{name}")
    return 1
  }
  let dest = join_path(parent_dir, name)
  if path_exists(dest) {
    println("error: destination already exists: \{dest}")
    return 1
  }
  match find_minimal_template() {
    None => {
      println(
        "error: templates/minimal not found (run from moonsight monorepo)",
      )
      1
    }
    Some(tmpl) =>
      try {
        ensure_dir(parent_dir)
        copy_dir(tmpl, dest)
        // Patch name in moonsight.json if present
        let cfg_path = join_path(dest, "moonsight.json")
        if path_exists(cfg_path) {
          let raw = read_file_to_string(cfg_path)
          let patched = raw.replace_all(old="my-moonsight-game", new=name)
          write_string_to_file(cfg_path, patched)
        }
        println("created \{dest}")
        println(
          "next: export CC=gcc && moon run cmd/moonsightc --target native -- check \{dest}",
        )
        println("      (requires apps/host-web/dist before build — see docs)")
        0
      } catch {
        IoError(msg) => {
          println("error: new failed: \{msg}")
          1
        }
      }
  }
}
