///|
/// Errors from the full parse → expand → resolve → lower → encode pipeline.
pub(all) suberror CompileError {
  Parse(ParseError)
  Macro(MacroError)
  Resolve(ResolveError)
  Screen(ScreenLowerError)
  Bytecode(BytecodeError)
} derive(Debug, Eq)

///|
/// Output of `compile_source`: IR, MSB1 bytes, and diagnostics.
pub(all) struct CompileResult {
  ir : IrModule
  bytecode : Bytes
  diags : Array[Diagnostic]
} derive(Debug)

///|
/// Narrative IR plus lowered screen defs from one source file.
pub(all) struct CompileBundle {
  ir : IrModule
  screens : Array[ScreenDef]
} derive(Debug)

///|
/// Full pipeline: parse → expand macros → resolve → lower → encode.
pub fn compile_source(
  src : String,
  file~ : String,
) -> CompileResult raise CompileError {
  let ir = compile_to_ir(src, file~)
  let bytecode = encode_module(ir)
  { ir, bytecode, diags: [] }
}

///|
/// Parse → expand → resolve → lower (no encode). Used by tests and VM hosts.
///
/// Screens in the source are ignored; use `compile_screens` / `compile_bundle`
/// when screen IR is needed.
pub fn compile_to_ir(
  src : String,
  file~ : String,
) -> IrModule raise CompileError {
  let unit = parse_source(src, file~) catch { e => raise Parse(e) }
  let expanded = expand_macros(unit) catch { e => raise Macro(e) }
  let resolved = resolve_unit(expanded, builtin_externs()) catch {
    e => raise Resolve(e)
  }
  lower_unit(resolved)
}

///|
/// Parse → expand → lower only screens (no scene resolve / IR).
pub fn compile_screens(
  src : String,
  file~ : String,
) -> Array[ScreenDef] raise CompileError {
  let unit = parse_source(src, file~) catch { e => raise Parse(e) }
  let expanded = expand_macros(unit) catch { e => raise Macro(e) }
  lower_screens(expanded.screens) catch { e => raise Screen(e) }
}

///|
/// Parse → expand → resolve → lower scenes and screens together.
pub fn compile_bundle(
  src : String,
  file~ : String,
) -> CompileBundle raise CompileError {
  let unit = parse_source(src, file~) catch { e => raise Parse(e) }
  let expanded = expand_macros(unit) catch { e => raise Macro(e) }
  let resolved = resolve_unit(expanded, builtin_externs()) catch {
    e => raise Resolve(e)
  }
  let ir = lower_unit(resolved)
  let screens = lower_screens(expanded.screens) catch { e => raise Screen(e) }
  { ir, screens }
}
