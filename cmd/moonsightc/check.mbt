///|
/// Type-check / compile `.yuki` sources without writing output.
///
/// `path` may be a single file or a directory of `.yuki` files.
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
