///|
test "lower screen actions" {
  let src =
    #|- screen "title"
    #|  vbox:
    #|    button "Start" action=start_game
    #|    button "Load" action=show_screen("save_load", mode=load)
    #|
  let screens = @script.compile_screens(src, file="t.yuki")
  assert_eq(screens.length(), 1)
  assert_eq(screens[0].name, "title")
  guard screens[0].root is VBox(children~, ..) else { fail("expected root vbox") }
  assert_eq(children.length(), 2)
  guard children[0] is Button(label=l0, action=a0) else { fail("Start button") }
  assert_eq(l0, "Start")
  guard a0 is StartGame else { fail("StartGame") }
  guard children[1] is Button(label=l1, action=a1) else { fail("Load button") }
  assert_eq(l1, "Load")
  guard a1 is ShowScreen(name~, mode~) else { fail("ShowScreen") }
  assert_eq(name, "save_load")
  guard mode is Some("load") else { fail("mode=load") }
}

///|
test "lower set_pref float and bool; adjust_pref" {
  let src =
    #|- screen "settings"
    #|  vbox:
    #|    button "Vol" action=set_pref("master_volume", 0.8)
    #|    button "Mute" action=set_pref("muted", true)
    #|    button "Up" action=adjust_pref("master_volume", 0.1)
    #|    button "Int" action=set_pref("slot_cap", 6)
    #|
  let screens = @script.compile_screens(src, file="s.yuki")
  assert_eq(screens.length(), 1)
  guard screens[0].root is VBox(children~, ..) else { fail("vbox") }
  assert_eq(children.length(), 4)
  guard children[0] is Button(action=SetPrefF(key=k0, value=v0), ..) else {
    fail("SetPrefF")
  }
  assert_eq(k0, "master_volume")
  assert_eq(v0, 0.8)
  guard children[1] is Button(action=SetPrefB(key=k1, value=v1), ..) else {
    fail("SetPrefB")
  }
  assert_eq(k1, "muted")
  assert_eq(v1, true)
  guard children[2] is Button(action=AdjustPref(key=k2, delta~), ..) else {
    fail("AdjustPref")
  }
  assert_eq(k2, "master_volume")
  assert_eq(delta, 0.1)
  guard children[3] is Button(action=SetPrefF(key=k3, value=v3), ..) else {
    fail("int→SetPrefF")
  }
  assert_eq(k3, "slot_cap")
  assert_eq(v3, 6.0)
}

///|
test "lower rejects invalid show_screen mode" {
  let src =
    #|- screen "bad"
    #|  vbox:
    #|    button "X" action=show_screen("save_load", mode=edit)
    #|
  try @script.compile_screens(src, file="bad.yuki") catch {
    err => {
      guard err is Screen(InvalidShowMode(mode~, ..)) else {
        fail("expected InvalidShowMode, got \{to_repr(err)}")
      }
      assert_eq(mode, "edit")
    }
  } noraise {
    _ => fail("expected CompileError")
  }
}

///|
test "screens encode decode round-trip" {
  let src =
    #|- screen "title"
    #|  vbox x=760 y=360:
    #|    text "MoonSight"
    #|    button "Start" action=start_game
    #|    button "Load" action=show_screen("save_load", mode=load)
    #|    button "Settings" action=show_screen("settings")
    #|
  let screens = @script.compile_screens(src, file="rt.yuki")
  let json = @script.encode_screens_file(screens, save_slots=6)
  let file = @script.decode_screens_file(json)
  assert_eq(file.save_slots, 6)
  assert_eq(file.defs.length(), 1)
  assert_eq(file.defs[0].name, "title")
  // Structural equality via JSON (ScreenDef derives ToJson, not Eq).
  assert_eq(file.defs[0].to_json().stringify(), screens[0].to_json().stringify())
  let again = @script.encode_screens_file(file.defs, save_slots=file.save_slots)
  let file2 = @script.decode_screens_file(again)
  assert_eq(file2.defs[0].to_json().stringify(), screens[0].to_json().stringify())
}

///|
test "compile_to_ir still works for scene-only files" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|
  let ir = @script.compile_to_ir(src, file="t.yuki")
  assert_true(ir.scenes.contains("s"))
  let bundle = @script.compile_bundle(src, file="t.yuki")
  assert_true(bundle.ir.scenes.contains("s"))
  assert_eq(bundle.screens.length(), 0)
}

///|
test "lower text bindings and multi-root wrap" {
  let src =
    #|- screen "menu"
    #|  vbox x=10 y=20:
    #|    text "Title"
    #|    text slot_label(0)
    #|    text pref("master_volume")
    #|    button "Back" action=return
    #|  fixed x=1 y=2:
    #|    button "X" action=noop
    #|
  let screens = @script.compile_screens(src, file="menu.yuki")
  assert_eq(screens.length(), 1)
  // Multiple root children → synthetic VBox wrapper
  guard screens[0].root is VBox(x~, y~, children~) else { fail("wrap vbox") }
  guard x is None else { fail("wrap x none") }
  guard y is None else { fail("wrap y none") }
  assert_eq(children.length(), 2)
  guard children[0] is VBox(x=vx, y=vy, children=vc) else { fail("inner vbox") }
  guard vx is Some(10.0) else { fail("x") }
  guard vy is Some(20.0) else { fail("y") }
  assert_eq(vc.length(), 4)
  guard vc[0] is Text(Literal("Title")) else { fail("lit") }
  guard vc[1] is Text(SlotLabel(0)) else { fail("slot") }
  guard vc[2] is Text(Pref(pk)) else { fail("pref") }
  assert_eq(pk, "master_volume")
  guard vc[3] is Button(action=Return, ..) else { fail("return") }
  guard children[1] is Fixed(x=fx, y=fy, children=fc, ..) else { fail("fixed") }
  assert_eq(fx, 1.0)
  assert_eq(fy, 2.0)
  guard fc[0] is Button(action=Noop, ..) else { fail("noop") }
}
