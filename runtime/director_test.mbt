///|
test "director text.begin type end mutates stage" {
  let stage = @runtime.Stage::new()
  let dir = @runtime.Director::with_builtins()
  assert_true(dir.call("text.begin", stage, [Str("y")]) == Ok)
  assert_true(dir.call("text.type", stage, [Str("Hi")]) == Ok)
  assert_true(dir.call("text.end", stage, []) == Ok)
  guard stage.text is Some(t) else { fail("text") }
  assert_eq(t.full_text, "Hi")
  guard t.speaker is Some("y") else { fail("speaker") }
  // text.end no longer force-completes; typewriter starts incomplete.
  assert_true(!t.complete)
  assert_eq(t.visible_chars, 0)
  stage.complete_text()
  guard stage.text is Some(t2) else { fail("after complete") }
  assert_true(t2.complete)
  assert_eq(t2.visible_chars, t2.full_text.length())
}

///|
test "director layer.show and layer.hide" {
  let stage = @runtime.Stage::new()
  let dir = @runtime.Director::with_builtins()
  assert_true(dir.call("layer.show", stage, [Str("bg"), Str("bg_room")]) == Ok)
  assert_eq(stage.layers.length(), 1)
  assert_eq(stage.layers[0].id, "bg")
  assert_eq(stage.layers[0].resource, "bg_room")
  assert_true(dir.call("layer.hide", stage, [Str("bg")]) == Ok)
  assert_eq(stage.layers.length(), 0)
}

///|
/// `scale=` snaps on show/set when duration is 0; named args use `#:key` packing.
test "builtin layer.show accepts scale named arg" {
  let stage = @runtime.Stage::new()
  let dir = @runtime.Director::with_builtins()
  assert_true(
    dir.call(
      "layer.show",
      stage,
      [
        Str("y"),
        Str("char_y"),
        Str("#:kind"),
        Str("character"),
        Str("#:scale"),
        Float(0.5),
      ],
    ) ==
    Ok,
  )
  assert_eq(stage.layers[0].scale, 0.5)
  assert_true(
    dir.call(
      "layer.set",
      stage,
      [Str("y"), Str("#:scale"), Float(1.0), Str("#:duration"), Float(0.0)],
    ) ==
    Ok,
  )
  assert_eq(stage.layers[0].scale, 1.0)
}

///|
test "director var.set stores values" {
  let stage = @runtime.Stage::new()
  let dir = @runtime.Director::with_builtins()
  assert_true(dir.call("var.set", stage, [Str("flag"), Bool(true)]) == Ok)
  assert_true(stage.get_var("flag") == Bool(true))
}

///|
test "director unknown host returns Error" {
  let stage = @runtime.Stage::new()
  let dir = @runtime.Director::with_builtins()
  guard dir.call("no.such", stage, []) is Error(msg) else {
    fail("expected Error")
  }
  assert_true(msg.contains("no.such"))
}
