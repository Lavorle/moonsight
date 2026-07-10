///|
/// MoonYuki token kinds produced by the line-oriented lexer.
pub(all) enum TokenKind {
  Minus // leading "-" declaration
  At // "@" command
  Colon
  Ident(String)
  StringLit(String)
  IntLit(Int)
  FloatLit(Double)
  BoolLit(Bool)
  Flag(String) // --force style without value handled as Flag
  Newline
  Eof
  // dialogue-related emitted by line classifier
  DialogueSpeaker(String)
  DialogueText(String)
  Error(String)
} derive(Debug, Eq)

///|
pub(all) struct Token {
  kind : TokenKind
  span : SourceSpan
} derive(Debug, Eq)
