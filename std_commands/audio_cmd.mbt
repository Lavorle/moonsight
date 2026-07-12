///|
/// `audio.bgm resource [volume=] [fade=]` — set Stage BGM and drive the mixer.
///
/// Named `volume` (default 1.0) is logical gain. Named `fade` (default 0) is a
/// linear wall-clock seconds fade; fire-and-forget via mixer tick.
///
/// Pass `None_` or no positional args to stop BGM (optional `fade=` fades out).
pub fn cmd_audio_bgm(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let (pos, named) = @runtime.split_host_args(args)
  let volume = match named_double(named, "volume") {
    Some(v) => v
    None => 1.0
  }
  let fade = match named_double(named, "fade") {
    Some(v) => v
    None => 0.0
  }
  match pos {
    [Str(resource), ..] => {
      // Empty resource id stops (same as None_).
      if resource == "" {
        return stop_bgm(stage, fade)
      }
      stage.bgm = Some(resource)
      let m = @audio.global_mixer()
      if fade > 0.0 {
        match m.bgm {
          Some(cur) =>
            if cur == resource {
              // Same track: fade volume only (no restart).
              m.fade_bgm_to(volume, fade)
            } else {
              // New track: start silent and fade in.
              m.play_bgm(resource, volume=0.0)
              m.fade_bgm_to(volume, fade)
            }
          None => {
            m.play_bgm(resource, volume=0.0)
            m.fade_bgm_to(volume, fade)
          }
        }
      } else {
        m.play_bgm(resource, volume~)
      }
      Ok
    }
    [None_, ..] | [] => stop_bgm(stage, fade)
    _ => Error("audio.bgm: expected resource Str or None_")
  }
}

///|
fn stop_bgm(stage : @runtime.Stage, fade : Double) -> @runtime.HostResult {
  stage.bgm = None
  let m = @audio.global_mixer()
  if fade > 0.0 && m.bgm is Some(_) {
    m.fade_bgm_to(0.0, fade, stop=true)
  } else {
    m.stop_bgm()
  }
  Ok
}

///|
/// `audio.se resource` — set Stage SE mirror and fire a one-shot via the mixer.
pub fn cmd_audio_se(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [Str(resource), ..] => {
      stage.se = Some(resource)
      @audio.global_mixer().play_se(resource)
      Ok
    }
    _ => Error("audio.se: expected resource Str")
  }
}
