///|
/// Parsed MoonYuki compilation unit (one source file).
pub(all) struct ScriptUnit {
  file : String
  externs : Array[ExternDecl]
  macros : Array[MacroDecl]
  scenes : Array[SceneDecl]
} derive(Debug)

///|
pub(all) struct ExternDecl {
  name : String
  params : Array[ParamDecl]
  span : SourceSpan
} derive(Debug)

///|
pub(all) struct ParamDecl {
  name : String
  default : Expr? // optional default
} derive(Debug)

///|
pub(all) struct MacroDecl {
  name : String
  params : Array[ParamDecl]
  body : Array[Stmt]
  span : SourceSpan
} derive(Debug)

///|
pub(all) struct SceneDecl {
  name : String
  /// Parent scene from `inherit "parent"` syntax (`inherit` is a reserved keyword).
  parent : String?
  items : Array[Stmt]
  span : SourceSpan
} derive(Debug)

///|
pub(all) enum Stmt {
  Command(cmd~ : String, args~ : Array[Arg], span~ : SourceSpan)
  Dialogue(speaker~ : String?, text~ : Array[TextPart], span~ : SourceSpan)
} derive(Debug)

///|
pub(all) enum TextPart {
  Literal(String)
  InlineCommand(cmd~ : String, args~ : Array[Arg])
} derive(Debug)

///|
pub(all) enum Arg {
  Positional(Expr)
  Named(name~ : String, Expr)
  Flag(String)
} derive(Debug)

///|
pub(all) enum Expr {
  Int(Int)
  Float(Double)
  Bool(Bool)
  Str(String)
  Ident(String)
} derive(Debug)
