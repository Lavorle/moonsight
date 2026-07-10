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
    #|{"format_version":2,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{},"layers":[],"overlay_opacity":0,"audio":{}}
  try eng.load(bad) catch {
    err =>
      inspect(
        err.to_string(),
        content="unsupported save format_version 2 (expected 1)",
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
test "save blob is valid JSON with format_version 1" {
  let eng = load_min_demo_engine()
  eng.tick(None_)
  let blob = eng.save()
  let game = @runtime.parse_save_game(blob)
  assert_eq(game.format_version, 1)
  assert_eq(game.scene, eng.vm.scene)
  assert_eq(game.ip, eng.vm.ip)
}
