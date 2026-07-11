///|
/// Type-check / compile `.yuki` sources without writing output.
///
/// `path` may be a single file or a directory of `.yuki` files.
/// After compile succeeds, unknown `@flow.jump` / jump-if scene targets error.
fn cmd_check(path : String) -> Int {
  try {
    let files = collect_yuki_files(path)
    if files.length() == 0 {
      println("error: no .yuki files under \{path}")
      return 1
    }
    let mut ok = 0
    let mut failed = 0
    for f in files {
      try {
        ignore(compile_file_to_ir(f))
        println("ok  \{f}")
        ok = ok + 1
      } catch {
        IoError(msg) => {
          println("err \{f}")
          println(msg)
          failed = failed + 1
        }
      }
    }
    if failed > 0 {
      println("check: \{ok} ok, \{failed} failed")
      return 1
    }
    // Merged module for jump-target heuristic (all scenes visible together).
    try {
      let entry_file = if is_dir(path) {
        // Prefer main.yuki when checking a project dir; else first file.
        let main = join_path(path, "main.yuki")
        if path_exists(main) {
          main
        } else {
          files[0]
        }
      } else {
        path
      }
      let ir = compile_yuki_paths(files[:], entry_file=entry_file)
      let missing = unknown_jump_targets(ir)
      if missing.length() > 0 {
        for t in missing {
          println("error: unknown jump target scene `\{t}`")
          failed = failed + 1
        }
      }
    } catch {
      IoError(msg) => {
        println("error: \{msg}")
        failed = failed + 1
      }
    }
    println("check: \{ok} ok, \{failed} failed")
    if failed > 0 {
      1
    } else {
      0
    }
  } catch {
    IoError(msg) => {
      println("error: \{msg}")
      1
    }
  }
}

///|
/// Collect distinct `flow.jump` string scene targets that are not defined scenes.
fn unknown_jump_targets(ir : @script.IrModule) -> Array[String] {
  let missing : Array[String] = []
  let seen : Map[String, Unit] = {}
  for _, scene in ir.scenes {
    for op in scene.ops {
      match op {
        Host(name="flow.jump", args~) =>
          if args.length() > 0 {
            match args[0] {
              Str(target) =>
                if !ir.scenes.contains(target) && !seen.contains(target) {
                  seen[target] = ()
                  missing.push(target)
                }
              _ => ()
            }
          }
        _ => ()
      }
    }
  }
  missing.sort()
  missing
}
