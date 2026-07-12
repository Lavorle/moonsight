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

///|
/// Author-owned stable identity used by localized presentation operations.
/// IDs are ASCII, dot-separated identifiers so they remain portable across
/// manifests, save files, catalogs, and Host implementations.
pub(all) struct AuthorId {
  value : String
} derive(Debug, Eq, Hash)

///|
pub(all) suberror AuthorIdError {
  EmptyAuthorId
  InvalidAuthorId(id~ : String, offset~ : Int, message~ : String)
  InvalidLocalizedAuthorId(
    span~ : SourceSpan,
    locale~ : String,
    id~ : String,
    offset~ : Int,
    message~ : String
  )
  MissingAuthorId(span~ : SourceSpan, locale~ : String, kind~ : String)
  DuplicateAuthorId(
    span~ : SourceSpan,
    locale~ : String,
    id~ : String,
    kind~ : String
  )
} derive(Debug, Eq)

///|
/// Parse the Formal-1.0 author-ID grammar:
/// `[A-Za-z_][A-Za-z0-9_-]*(.[A-Za-z_][A-Za-z0-9_-]*)*`.
/// The byte/code-unit offset is stable because the accepted alphabet is ASCII.
pub fn parse_author_id(id : String) -> AuthorId raise AuthorIdError {
  if id == "" {
    raise EmptyAuthorId
  }
  let mut segment_start = true
  for offset = 0; offset < id.length(); offset = offset + 1 {
    guard id.get_char(offset) is Some(c) else { break }
    if segment_start {
      if !(c.is_ascii_alphabetic() || c == '_') {
        raise InvalidAuthorId(
          id~,
          offset~,
          message="segment must start with an ASCII letter or underscore",
        )
      }
      segment_start = false
    } else if c == '.' {
      segment_start = true
    } else if !(c.is_ascii_alphabetic() ||
      c.is_ascii_digit() ||
      c == '_' ||
      c == '-') {
      raise InvalidAuthorId(
        id~,
        offset~,
        message="expected ASCII letter, digit, underscore, hyphen, or dot",
      )
    }
  }
  if segment_start {
    raise InvalidAuthorId(
      id~,
      offset=id.length() - 1,
      message="ID must not end with a dot",
    )
  }
  { value: id }
}
