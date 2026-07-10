///|
test "parse scene with dialogue and command" {
  let src =
    #|- scene "intro"
    #|y:Hello
    #|@wait 1
    #|
  let unit = @script.parse_source(src, file="t.yuki")
  guard unit.scenes.length() == 1 else { fail("one scene") }
  assert_eq(unit.scenes[0].name, "intro")
  assert_eq(unit.scenes[0].items.length(), 2)
  assert_eq(unit.file, "t.yuki")
  assert_eq(unit.externs.length(), 0)
  assert_eq(unit.macros.length(), 0)
  // dialogue then command
  guard unit.scenes[0].items[0] is Dialogue(speaker~, text~, ..) else {
    fail("expected dialogue")
  }
  guard speaker is Some("y") else { fail("speaker y") }
  guard text is [Literal(lit), ..] else { fail("expected literal text") }
  assert_eq(lit, "Hello")
  guard unit.scenes[0].items[1] is Command(cmd~, args~, ..) else {
    fail("expected command")
  }
  assert_eq(cmd, "wait")
  guard args is [Positional(Int(n))] else { fail("expected positional 1") }
  assert_eq(n, 1)
}

///|
test "parse extern macro scene dialogue command" {
  let src =
    #|- extern wait time=1
    #|- macro pause time=1
    #|@wait time
    #|
    #|- scene "intro"
    #|y:Hello [wait --time 1]
    #|@pause 2
    #|
  let unit = @script.parse_source(src, file="t.yuki")
  assert_eq(unit.externs.length(), 1)
  assert_eq(unit.macros.length(), 1)
  assert_eq(unit.scenes.length(), 1)

  // extern wait time=1
  assert_eq(unit.externs[0].name, "wait")
  assert_eq(unit.externs[0].params.length(), 1)
  assert_eq(unit.externs[0].params[0].name, "time")
  guard unit.externs[0].params[0].default is Some(Int(d)) else {
    fail("extern default")
  }
  assert_eq(d, 1)

  // macro pause time=1 { @wait time }
  assert_eq(unit.macros[0].name, "pause")
  assert_eq(unit.macros[0].params.length(), 1)
  assert_eq(unit.macros[0].params[0].name, "time")
  assert_eq(unit.macros[0].body.length(), 1)
  guard unit.macros[0].body[0] is Command(cmd~, args~, ..) else {
    fail("macro body command")
  }
  assert_eq(cmd, "wait")
  guard args is [Positional(Ident(p))] else { fail("macro arg ref") }
  assert_eq(p, "time")

  // scene body: dialogue with inline + @pause 2
  assert_eq(unit.scenes[0].name, "intro")
  assert_eq(unit.scenes[0].items.length(), 2)
  guard unit.scenes[0].items[0] is Dialogue(text~, ..) else {
    fail("scene dialogue")
  }
  // Hello [wait --time 1] → Literal + InlineCommand
  guard text.length() >= 2 else { fail("expected text parts with inline") }
  guard text[0] is Literal(lit) else { fail("literal prefix") }
  assert_true(lit.has_prefix("Hello"))
  guard text[1] is InlineCommand(cmd=icmd, args=iargs) else {
    fail("inline command")
  }
  assert_eq(icmd, "wait")
  guard iargs is [Flag("time"), Positional(Int(1))] else {
    fail("expected [Flag(time), Positional(Int(1))]")
  }

  guard unit.scenes[0].items[1] is Command(cmd=pcmd, args=pargs, ..) else {
    fail("pause command")
  }
  assert_eq(pcmd, "pause")
  guard pargs is [Positional(Int(pn))] else { fail("pause arg") }
  assert_eq(pn, 2)
}

///|
test "parse multi-param extern without defaults" {
  let src =
    #|- extern f a b
    #|
  let unit = @script.parse_source(src, file="multi.yuki")
  assert_eq(unit.externs.length(), 1)
  assert_eq(unit.externs[0].name, "f")
  assert_eq(unit.externs[0].params.length(), 2)
  assert_eq(unit.externs[0].params[0].name, "a")
  guard unit.externs[0].params[0].default is None else {
    fail("param a should have no default")
  }
  assert_eq(unit.externs[0].params[1].name, "b")
  guard unit.externs[0].params[1].default is None else {
    fail("param b should have no default")
  }
}

///|
test "parse named args flags and scene inherit" {
  let src =
    #|- scene "child" inherit "parent"
    #|@foo bar=1 --force
    #|@set x=1.5 flag=true name="hi"
    #|
  let unit = @script.parse_source(src, file="inh.yuki")
  guard unit.scenes.length() == 1 else { fail("one scene") }
  assert_eq(unit.scenes[0].name, "child")
  guard unit.scenes[0].parent is Some("parent") else {
    fail("expected inherit parent")
  }
  assert_eq(unit.scenes[0].items.length(), 2)

  guard unit.scenes[0].items[0] is Command(cmd~, args~, ..) else {
    fail("foo cmd")
  }
  assert_eq(cmd, "foo")
  guard args is [Named(name=n, Int(v)), Flag(f)] else {
    fail("named+flag args")
  }
  assert_eq(n, "bar")
  assert_eq(v, 1)
  assert_eq(f, "force")

  guard unit.scenes[0].items[1] is Command(args=sargs, ..) else {
    fail("set cmd")
  }
  guard sargs
    is [
      Named(name="x", Float(fv)),
      Named(name="flag", Bool(true)),
      Named(name="name", Str(sv)),
    ] else {
    fail("set named args")
  }
  assert_eq(fv, 1.5)
  assert_eq(sv, "hi")
}

///|
test "parse error on unexpected top-level command" {
  let src =
    #|@wait 1
    #|
  try @script.parse_source(src, file="bad.yuki") catch {
    err => {
      guard err is ParseError(message~, span~) else {
        fail("expected ParseError")
      }
      assert_eq(span.file, "bad.yuki")
      assert_true(message.has_prefix("expected top-level"))
    }
  } noraise {
    _ => fail("expected parse error")
  }
}

///|
test "parse minimal title screen" {
  let src =
    #|- screen "title"
    #|  vbox:
    #|    text "MoonSight"
    #|    button "Start" action=start_game
    #|
  let unit = @script.parse_source(src, file="t.yuki")
  assert_eq(unit.screens.length(), 1)
  assert_eq(unit.screens[0].name, "title")
  assert_eq(unit.screens[0].root_children.length(), 1)
  guard unit.screens[0].root_children[0] is VBox(children~, ..) else {
    fail("expected root vbox")
  }
  assert_eq(children.length(), 2)
  guard children[0] is Text(src~, ..) else { fail("expected text child") }
  guard src is Literal(lit) else { fail("expected literal text") }
  assert_eq(lit, "MoonSight")
  guard children[1] is Button(label~, action~, ..) else {
    fail("expected button child")
  }
  assert_eq(label, "Start")
  guard action is StartGame else { fail("expected start_game action") }
}

///|
test "parse screen actions attrs and text bindings" {
  let src =
    #|- screen "menu"
    #|  vbox x=760 y=360:
    #|    text slot_label(0)
    #|    text pref("master_volume")
    #|    button "Load" action=show_screen("save_load", mode=load)
    #|    button "Back" action=return
    #|    button "Save" action=save_slot(1)
    #|  fixed x=10 y=20 w=100 h=50:
    #|    button "X" action=noop
    #|
  let unit = @script.parse_source(src, file="menu.yuki")
  assert_eq(unit.screens.length(), 1)
  assert_eq(unit.screens[0].root_children.length(), 2)
  guard unit.screens[0].root_children[0]
    is VBox(x~, y~, children~, ..) else {
    fail("vbox")
  }
  guard x is Some(760.0) else { fail("vbox x") }
  guard y is Some(360.0) else { fail("vbox y") }
  assert_eq(children.length(), 5)
  guard children[0] is Text(src=SlotLabel(0), ..) else { fail("slot_label") }
  guard children[1] is Text(src=Pref(pk), ..) else { fail("pref text") }
  assert_eq(pk, "master_volume")
  guard children[2] is Button(action=ShowScreen(name~, mode~), ..) else {
    fail("show_screen")
  }
  assert_eq(name, "save_load")
  guard mode is Some("load") else { fail("mode=load") }
  guard children[3] is Button(action=Return, ..) else { fail("return") }
  guard children[4] is Button(action=SaveSlot(1), ..) else { fail("save_slot") }
  guard unit.screens[0].root_children[1]
    is Fixed(x=fx, y=fy, w~, h~, children=fc, ..) else {
    fail("fixed")
  }
  assert_eq(fx, 10.0)
  assert_eq(fy, 20.0)
  guard w is Some(100.0) else { fail("w") }
  guard h is Some(50.0) else { fail("h") }
  assert_eq(fc.length(), 1)
}
