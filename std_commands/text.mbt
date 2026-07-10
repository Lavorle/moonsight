///|
/// `text.begin [speaker]`
pub fn cmd_text_begin(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [] | [None_] => {
      stage.begin_text()
      Ok
    }
    [Str(s), ..] => {
      stage.begin_text(speaker=s)
      Ok
    }
    _ => Error("text.begin: expected speaker Str or None_")
  }
}

///|
/// `text.type chunk`
pub fn cmd_text_type(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [Str(chunk), ..] => {
      stage.type_more(chunk)
      Ok
    }
    _ => Error("text.type: expected Str chunk")
  }
}

///|
/// `text.end` — mark current dialogue block complete.
pub fn cmd_text_end(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  ignore(args)
  stage.complete_text()
  Ok
}
