///|
/// Errors from the full parse → expand → resolve → lower → encode pipeline.
pub(all) suberror CompileError {
  Parse(ParseError)
  Macro(MacroError)
  Resolve(ResolveError)
  Bytecode(BytecodeError)
  AuthorId(AuthorIdError)
} derive(Debug, Eq)

///|
/// Output of `compile_source`: IR, MSB1 bytes, and diagnostics.
pub(all) struct CompileResult {
  ir : IrModule
  bytecode : Bytes
  diags : Array[Diagnostic]
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
/// Compile while preserving explicit author identity metadata.
pub fn compile_to_identified_ir(
  src : String,
  file~ : String,
) -> IdentifiedIrModule raise CompileError {
  let unit = parse_source(src, file~) catch { e => raise CompileError::Parse(e) }
  let expanded = expand_macros(unit) catch { e => raise CompileError::Macro(e) }
  let resolved = resolve_unit(expanded, builtin_externs()) catch {
    e => raise CompileError::Resolve(e)
  }
  lower_unit_with_ids(resolved) catch { e => raise CompileError::AuthorId(e) }
}
