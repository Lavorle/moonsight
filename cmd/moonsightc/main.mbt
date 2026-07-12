///|
/// moonsightc — MoonSight project checker / web dist builder.
///
/// ```
/// moonsightc version
/// moonsightc new <name> [-o <parent_dir>]
/// moonsightc check <file.yuki|dir>
/// moonsightc build <project_dir> -o <out_dir>
/// ```

///|
extern "C" fn process_exit(code : Int) -> Unit = "exit"

///|
fn print_usage() -> Unit {
  let usage =
    #|usage: moonsightc <new|check|freeze-ids|build|version> ...
    #|  moonsightc version
    #|  moonsightc new <name> [-o <parent_dir>]
    #|  moonsightc check <file.yuki|dir>
    #|  moonsightc freeze-ids <file.yuki> [-o <output.yuki>]
    #|  moonsightc build <project_dir> [-o <out_dir>]
    #|
  println(usage)
}

///|
/// Strip argv[0] (executable path).
fn cli_args() -> Array[String] {
  let all = @env.args()
  if all.length() <= 1 {
    []
  } else {
    let out : Array[String] = []
    for i in 1..<all.length() {
      out.push(all[i])
    }
    out
  }
}

///|
/// Parse `-o <dir>` from remaining args; default `dist`.
fn out_dir_from(args : ArrayView[String]) -> String {
  let mut i = 0
  while i < args.length() {
    if args[i] == "-o" {
      if i + 1 < args.length() {
        return args[i + 1]
      } else {
        return "dist"
      }
    }
    if args[i].has_prefix("-o=") {
      return args[i][3:].to_owned()
    }
    i = i + 1
  }
  "dist"
}

///|
/// Parse `-o <dir>` from remaining args for `new`; default `.`.
fn parent_dir_from(args : ArrayView[String]) -> String {
  let mut i = 0
  while i < args.length() {
    if args[i] == "-o" {
      if i + 1 < args.length() {
        return args[i + 1]
      } else {
        return "."
      }
    }
    if args[i].has_prefix("-o=") {
      return args[i][3:].to_owned()
    }
    i = i + 1
  }
  "."
}

///|
fn main {
  let args = cli_args()
  let code = match args {
    [] => {
      print_usage()
      1
    }
    ["version", ..] | ["--version", ..] | ["-V", ..] => {
      println("moonsightc 0.9.0-candidate")
      0
    }
    ["help", ..] | ["--help", ..] | ["-h", ..] => {
      print_usage()
      0
    }
    ["new"] => {
      println("error: new requires <name>")
      print_usage()
      1
    }
    ["new", name, .. rest] => cmd_new(name, parent_dir_from(rest))
    ["check"] => {
      println("error: check requires <file.yuki|dir>")
      print_usage()
      1
    }
    ["check", path, ..] => cmd_check(path)
    ["freeze-ids"] => {
      println("error: freeze-ids requires <file.yuki>")
      1
    }
    ["freeze-ids", path, .. rest] => {
      let out = if rest.length() > 0 {
        out_dir_from(rest)
      } else {
        path + ".ids.yuki"
      }
      cmd_freeze_ids(path, out)
    }
    ["build"] => {
      println("error: build requires <project_dir>")
      print_usage()
      1
    }
    ["build", path, .. rest] => cmd_build(path, out_dir_from(rest))
    [cmd, ..] => {
      println("error: unknown command `\{cmd}`")
      print_usage()
      1
    }
  }
  if code != 0 {
    process_exit(code)
  }
}
