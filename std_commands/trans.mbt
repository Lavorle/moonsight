///|
/// `trans.fade from to duration` — Phase 1 applies `to` immediately and
/// records duration for a later animation system.
pub fn cmd_trans_fade(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [from, to, duration, ..] =>
      match
        (
          @runtime.value_as_double(from),
          @runtime.value_as_double(to),
          @runtime.value_as_double(duration),
        ) {
        (Some(f), Some(t), Some(d)) => {
          ignore(f)
          stage.fade_to = t
          stage.fade_duration = d
          stage.overlay_opacity = t
          Ok
        }
        _ => Error("trans.fade: expected from/to/duration numbers")
      }
    [from, to] =>
      match (@runtime.value_as_double(from), @runtime.value_as_double(to)) {
        (Some(f), Some(t)) => {
          ignore(f)
          stage.fade_to = t
          stage.fade_duration = 0.0
          stage.overlay_opacity = t
          Ok
        }
        _ => Error("trans.fade: expected from/to numbers")
      }
    [to] =>
      match @runtime.value_as_double(to) {
        Some(t) => {
          stage.fade_to = t
          stage.fade_duration = 0.0
          stage.overlay_opacity = t
          Ok
        }
        None => Error("trans.fade: expected numeric to")
      }
    _ => Error("trans.fade: expected from to duration")
  }
}
