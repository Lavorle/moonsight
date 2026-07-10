///|
/// Staging sibling used while assembling a dist. Promoted to `out_dir` only
/// after the full build succeeds (spec §4.6 — no partial playable out_dir).
fn build_staging_dir(out_dir : String) -> String {
  out_dir + ".tmp-moonsight-build"
}

///|
/// Build a project directory into `out_dir`:
/// 1. Read moonsight.json
/// 2. Compile all `.yuki` → `game.msb`
/// 3. Copy assets + write manifest.json
/// 4. Copy host wasm + js_glue
///
/// Writes go to a staging directory first; `out_dir` is replaced only on full
/// success. On failure, staging is deleted and any prior `out_dir` is left intact.
fn cmd_build(project_dir : String, out_dir : String) -> Int {
  let staging = build_staging_dir(out_dir)
  try {
    guard path_exists(project_dir) else {
      println("error: project dir not found: \{project_dir}")
      return 1
    }
    guard is_dir(project_dir) else {
      println("error: not a directory: \{project_dir}")
      return 1
    }
    let cfg = load_project_config(project_dir)
    let yuki = collect_yuki_files(project_dir)
    if yuki.length() == 0 {
      println("error: no .yuki sources in \{project_dir}")
      return 1
    }
    let entry_path = join_path(project_dir, cfg.entry)
    if !path_exists(entry_path) {
      println("warning: entry file missing: \{entry_path}")
    }
    let ir = compile_yuki_paths(yuki[:], entry_file=entry_path)
    let bytecode = @script.encode_module(ir)

    // Drop leftover staging from a previous interrupted build.
    remove_tree_best_effort(staging)
    ensure_dir(staging)

    let msb_path = join_path(staging, "game.msb")
    write_bytes_to_file(msb_path, bytecode)
    println("wrote \{msb_path} (\{bytecode.length()} bytes, entry=\{ir.entry})")

    // Host runtime first (may include a placeholder manifest.json).
    match find_js_glue() {
      Some(glue) => {
        copy_js_glue(glue, staging)
        println("copied js_glue from \{glue}")
      }
      None =>
        println(
          "warning: host_web/js_glue not found; skip wasm/js copy (build host_web first)",
        )
    }

    // Assets + project manifest (overwrite any glue placeholder).
    let resources : Map[String, String] = {}
    let audio : Map[String, String] = {}
    let assets_src = join_path(project_dir, "assets")
    if path_exists(assets_src) && is_dir(assets_src) {
      let assets_dst = join_path(staging, "assets")
      copy_dir(assets_src, assets_dst)
      collect_asset_manifest(assets_src, "assets", resources, audio)
      println("copied assets → \{assets_dst}")
    }

    // Fail build when scripts reference string-literal resources not on disk.
    if !validate_literal_resources(ir, resources, audio) {
      remove_tree_best_effort(staging)
      return 1
    }

    let manifest = build_manifest_json(cfg, resources, audio)
    let manifest_path = join_path(staging, "manifest.json")
    write_string_to_file(manifest_path, manifest)
    println("wrote \{manifest_path}")

    // Also ship entry source as demo.yuki so current host_web can load it
    // (MSB binary load not yet wired in host — see Task 12 concerns).
    if path_exists(entry_path) && is_file(entry_path) {
      copy_file(entry_path, join_path(staging, "demo.yuki"))
      println("copied entry → \{join_path(staging, "demo.yuki")}")
    }

    // Promote staging → out_dir only after full success.
    if path_exists(out_dir) {
      remove_tree(out_dir)
    } else {
      let parent = dirname(out_dir)
      if parent != out_dir && parent != "" && parent != "." {
        ensure_dir(parent)
      }
    }
    rename_path(staging, out_dir)

    println("build ok: \{cfg.name} → \{out_dir}")
    0
  } catch {
    IoError(msg) => {
      remove_tree_best_effort(staging)
      println("error: \{msg}")
      1
    }
  }
}

///|
fn build_manifest_json(
  cfg : ProjectConfig,
  resources : Map[String, String],
  audio : Map[String, String],
) -> String {
  let res_obj : Map[String, Json] = {}
  for k, v in resources {
    res_obj[k] = Json::string(v)
  }
  let audio_obj : Map[String, Json] = {}
  for k, v in audio {
    audio_obj[k] = Json::string(v)
  }
  let root : Map[String, Json] = {
    "name": Json::string(cfg.name),
    "logical_width": Json::number(cfg.logical_width.to_double()),
    "logical_height": Json::number(cfg.logical_height.to_double()),
    "resources": Json::object(res_obj),
    "audio": Json::object(audio_obj),
  }
  Json::object(root).stringify(indent=2) + "\n"
}

///|
/// Walk assets tree; map basename (no ext) → relative URL path.
fn collect_asset_manifest(
  abs_dir : String,
  rel_prefix : String,
  resources : Map[String, String],
  audio : Map[String, String],
) -> Unit raise IoError {
  for name in read_dir(abs_dir) {
    let abs = join_path(abs_dir, name)
    let rel = join_path(rel_prefix, name)
    if is_dir(abs) {
      collect_asset_manifest(abs, rel, resources, audio)
    } else {
      let id = strip_extension(name)
      if is_image_name(name) {
        resources[id] = rel
      } else if is_audio_name(name) {
        audio[id] = rel
      }
    }
  }
}

///|
fn is_image_name(name : String) -> Bool {
  name.has_suffix(".png") ||
  name.has_suffix(".jpg") ||
  name.has_suffix(".jpeg") ||
  name.has_suffix(".webp")
}

///|
fn is_audio_name(name : String) -> Bool {
  name.has_suffix(".ogg") ||
  name.has_suffix(".mp3") ||
  name.has_suffix(".wav") ||
  name.has_suffix(".m4a")
}

///|
/// Locate engine `host_web/js_glue` relative to cwd or project parents.
fn find_js_glue() -> String? {
  let candidates = [
    "host_web/js_glue", "./host_web/js_glue", "../host_web/js_glue",
  ]
  for c in candidates {
    if path_exists(join_path(c, "index.html")) ||
      path_exists(join_path(c, "boot.js")) {
      return Some(c)
    }
  }
  // Walk parents of cwd looking for host_web/js_glue
  match @env.current_dir() {
    Some(cwd) => {
      let mut dir = cwd
      for _ in 0..<8 {
        let cand = join_path(dir, "host_web/js_glue")
        if path_exists(join_path(cand, "boot.js")) {
          return Some(cand)
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
fn copy_js_glue(glue_dir : String, out_dir : String) -> Unit raise IoError {
  for name in read_dir(glue_dir) {
    // Skip nested junk; copy top-level glue files only.
    // Project-owned outputs are written after this copy.
    if name == "manifest.json" {
      continue
    }
    let from = join_path(glue_dir, name)
    if is_file(from) {
      copy_file(from, join_path(out_dir, name))
    }
  }
  // Prefer release wasm if present next to engine build tree.
  let release_wasm = "_build/wasm-gc/release/build/host_web/host_web.wasm"
  if path_exists(release_wasm) {
    copy_file(release_wasm, join_path(out_dir, "host_web.wasm"))
  }
}
