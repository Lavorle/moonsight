///|
/// 1-based source location range within a file.
pub(all) struct SourceSpan {
  file : String
  line : Int // 1-based
  col : Int // 1-based
  end_line : Int
  end_col : Int
} derive(Debug, Eq)
