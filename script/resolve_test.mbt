///|
test "resolve rejects unknown command" {
  let src =
    #|- scene "s"
    #|@no_such 1
    #|
  let unit = @script.expand_macros(@script.parse_source(src, file="t.yuki"))
  try @script.resolve_unit(unit, @script.builtin_externs()) catch {
    UnknownCommand(name~, ..) => assert_eq(name, "no_such")
    other => fail("unexpected resolve error: \{to_repr(other)}")
  } noraise {
    _ => fail("expected UnknownCommand")
  }
}

///|
test "resolve accepts file extern and builtin" {
  let src =
    #|- extern wait time=1
    #|- scene "s"
    #|@wait 1
    #|@text.begin
    #|
  let unit = @script.expand_macros(@script.parse_source(src, file="t.yuki"))
  let resolved = @script.resolve_unit(unit, @script.builtin_externs())
  assert_eq(resolved.file, "t.yuki")
  assert_eq(resolved.scenes.length(), 1)
  assert_eq(resolved.scenes[0].name, "s")
  assert_true(resolved.externs.contains("wait"))
  assert_true(resolved.externs.contains("text.begin"))
  assert_true(resolved.scene_table.contains("s"))
  assert_eq(resolved.scene_table["s"], 0)
}

///|
test "resolve rejects duplicate scene names" {
  let src =
    #|- scene "s"
    #|@text.begin
    #|- scene "s"
    #|@text.end
    #|
  let unit = @script.expand_macros(@script.parse_source(src, file="dup.yuki"))
  try @script.resolve_unit(unit, @script.builtin_externs()) catch {
    DuplicateScene(name~, ..) => assert_eq(name, "s")
    other => fail("unexpected resolve error: \{to_repr(other)}")
  } noraise {
    _ => fail("expected DuplicateScene")
  }
}

///|
test "resolve rejects unknown parent scene" {
  let src =
    #|- scene "child" inherit "missing"
    #|@text.begin
    #|
  let unit = @script.expand_macros(@script.parse_source(src, file="inh.yuki"))
  try @script.resolve_unit(unit, @script.builtin_externs()) catch {
    UnknownParent(parent~, name~, ..) => {
      assert_eq(name, "child")
      assert_eq(parent, "missing")
    }
    other => fail("unexpected resolve error: \{to_repr(other)}")
  } noraise {
    _ => fail("expected UnknownParent")
  }
}

///|
test "resolve accepts valid parent scene" {
  let src =
    #|- scene "parent"
    #|@text.begin
    #|- scene "child" inherit "parent"
    #|@text.end
    #|
  let unit = @script.expand_macros(@script.parse_source(src, file="inh.yuki"))
  let resolved = @script.resolve_unit(unit, @script.builtin_externs())
  assert_eq(resolved.scenes.length(), 2)
  guard resolved.scenes[1].parent is Some("parent") else { fail("parent kept") }
  assert_true(resolved.scene_table.contains("parent"))
  assert_true(resolved.scene_table.contains("child"))
}

///|
test "builtin_externs covers std host names" {
  let builtins = @script.builtin_externs()
  let names = Map::from_iter(builtins.map(e => (e.name, true)).iter())
  for
    need in [
      "text.begin", "text.type", "text.end", "flow.jump", "flow.yield", "flow.choice",
      "flow.wait", "layer.show", "layer.hide", "layer.move", "trans.fade", "var.set",
      "audio.bgm", "audio.se", "sys.save_hint",
    ] {
    assert_true(names.contains(need), msg="missing builtin \{need}")
  }
}
