///|
pub(all) enum Severity {
  Error
  Warning
} derive(Debug, Eq)

///|
pub(all) struct Diagnostic {
  severity : Severity
  span : SourceSpan
  message : String
} derive(Debug, Eq)

///|
/// Format a diagnostic for CLI output: `file:line:col: message`.
pub fn Diagnostic::to_cli(self : Diagnostic) -> String {
  "\{self.span.file}:\{self.span.line}:\{self.span.col}: \{self.message}"
}
