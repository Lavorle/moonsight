///|
test "layer.show and trans.fade mutate stage" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("layer.show", stage, [Str("bg"), Str("bg_room")]) == Ok)
  assert_eq(stage.layers.length(), 1)
  assert_eq(stage.layers[0].resource, "bg_room")
  ignore(reg.call("trans.fade", stage, [Float(0.0), Float(1.0), Float(0.3)]))
  assert_eq(stage.overlay_opacity, 1.0)
  assert_eq(stage.fade_to, 1.0)
  assert_eq(stage.fade_duration, 0.3)
}

///|
test "layer.show accepts Int and Float coords" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(
    reg.call("layer.show", stage, [
      Str("c"),
      Str("char_y"),
      Int(10),
      Int(100),
      Float(200.5),
      Float(0.5),
    ]) ==
    Ok,
  )
  assert_eq(stage.layers[0].z, 10)
  assert_eq(stage.layers[0].x, 100.0)
  assert_eq(stage.layers[0].y, 200.5)
  assert_eq(stage.layers[0].opacity, 0.5)
}

///|
test "layer.hide and layer.move" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  ignore(reg.call("layer.show", stage, [Str("c"), Str("char_y")]))
  assert_true(reg.call("layer.move", stage, [Str("c"), Int(1), Int(2)]) == Ok)
  assert_eq(stage.layers[0].x, 1.0)
  assert_eq(stage.layers[0].y, 2.0)
  assert_true(reg.call("layer.hide", stage, [Str("c")]) == Ok)
  assert_eq(stage.layers.length(), 0)
}

///|
test "text begin type end" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("text.begin", stage, [Str("y")]) == Ok)
  assert_true(reg.call("text.type", stage, [Str("Hi")]) == Ok)
  assert_true(reg.call("text.end", stage, []) == Ok)
  guard stage.text is Some(t) else { fail("text") }
  assert_eq(t.full_text, "Hi")
  assert_true(t.complete)
}

///|
test "var.set stores values" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("var.set", stage, [Str("flag"), Bool(true)]) == Ok)
  assert_true(stage.get_var("flag") == Bool(true))
}

///|
test "flow.jump returns JumpScene" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(
    reg.call("flow.jump", stage, [Str("other")]) == JumpScene("other"),
  )
}

///|
test "flow.wait and flow.yield return Yield" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("flow.wait", stage, [Float(0.5)]) == Yield)
  assert_true(reg.call("flow.yield", stage, []) == Yield)
}

///|
test "flow.choice sets options and yields" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("flow.choice", stage, [Str("A"), Str("B")]) == Yield)
  guard stage.choices is Some(c) else { fail("choices") }
  assert_eq(c.options.length(), 2)
  assert_eq(c.options[0], "A")
  assert_eq(c.options[1], "B")
}

///|
test "audio.bgm se and sys.save_hint" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("audio.bgm", stage, [Str("bgm_soft")]) == Ok)
  guard stage.bgm is Some(bgm) else { fail("bgm") }
  assert_eq(bgm, "bgm_soft")
  assert_true(reg.call("audio.se", stage, [Str("click")]) == Ok)
  guard stage.se is Some(se) else { fail("se") }
  assert_eq(se, "click")
  assert_true(reg.call("sys.save_hint", stage, []) == Ok)
  assert_true(stage.save_hint)
}

///|
test "registry keys match script.builtin_externs exactly" {
  let reg = @std_commands.standard_registry()
  let reg_names = reg.registered_names()
  let builtin_names = @script.builtin_externs().map(e => e.name)
  builtin_names.sort()
  assert_eq(reg_names.length(), builtin_names.length())
  for i in 0..<reg_names.length() {
    assert_eq(reg_names[i], builtin_names[i])
  }
  // Also match the canonical list helper.
  let expected = @std_commands.standard_host_names()
  expected.sort()
  assert_eq(reg_names.length(), expected.length())
  for i in 0..<reg_names.length() {
    assert_eq(reg_names[i], expected[i])
  }
}

///|
test "unknown host returns Error" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  guard reg.call("no.such", stage, []) is Error(msg) else {
    fail("expected Error")
  }
  assert_true(msg.contains("no.such"))
}
