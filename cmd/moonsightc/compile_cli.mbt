///|
/// Format a compile pipeline error as `file:line:col: message`.
fn format_compile_error(err : @script.CompileError) -> String {
  match err {
    Parse(@script.ParseError(span~, message~)) =>
      "\{span.file}:\{span.line}:\{span.col}: \{message}"
    Macro(@script.RecursionLimit(name~, span~)) =>
      "\{span.file}:\{span.line}:\{span.col}: macro recursion limit: \{name}"
    Resolve(@script.UnknownCommand(name~, span~)) =>
      "\{span.file}:\{span.line}:\{span.col}: unknown command `\{name}`"
    Resolve(@script.DuplicateScene(name~, span~)) =>
      "\{span.file}:\{span.line}:\{span.col}: duplicate scene `\{name}`"
    Resolve(@script.UnknownParent(name~, parent~, span~)) =>
      "\{span.file}:\{span.line}:\{span.col}: scene `\{name}` unknown parent `\{parent}`"
    Bytecode(e) => "bytecode error: \{to_repr(e)}"
    AuthorId(@script.MissingAuthorId(span~, locale~, kind~)) =>
      "\{span.file}:\{span.line}:\{span.col}: missing author ID for \{kind} in locale `\{locale}`"
    AuthorId(@script.DuplicateAuthorId(span~, locale~, id~, kind~)) =>
      "\{span.file}:\{span.line}:\{span.col}: duplicate \{kind} ID `\{id}` in locale `\{locale}`"
    AuthorId(
      @script.InvalidLocalizedAuthorId(span~, locale~, id~, offset~, message~)
    ) =>
      "\{span.file}:\{span.line}:\{span.col}: invalid author ID `\{id}` at offset \{offset} in locale `\{locale}`: \{message}"
    AuthorId(e) => "author ID error: \{to_repr(e)}"
  }
}

///|
/// Collect `.yuki` files under `root` (file or directory), sorted for stability.
fn collect_yuki_files(root : String) -> Array[String] raise IoError {
  let out : Array[String] = []
  collect_yuki_into(root, out)
  out.sort()
  out
}

///|
fn collect_yuki_into(path : String, out : Array[String]) -> Unit raise IoError {
  if is_dir(path) {
    for name in read_dir(path) {
      collect_yuki_into(join_path(path, name), out)
    }
  } else if has_extension(path, ".yuki") {
    out.push(path)
  }
}

///|
/// Compile one source file to IR.
fn compile_file_to_ir(path : String) -> @script.IrModule raise IoError {
  let src = read_file_to_string(path)
  @script.compile_to_ir(src, file=path) catch {
    e => raise IoError(format_compile_error(e))
  }
}

///|
/// Compile many `.yuki` files and merge scenes into one module.
///
/// `entry_file` (relative or absolute) picks the module entry scene from that
/// file's IR when present; otherwise falls back to `"entrypoint"` / first scene.
fn compile_yuki_paths(
  paths : ArrayView[String],
  entry_file? : String,
) -> @script.IrModule raise IoError {
  guard paths.length() > 0 else { raise IoError("no .yuki sources found") }
  let scenes : Map[String, @script.IrScene] = {}
  let mut entry = "entrypoint"
  let mut entry_set = false
  let entry_abs = match entry_file {
    Some(f) => Some(normalize_path_key(f))
    None => None
  }
  for path in paths {
    let ir = compile_file_to_ir(path)
    for name, scene in ir.scenes {
      if scenes.contains(name) {
        raise IoError("duplicate scene `\{name}` from \{path}")
      }
      scenes[name] = scene
    }
    match entry_abs {
      Some(ef) =>
        if normalize_path_key(path) == ef || basename(path) == basename(ef) {
          entry = ir.entry
          entry_set = true
        }
      None => ()
    }
    if !entry_set {
      // Prefer an explicit entrypoint scene from any file.
      if ir.scenes.contains("entrypoint") {
        entry = "entrypoint"
        entry_set = true
      } else if !entry_set && paths.length() == 1 {
        entry = ir.entry
        entry_set = true
      }
    }
  }
  if !entry_set {
    if scenes.contains("entrypoint") {
      entry = "entrypoint"
    } else {
      for name, _ in scenes {
        entry = name
        break
      }
    }
  }
  if !scenes.contains(entry) {
    raise IoError("entry scene `\{entry}` not found after compile")
  }
  { scenes, entry }
}

///|
/// Compile and merge sources while preserving author-owned stable IDs for the
/// MSB2 stable-operation section. Legacy sources remain valid and simply
/// contribute no stable-operation entries.
fn compile_yuki_paths_with_ids(
  paths : ArrayView[String],
  entry_file? : String,
  locale? : String,
  require_explicit_ids? : Bool = false,
) -> @script.IdentifiedIrModule raise IoError {
  guard paths.length() > 0 else { raise IoError("no .yuki sources found") }
  let scenes : Map[String, @script.IrScene] = {}
  let stable_operations : Array[@script.StableOperationId] = []
  let mut entry = "entrypoint"
  let mut entry_set = false
  let entry_abs = match entry_file {
    Some(f) => Some(normalize_path_key(f))
    None => None
  }
  for path in paths {
    let src = read_file_to_string(path)
    let identified = if require_explicit_ids {
      @script.compile_localized_to_identified_ir(
        src,
        file=path,
        locale=locale.or("und"),
        require_explicit_ids=true,
      )
    } else {
      @script.compile_to_identified_ir(src, file=path)
    } catch {
      e => raise IoError(format_compile_error(e))
    }
    for name, scene in identified.ir.scenes {
      if scenes.contains(name) {
        raise IoError("duplicate scene `\{name}` from \{path}")
      }
      scenes[name] = scene
    }
    stable_operations.append(identified.stable_operations)
    match entry_abs {
      Some(ef) =>
        if normalize_path_key(path) == ef || basename(path) == basename(ef) {
          entry = identified.ir.entry
          entry_set = true
        }
      None => ()
    }
    if !entry_set {
      if identified.ir.scenes.contains("entrypoint") {
        entry = "entrypoint"
        entry_set = true
      } else if paths.length() == 1 {
        entry = identified.ir.entry
        entry_set = true
      }
    }
  }
  if !entry_set {
    if scenes.contains("entrypoint") {
      entry = "entrypoint"
    } else {
      for name, _ in scenes {
        entry = name
        break
      }
    }
  }
  if !scenes.contains(entry) {
    raise IoError("entry scene `\{entry}` not found after compile")
  }
  { ir: { scenes, entry }, stable_operations }
}

///|
/// Normalize path for comparison (strip leading `./`).
fn normalize_path_key(path : String) -> String {
  if path.has_prefix("./") {
    path[2:].to_owned()
  } else {
    path
  }
}
