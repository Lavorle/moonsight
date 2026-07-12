///|
/// Deterministically insert `@meta.id` directives before legacy dialogue and
/// choice lines. Existing directives are preserved, making the transform
/// idempotent and suitable for reviewed migration output.
fn freeze_ids_source(src : String) -> String {
  let lines = src.split("\n").to_array()
  let out : Array[String] = []
  let mut scene = "scene"
  let mut ordinal = 0
  let mut pending_id = false
  for raw in lines {
    let line = raw.to_owned()
    let trimmed = line.trim().to_owned()
    if trimmed.has_prefix("- scene ") {
      scene = freeze_id_slug(trimmed[8:].to_owned())
      ordinal = 0
      pending_id = false
    }
    if trimmed.has_prefix("@meta.id ") {
      pending_id = true
    } else {
      let is_dialogue = !trimmed.has_prefix("@") && trimmed.contains(":")
      let is_choice = trimmed.has_prefix("@flow.choice ")
      if is_dialogue || is_choice {
        ordinal = ordinal + 1
        if !pending_id {
          out.push("@meta.id \"\{scene}.op\{ordinal}\"")
        }
        pending_id = false
      } else if trimmed != "" && !trimmed.has_prefix("#") {
        pending_id = false
      }
    }
    out.push(line)
  }
  out.join("\n")
}

///|
fn freeze_id_slug(raw : String) -> String {
  let mut s = raw.trim().to_owned()
  if s.has_prefix("\"") && s.has_suffix("\"") && s.length() >= 2 {
    s = s[1:s.length() - 1].to_owned()
  }
  let mut out = ""
  for i = 0; i < s.length(); i = i + 1 {
    match s.get_char(i) {
      Some(c) if c.is_ascii_alphabetic() ||
        c.is_ascii_digit() ||
        c == '_' ||
        c == '-' => out = out + c.to_string()
      Some('.') => out = out + "."
      Some(_) => out = out + "_"
      None => ()
    }
  }
  if out == "" || (out.get_char(0) is Some(c) && c.is_ascii_digit()) {
    "scene_" + out
  } else {
    out
  }
}

///|
fn cmd_freeze_ids(path : String, out_path : String) -> Int {
  try {
    let frozen = freeze_ids_source(read_file_to_string(path))
    write_string_to_file(out_path, frozen)
    println("wrote \{out_path}")
    0
  } catch {
    IoError(msg) => {
      println("error: \{msg}")
      1
    }
  }
}
