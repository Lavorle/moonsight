///|
fn load_min_demo_engine() -> @runtime.Engine raise {
  let src =
    #|- scene "s"
    #|@layer.show "bg" "bg_room"
    #|y:Hi
    #|
  let ir = @script.compile_to_ir(src, file="min_demo.yuki")
  @runtime.Engine::from_ir(ir, entry="s")
}

///|
test "save roundtrip restores scene ip vars and layers" {
  let eng = load_min_demo_engine()
  eng.tick(Intent::Advance)
  eng.stage.set_var("met_y", Value::Bool(true))
  let blob = eng.save(slot=0)
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  assert_eq(eng2.vm.scene, eng.vm.scene)
  assert_eq(eng2.vm.ip, eng.vm.ip)
  assert_true(eng2.stage.get_var("met_y") == Value::Bool(true))
  assert_eq(eng2.stage.layers.length(), eng.stage.layers.length())
}

///|
test "save rejects unsupported format_version" {
  let eng = load_min_demo_engine()
  // Option fields must be omitted (not JSON null) for FromJson.
  let bad =
    #|{"format_version":99,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{},"layers":[],"overlay_opacity":0,"audio":{},"wait":{"$tag":"Running"},"auto":false}
  try eng.load(bad) catch {
    err =>
      inspect(
        err.to_string(),
        content="unsupported save format_version 99 (expected 2 or 3)",
      )
  } noraise {
    _ => fail("expected UnsupportedVersion")
  }
}

///|
test "save consumes save_hint flag" {
  let eng = load_min_demo_engine()
  eng.stage.save_hint = true
  ignore(eng.save(slot=0))
  assert_true(!eng.stage.save_hint)
}

///|
test "save blob is format_version 3" {
  let eng = load_min_demo_engine()
  eng.tick(None_)
  let blob = eng.save()
  let game = @runtime.parse_save_game(blob)
  assert_eq(game.format_version, 3)
  assert_eq(game.scene, eng.vm.scene)
  assert_eq(game.ip, eng.vm.ip)
  assert_true(game.wait == Yield)
}

///|
test "save roundtrip restores Choose wait and choices" {
  let src =
    #|- scene "s"
    #|@flow.choice "Talk" "Leave" --result act
    #|@var.set "after" 1
    #|
  let ir = @script.compile_to_ir(src, file="choice_save.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  assert_true(eng.vm.wait == Choose)
  guard eng.stage.choices is Some(_) else { fail("choices present") }
  let blob = eng.save()
  let eng2 = @runtime.Engine::from_ir(ir, entry="s")
  eng2.load(blob)
  assert_true(eng2.vm.wait == Choose)
  assert_true(eng2.vm.choose_result_var is Some("act"))
  guard eng2.stage.choices is Some(ch) else { fail("restored choices") }
  assert_eq(ch.options.length(), 2)
  assert_eq(ch.options[0], "Talk")
  eng2.tick(Select(1))
  assert_true(eng2.stage.get_var("act") == Int(1))
  assert_true(eng2.stage.get_var("after") == Int(1))
}

///|
test "save roundtrip restores Yield with incomplete typewriter text" {
  let eng = load_min_demo_engine()
  eng.tick(None_, dt=0.0)
  guard eng.stage.text is Some(t0) else { fail("text") }
  assert_true(!t0.complete)
  let blob = eng.save()
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  assert_true(eng2.vm.wait == Yield)
  guard eng2.stage.text is Some(t1) else { fail("restored text") }
  assert_eq(t1.full_text, "Hi")
  assert_true(!t1.complete)
}

///|
test "save roundtrip restores tweens and wait_remaining" {
  let eng = load_min_demo_engine()
  eng.stage.show_layer(
    id="y",
    layer=Character,
    resource="char_y",
    z=10,
    opacity=0.5,
  )
  eng.stage.start_layer_tween(id="y", prop=Opacity, to=1.0, duration=0.4)
  eng.stage.wait_remaining = 0.8
  eng.stage.fade_to = 1.0
  eng.stage.fade_remaining = 0.5
  eng.stage.overlay_opacity = 0.3
  let blob = eng.save()
  let game = @runtime.parse_save_game(blob)
  assert_eq(game.format_version, 3)
  assert_eq(game.wait_remaining, 0.8)
  assert_eq(game.fade_to, 1.0)
  assert_eq(game.fade_remaining, 0.5)
  assert_eq(game.overlay_opacity, 0.3)
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  assert_eq(eng2.stage.wait_remaining, 0.8)
  assert_eq(eng2.stage.fade_to, 1.0)
  assert_eq(eng2.stage.fade_remaining, 0.5)
  assert_eq(eng2.stage.overlay_opacity, 0.3)
  let mut found = false
  for layer in eng2.stage.layers {
    if layer.id == "y" {
      found = true
      assert_eq(layer.opacity, 0.5)
      assert_eq(layer.tweens.length(), 1)
      assert_true(layer.tweens[0].prop == Opacity)
      assert_eq(layer.tweens[0].to, 1.0)
      assert_eq(layer.tweens[0].remaining, 0.4)
      assert_true(!layer.pending_hide)
    }
  }
  assert_true(found)
}

///|
test "load v2 save still works" {
  let eng = load_min_demo_engine()
  // v2 blob: no fade_to / fade_remaining / wait_remaining; layers lack tweens/pending_hide
  let v2 =
    #|{"format_version":2,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{"met":["Bool",true]},"layers":[{"id":"bg","kind":"Background","resource":"bg_room","z":0,"x":0,"y":0,"opacity":1,"visible":true}],"overlay_opacity":0,"audio":{},"wait":"Running","auto":false}
  eng.load(v2)
  assert_eq(eng.vm.scene, "s")
  assert_eq(eng.vm.ip, 0)
  assert_true(eng.vm.wait == Running)
  assert_true(eng.stage.get_var("met") == Bool(true))
  assert_eq(eng.stage.layers.length(), 1)
  assert_eq(eng.stage.layers[0].id, "bg")
  assert_true(eng.stage.layers[0].kind == Background)
  assert_eq(eng.stage.layers[0].tweens.length(), 0)
  assert_true(!eng.stage.layers[0].pending_hide)
  assert_eq(eng.stage.wait_remaining, 0.0)
  assert_eq(eng.stage.fade_to, 0.0)
  assert_eq(eng.stage.fade_remaining, 0.0)
}
