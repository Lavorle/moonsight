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
/// 4. Copy host shell from apps/host-web/dist (required)
///
/// Writes go to a staging directory first; `out_dir` is replaced only on full
/// success. On failure, staging is deleted and any prior `out_dir` is left intact.
fn cmd_build(project_dir : String, out_dir : String) -> Int {
  let staging = build_staging_dir(out_dir)
  // Track whether we overwrote project_ui so failure paths restore the stub.
  let mut linked_ui = false
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

    // Link optional project UI into host_web/project_ui, then rebuild wasm when set.
    // Mark linked before prepare so catch restores even if prepare mutates then fails
    // (e.g. clears project_ui/*.mbt then raises on empty ui_package).
    linked_ui = true
    prepare_project_ui(project_dir, cfg)
    match cfg.ui_package {
      Some(_) => rebuild_host_web_wasm()
      None => ()
    }

    // Drop leftover staging from a previous interrupted build.
    remove_tree_best_effort(staging)
    ensure_dir(staging)

    let msb_path = join_path(staging, "game.msb")
    write_bytes_to_file(msb_path, bytecode)
    println("wrote \{msb_path} (\{bytecode.length()} bytes, entry=\{ir.entry})")

    // Host shell first (may include a placeholder manifest.json).
    // Svelte dist is required; fail hard when missing.
    match find_host_shell() {
      Some(shell) => {
        copy_host_shell(shell, staging)
        println("copied host shell from \{shell}")
      }
      None => {
        println(
          "error: Svelte host shell not found (apps/host-web/dist/index.html).\n" +
          "  Build it first: cd apps/host-web && npm i && npm run build\n" +
          "  Then: moon run cmd/moonsightc --target native -- build <project> -o <out>",
        )
        remove_tree_best_effort(staging)
        restore_project_ui_stub()
        return 1
      }
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
      restore_project_ui_stub()
      return 1
    }

    let manifest = build_manifest_json(cfg, resources, audio)
    let manifest_path = join_path(staging, "manifest.json")
    write_string_to_file(manifest_path, manifest)
    println("wrote \{manifest_path}")

    // Also ship entry source as demo.yuki for source fallback path.
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

    // Always restore committed stub (even if no ui_package was linked).
    restore_project_ui_stub()
    linked_ui = false

    println("build ok: \{cfg.name} → \{out_dir}")
    0
  } catch {
    IoError(msg) => {
      remove_tree_best_effort(staging)
      if linked_ui {
        restore_project_ui_stub()
      }
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
    "save_slots": Json::number(cfg.save_slots.to_double()),
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
/// Locate the web host shell: **only** `apps/host-web/dist` with `index.html`.
fn find_host_shell() -> String? {
  let candidates = [
    "apps/host-web/dist", "./apps/host-web/dist", "../apps/host-web/dist",
  ]
  for c in candidates {
    if is_host_shell_dir(c) {
      return Some(c)
    }
  }
  match @env.current_dir() {
    Some(cwd) => {
      let mut dir = cwd
      for _ in 0..<8 {
        let dist = join_path(dir, "apps/host-web/dist")
        if is_host_shell_dir(dist) {
          return Some(dist)
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
/// Svelte/Vite dist must ship `index.html` (no boot.js fallback).
fn is_host_shell_dir(dir : String) -> Bool {
  path_exists(join_path(dir, "index.html"))
}

///|
/// Copy host shell static files into `out_dir`.
/// Skips host-local placeholder `manifest.json` (project manifest is written later).
/// Injects release `host_web.wasm` when the engine build tree has one.
fn copy_host_shell(shell_dir : String, out_dir : String) -> Unit raise IoError {
  for name in read_dir(shell_dir) {
    // Skip host-local placeholder; build writes project manifest after assets.
    // Copy files *and* dirs (slug/, fonts/, Vite assets/ as required by the shell).
    if name == "manifest.json" {
      continue
    }
    let from = join_path(shell_dir, name)
    let to = join_path(out_dir, name)
    if is_dir(from) {
      copy_dir(from, to)
    } else if is_file(from) {
      copy_file(from, to)
    }
  }
  // Prefer release wasm if present next to engine build tree.
  let release_wasm = "_build/wasm-gc/release/build/host_web/host_web.wasm"
  if path_exists(release_wasm) {
    copy_file(release_wasm, join_path(out_dir, "host_web.wasm"))
  }
}
