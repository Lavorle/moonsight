///|
/// `ui.show name [mode=save|load]` — push a modal screen (drained by Engine).
///
/// Yields so the narrative VM pauses while the screen stack is non-empty.
pub fn cmd_ui_show(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let (pos, named) = @runtime.split_host_args(args)
  match pos {
    [Str(name), ..] => {
      let mode : String? = match named.get("mode") {
        Some(Str(m)) => Some(m)
        _ => None
      }
      stage.ui_ops.push(@runtime.UiHostOp::Show(name~, mode~))
      Yield
    }
    _ => Error("ui.show: expected name Str")
  }
}

///|
/// `ui.hide [name]` — pop top screen, or remove matching name when given.
pub fn cmd_ui_hide(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let (pos, _) = @runtime.split_host_args(args)
  match pos {
    [] => {
      stage.ui_ops.push(@runtime.UiHostOp::Hide(name=None))
      Ok
    }
    [Str(name), ..] => {
      stage.ui_ops.push(@runtime.UiHostOp::Hide(name=Some(name)))
      Ok
    }
    _ => Error("ui.hide: expected optional name Str")
  }
}
