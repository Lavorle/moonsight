///|
/// `audio.bgm resource` — record logical BGM id on Stage (mixer in Task 13).
pub fn cmd_audio_bgm(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [Str(resource), ..] => {
      stage.bgm = Some(resource)
      Ok
    }
    [None_, ..] | [] => {
      stage.bgm = None
      Ok
    }
    _ => Error("audio.bgm: expected resource Str or None_")
  }
}

///|
/// `audio.se resource` — record logical SE id on Stage.
pub fn cmd_audio_se(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [Str(resource), ..] => {
      stage.se = Some(resource)
      Ok
    }
    _ => Error("audio.se: expected resource Str")
  }
}
