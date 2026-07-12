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
      let is_resource = trimmed.has_prefix("@layer.show ") ||
        trimmed.has_prefix("@audio.bgm ") ||
        trimmed.has_prefix("@audio.se ")
      if is_dialogue || is_choice || is_resource {
        ordinal = ordinal + 1
        if !pending_id {
          let base = "\{scene}.op\{ordinal}"
          if is_dialogue {
            let speaker = freeze_dialogue_speaker(trimmed)
            out.push(
              "@meta.id \"\{base}\" presentation=\"\{scene}.text\{ordinal}\" speaker=\"\{scene}.speaker.\{speaker}\"",
            )
          } else if is_choice {
            out.push(
              "@meta.id \"\{base}\" presentation=\"\{scene}.choice\{ordinal}\" choices=\"\{freeze_choice_ids(scene, ordinal, trimmed)}\"",
            )
          } else {
            out.push(
              "@meta.id \"\{base}\" resource=\"\{scene}.resource\{ordinal}\"",
            )
          }
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
fn freeze_dialogue_speaker(line : String) -> String {
  match freeze_find_char(line, ':') {
    Some(i) => freeze_id_slug(line[0:i].to_owned())
    None => "narrator"
  }
}

///|
fn freeze_find_char(text : String, target : Char) -> Int? {
  for i = 0; i < text.length(); i = i + 1 {
    if text.get_char(i) is Some(c) && c == target {
      return Some(i)
    }
  }
  None
}

///|
fn freeze_choice_ids(scene : String, ordinal : Int, line : String) -> String {
  let mut quotes = 0
  for i = 0; i < line.length(); i = i + 1 {
    if line.get_char(i) is Some('"') {
      quotes = quotes + 1
    }
  }
  let count = if quotes / 2 > 0 { quotes / 2 } else { 1 }
  let ids : Array[String] = []
  for option = 1; option <= count; option = option + 1 {
    ids.push("\{scene}.choice\{ordinal}.option\{option}")
  }
  ids.join(",")
}

///|
/// Reviewed deterministic legacy mapping: source presentation ordinal to the
/// generated stable operation identity. The artifact is intentionally simple
/// JSON so downstream compatibility tooling can retain it byte-for-byte.
fn freeze_compatibility_json(src : String) -> String {
  let frozen = freeze_ids_source(src)
  let ids : Array[String] = []
  for raw in frozen.split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix("@meta.id \"") {
      let rest = line[10:].to_owned()
      match freeze_find_char(rest, '"') {
        Some(i) => ids.push(rest[0:i].to_owned())
        None => ()
      }
    }
  }
  let rows : Array[String] = []
  for i, id in ids {
    rows.push("    {\"legacy_ordinal\": \{i}, \"operation_id\": \"\{id}\"}")
  }
  "{\n  \"schema_version\": 1,\n  \"operations\": [\n" +
  rows.join(",\n") +
  "\n  ]\n}\n"
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
    let compat_path = out_path + ".compat.json"
    write_string_to_file(compat_path, freeze_compatibility_json(frozen))
    println("wrote \{compat_path}")
    0
  } catch {
    IoError(msg) => {
      println("error: \{msg}")
      1
    }
  }
}
