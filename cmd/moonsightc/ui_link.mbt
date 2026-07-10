///|
/// Link optional project UI package into `host_web/project_ui` for wasm builds.
///
/// Committed stub is a no-op `register`. When `ui_package` is set, moonsightc
/// overwrites `*.mbt` from the project path, rebuilds host_web, then restores
/// the stub so the working tree stays clean.

///|
/// Run a shell command via `stub_system.c` (`moonsight_system` → libc system).
///
/// `system(3)` returns the wait status; 0 means the child exited 0. Any non-zero
/// value (encoded exit code, signal, etc.) is treated as failure — sufficient for
/// `moon build` success/fail checks.
#borrow(cmd)
extern "C" fn system_ffi(cmd : Bytes) -> Int = "moonsight_system"

///|
fn shell_run(cmd : String) -> Int {
  system_ffi(c_path(cmd))
}

///|
/// Stub `moon.pkg` for `host_web/project_ui` (always preserved across link).
fn project_ui_moon_pkg() -> String {
  let s =
    #|import {
    #|  "moonsight/moonsight/runtime",
    #|}
    #|
  s
}

///|
/// No-op project UI register source restored after every build.
fn project_ui_stub_lib() -> String {
  let s =
    #|///|
    #|/// Project UI overlay package linked into `host_web`.
    #|///
    #|/// Default stub is a no-op. When `moonsight.json` sets `ui_package`, moonsightc
    #|/// overwrites `*.mbt` here from the project package for the wasm build, then
    #|/// restores this stub afterward.
    #|
    #|///|
    #|/// Register project HUD / modal overrides on the shared `UiApp` (after `std_ui`).
    #|pub fn register(_app : @runtime.UiApp) -> Unit {
    #|  ()
    #|}
    #|
  s
}

///|
/// Locate engine root (directory containing `moon.mod` + `host_web/`).
fn find_engine_root() -> String? {
  let candidates = [".", "./", ".."]
  for c in candidates {
    if path_exists(join_path(c, "moon.mod")) &&
      path_exists(join_path(c, "host_web")) {
      return Some(c)
    }
  }
  match @env.current_dir() {
    Some(cwd) => {
      let mut dir = cwd
      for _ in 0..<8 {
        if path_exists(join_path(dir, "moon.mod")) &&
          path_exists(join_path(dir, "host_web")) {
          return Some(dir)
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
/// Path to `host_web/project_ui` under the engine root.
fn find_project_ui_dir() -> String? {
  match find_engine_root() {
    None => None
    Some(root) => {
      let p = join_path(root, "host_web/project_ui")
      if path_exists(p) || path_exists(join_path(root, "host_web")) {
        Some(p)
      } else {
        None
      }
    }
  }
}

///|
/// Delete every `*.mbt` under `ui_dir` (leave moon.pkg / other files).
fn clear_project_ui_mbt(ui_dir : String) -> Unit raise IoError {
  if !path_exists(ui_dir) {
    return
  }
  for name in read_dir(ui_dir) {
    if name.has_suffix(".mbt") {
      remove_file(join_path(ui_dir, name))
    }
  }
}

///|
/// Write committed no-op stub into `host_web/project_ui`.
fn write_project_ui_stub(ui_dir : String) -> Unit raise IoError {
  ensure_dir(ui_dir)
  clear_project_ui_mbt(ui_dir)
  write_string_to_file(join_path(ui_dir, "moon.pkg"), project_ui_moon_pkg())
  write_string_to_file(join_path(ui_dir, "lib.mbt"), project_ui_stub_lib())
}

///|
/// Restore stub best-effort (never raises; used on success and failure paths).
fn restore_project_ui_stub() -> Unit {
  match find_project_ui_dir() {
    None => ()
    Some(ui_dir) =>
      try {
        write_project_ui_stub(ui_dir)
        println("restored host_web/project_ui stub")
      } catch {
        IoError(msg) => println("warning: failed to restore project_ui stub: \{msg}")
      }
  }
}

///|
/// Copy project UI `*.mbt` into the host overlay, or ensure the stub is present.
///
/// Always rewrites `moon.pkg` to the engine runtime import (project packages
/// are not full modules — only sources are linked).
fn prepare_project_ui(project_dir : String, cfg : ProjectConfig) -> Unit raise IoError {
  match find_project_ui_dir() {
    None => raise IoError("host_web/project_ui not found (run from engine repo)")
    Some(ui_dir) =>
      match cfg.ui_package {
        None => {
          write_project_ui_stub(ui_dir)
          println("project_ui: stub (no ui_package)")
        }
        Some(rel) => {
          let src = join_path(project_dir, rel)
          guard path_exists(src) else {
            raise IoError("ui_package not found: \{src}")
          }
          guard is_dir(src) else {
            raise IoError("ui_package is not a directory: \{src}")
          }
          // Mutation starts at clear: any failure after that must restore the stub.
          try {
            ensure_dir(ui_dir)
            clear_project_ui_mbt(ui_dir)
            write_string_to_file(join_path(ui_dir, "moon.pkg"), project_ui_moon_pkg())
            let mut copied = 0
            for name in read_dir(src) {
              if name.has_suffix(".mbt") {
                copy_file(join_path(src, name), join_path(ui_dir, name))
                copied = copied + 1
              }
            }
            if copied == 0 {
              raise IoError("ui_package has no .mbt files: \{src}")
            }
            println("project_ui: linked \{copied} file(s) from \{src}")
          } catch {
            IoError(msg) => {
              restore_project_ui_stub()
              raise IoError(msg)
            }
          }
        }
      }
  }
}

///|
/// Rebuild `host_web` wasm-gc release so linked `project_ui` is in the binary.
fn rebuild_host_web_wasm() -> Unit raise IoError {
  match find_engine_root() {
    None => raise IoError("engine root not found for moon build host_web")
    Some(root) => {
      // Quote-free: engine paths are expected to be simple. Use sh -c via system.
      let cmd =
        "cd \{root} && moon build --target wasm-gc --release host_web"
      println("running: \{cmd}")
      let rc = shell_run(cmd)
      if rc != 0 {
        raise IoError("moon build host_web failed (exit \{rc})")
      }
      let wasm = join_path(root, "_build/wasm-gc/release/build/host_web/host_web.wasm")
      guard path_exists(wasm) else {
        raise IoError("host_web.wasm missing after build: \{wasm}")
      }
      // Keep js_glue artifact in sync for consumers that copy only that tree.
      let glue_wasm = join_path(root, "host_web/js_glue/host_web.wasm")
      try {
        copy_file(wasm, glue_wasm)
        println("updated \{glue_wasm}")
      } catch {
        IoError(msg) =>
          println("warning: could not update js_glue wasm: \{msg}")
      }
      println("rebuilt host_web.wasm")
    }
  }
}
