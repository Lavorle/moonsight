///|
test "expand pause macro into wait command" {
  let src =
    #|- extern wait time=1
    #|- macro pause time=1
    #|@wait time
    #|
    #|- scene "s"
    #|@pause 3
    #|
  let unit = @script.parse_source(src, file="t.yuki")
  let expanded = @script.expand_macros(unit)
  // scene should contain @wait with time=3
  guard expanded.scenes[0].items is [Command(cmd="wait", args~, ..), ..] else {
    fail("expected wait command")
  }
  // assert args encode time 3
  guard args is [Positional(Int(3))] else {
    fail("expected positional Int(3) after param subst")
  }
  assert_eq(expanded.scenes[0].items.length(), 1)
  assert_eq(expanded.file, "t.yuki")
}

///|
test "expand uses macro default when arg omitted" {
  let src =
    #|- extern wait time=1
    #|- macro pause time=1
    #|@wait time
    #|
    #|- scene "s"
    #|@pause
    #|
  let unit = @script.parse_source(src, file="t.yuki")
  let expanded = @script.expand_macros(unit)
  guard expanded.scenes[0].items is [Command(cmd="wait", args~, ..)] else {
    fail("expected wait")
  }
  guard args is [Positional(Int(1))] else { fail("default time=1") }
}

///|
test "expand binds named macro args" {
  let src =
    #|- extern wait time=1
    #|- macro pause time=1
    #|@wait time
    #|
    #|- scene "s"
    #|@pause time=7
    #|
  let unit = @script.parse_source(src, file="t.yuki")
  let expanded = @script.expand_macros(unit)
  guard expanded.scenes[0].items is [Command(cmd="wait", args~, ..)] else {
    fail("expected wait")
  }
  guard args is [Positional(Int(7))] else { fail("named time=7") }
}

///|
test "expand errors on recursive macro depth limit" {
  let src =
    #|- macro loop
    #|@loop
    #|
    #|- scene "s"
    #|@loop
    #|
  let unit = @script.parse_source(src, file="rec.yuki")
  try @script.expand_macros(unit) catch {
    err => {
      guard err is RecursionLimit(name~, ..) else {
        fail("expected RecursionLimit")
      }
      assert_eq(name, "loop")
    }
  } noraise {
    _ => fail("expected macro recursion error")
  }
}
