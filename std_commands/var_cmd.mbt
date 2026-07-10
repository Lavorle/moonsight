///|
/// `var.set name value`
pub fn cmd_var_set(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [Str(name), value, ..] => {
      stage.set_var(name, value)
      Ok
    }
    _ => Error("var.set: expected name Str and value")
  }
}
