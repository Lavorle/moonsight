///|
/// `sys.save_hint` — marks a safe save point (consumed by Task 9 save flow).
pub fn cmd_sys_save_hint(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  ignore(args)
  stage.save_hint = true
  Ok
}
