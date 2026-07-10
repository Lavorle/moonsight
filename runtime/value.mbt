///|
/// Runtime script value (variables, host args, expression results).
pub(all) enum Value {
  Int(Int)
  Float(Double)
  Bool(Bool)
  Str(String)
  None_
} derive(Debug, Eq)

///|
/// Truthiness used by jump conditions and control flow.
///
/// Falsey: `Bool(false)`, `Int(0)`, `None_`, empty `Str("")`.
/// Everything else (including `Float(0.0)`) is truthy.
pub fn Value::truthy(self : Value) -> Bool {
  match self {
    Bool(b) => b
    Int(0) => false
    None_ => false
    Str("") => false
    _ => true
  }
}
