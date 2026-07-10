///|
/// `trans.fade from to duration` — sets overlay start/`fade_to`/`fade_remaining`.
///
/// When `duration > 0`, opacity starts at `from` and the engine eases toward
/// `fade_to` over wall-clock `duration` seconds. Zero/omitted duration snaps to `to`.
/// Clears any in-flight dissolve so simple fade is not dual-phase.
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
          stage.dissolve_phase = 0
          stage.dissolve_total = 0.0
          stage.fade_to = t
          if d <= 0.0 {
            stage.overlay_opacity = t
            stage.fade_remaining = 0.0
          } else {
            stage.overlay_opacity = f
            stage.fade_remaining = d
          }
          Ok
        }
        _ => Error("trans.fade: expected from/to/duration numbers")
      }
    [from, to] =>
      match (@runtime.value_as_double(from), @runtime.value_as_double(to)) {
        (Some(_f), Some(t)) => {
          stage.dissolve_phase = 0
          stage.dissolve_total = 0.0
          stage.fade_to = t
          stage.fade_remaining = 0.0
          stage.overlay_opacity = t
          Ok
        }
        _ => Error("trans.fade: expected from/to numbers")
      }
    [to] =>
      match @runtime.value_as_double(to) {
        Some(t) => {
          stage.dissolve_phase = 0
          stage.dissolve_total = 0.0
          stage.fade_to = t
          stage.fade_remaining = 0.0
          stage.overlay_opacity = t
          Ok
        }
        None => Error("trans.fade: expected numeric to")
      }
    _ => Error("trans.fade: expected from to duration")
  }
}

///|
/// `trans.dissolve duration` — full-screen veil 0→1→0 over `duration` seconds.
///
/// Does not Yield (same as fade); pair with `@flow.wait` to hold the script.
/// `duration <= 0` clears the veil immediately.
pub fn cmd_trans_dissolve(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let d = match args {
    [v, ..] =>
      match @runtime.value_as_double(v) {
        Some(x) => x
        None => return Error("trans.dissolve: expected duration number")
      }
    _ => return Error("trans.dissolve: expected duration")
  }
  if d <= 0.0 {
    stage.dissolve_phase = 0
    stage.dissolve_total = 0.0
    stage.overlay_opacity = 0.0
    stage.fade_to = 0.0
    stage.fade_remaining = 0.0
  } else {
    stage.dissolve_phase = 1
    stage.dissolve_total = d
    stage.fade_to = 1.0
    stage.overlay_opacity = 0.0
    stage.fade_remaining = d
  }
  Ok
}
