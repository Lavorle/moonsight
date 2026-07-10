///|
/// Parsed MoonYuki compilation unit (one source file).
pub(all) struct ScriptUnit {
  file : String
  externs : Array[ExternDecl]
  macros : Array[MacroDecl]
  scenes : Array[SceneDecl]
  screens : Array[ScreenDecl]
} derive(Debug)

///|
/// Top-level `- screen "name"` declaration (Phase 3 UI DSL).
pub(all) struct ScreenDecl {
  name : String
  root_children : Array[ScreenNode]
  span : SourceSpan
} derive(Debug)

///|
/// Screen widget tree node (indent-based body under `- screen`).
pub(all) enum ScreenNode {
  VBox(x~ : Double?, y~ : Double?, children~ : Array[ScreenNode], span~ : SourceSpan)
  HBox(x~ : Double?, y~ : Double?, children~ : Array[ScreenNode], span~ : SourceSpan)
  Fixed(
    x~ : Double,
    y~ : Double,
    w~ : Double?,
    h~ : Double?,
    children~ : Array[ScreenNode],
    span~ : SourceSpan,
  )
  Text(src~ : ScreenTextSrc, span~ : SourceSpan)
  Button(label~ : String, action~ : ScreenActionAst, span~ : SourceSpan)
} derive(Debug)

///|
pub(all) enum ScreenTextSrc {
  Literal(String)
  SlotLabel(Int)
  Pref(String)
} derive(Debug)

///|
/// Closed action set for buttons. Lowering validates / maps to runtime IR.
pub(all) enum ScreenActionAst {
  Return
  StartGame
  QuitToTitle
  ShowScreen(name~ : String, mode~ : String?) // mode: "save" | "load" | None
  HideScreen(name~ : String?)
  SaveSlot(Int)
  LoadSlot(Int)
  SetPref(key~ : String, value~ : Expr)
  AdjustPref(key~ : String, delta~ : Double)
  Noop
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
