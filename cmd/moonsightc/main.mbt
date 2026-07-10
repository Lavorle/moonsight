///|
/// moonsightc — MoonSight project checker / web dist builder.
///
/// ```
/// moonsightc version
/// moonsightc check <file.yuki|dir>
/// moonsightc build <project_dir> -o <out_dir>
/// ```

///|
extern "C" fn process_exit(code : Int) -> Unit = "exit"

///|
fn print_usage() -> Unit {
  let usage =
    #|usage: moonsightc <check|build|version> ...
    #|  moonsightc version
    #|  moonsightc check <file.yuki|dir>
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
fn main {
  let args = cli_args()
  let code = match args {
    [] => {
      print_usage()
      1
    }
    ["version", ..] | ["--version", ..] | ["-V", ..] => {
      println("moonsightc 0.1.0")
      0
    }
    ["help", ..] | ["--help", ..] | ["-h", ..] => {
      print_usage()
      0
    }
    ["check"] => {
      println("error: check requires <file.yuki|dir>")
      print_usage()
      1
    }
    ["check", path, ..] => cmd_check(path)
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
