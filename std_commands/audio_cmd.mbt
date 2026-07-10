///|
/// `audio.bgm resource` — set Stage BGM mirror and drive the logical mixer.
///
/// Pass `None_` or no args to stop BGM. Volume/loop use mixer defaults (1.0 / looped).
pub fn cmd_audio_bgm(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [Str(resource), ..] => {
      stage.bgm = Some(resource)
      @audio.global_mixer().play_bgm(resource)
      Ok
    }
    [None_, ..] | [] => {
      stage.bgm = None
      @audio.global_mixer().stop_bgm()
      Ok
    }
    _ => Error("audio.bgm: expected resource Str or None_")
  }
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
