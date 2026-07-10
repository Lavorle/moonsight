///|
test "choice selects branch" {
  let src =
    #|- scene "s"
    #|@flow.choice "Yes" "No" --result c
    #|
  let ir = @script.compile_to_ir(src, file="choice.yuki")
  let ops = ir.scenes["s"].ops
  guard ops[0] is Choose(options~, result_var~) else {
    fail("expected IrOp::Choose from flow.choice")
  }
  assert_eq(result_var, "c")
  assert_eq(options.length(), 2)
  assert_eq(options[0], "Yes")
  assert_eq(options[1], "No")

  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  assert_true(eng.vm.wait == Choose)
  guard eng.stage.choices is Some(ch) else { fail("choices on stage") }
  assert_eq(ch.options.length(), 2)
  assert_eq(ch.options[0], "Yes")

  eng.tick(Select(0))
  assert_true(eng.stage.get_var("c") == Int(0))
  assert_true(eng.stage.choices is None)
  assert_true(eng.vm.wait == Halted)
}

///|
test "choice named result form lowers and selects" {
  let src =
    #|- scene "s"
    #|@flow.choice result="c" "Yes" "No"
    #|
  let ir = @script.compile_to_ir(src, file="choice2.yuki")
  guard ir.scenes["s"].ops[0] is Choose(result_var~, options~) else {
    fail("Choose")
  }
  assert_eq(result_var, "c")
  assert_eq(options[1], "No")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  eng.tick(Select(1))
  assert_true(eng.stage.get_var("c") == Int(1))
}

///|
test "engine view snapshots stage for render" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|
  let ir = @script.compile_to_ir(src, file="view.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  let view = eng.view()
  assert_eq(view.scene, "s")
  assert_true(view.wait == Yield)
  guard view.text is Some(t) else { fail("view text") }
  assert_eq(t.full_text, "Hi")
  assert_true(view.auto == false)
}

///|
test "fade transition eases overlay toward target" {
  let fade_src =
    #|- scene "s"
    #|
  let ir = @script.compile_to_ir(fade_src, file="fade.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.stage.overlay_opacity = 0.0
  eng.stage.fade_to = 1.0
  eng.stage.fade_duration = 0.3
  // One frame at dt=0.1 of a 0.3s unit fade → +1/3
  eng.tick(None_, dt=0.1)
  assert_true(eng.stage.overlay_opacity > 0.3)
  assert_true(eng.stage.overlay_opacity < 0.4)
  // Finish remaining distance
  eng.tick(None_, dt=0.3)
  assert_eq(eng.stage.overlay_opacity, 1.0)
}

///|
test "toggle auto synthesizes advance on yield" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="auto.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  guard eng.stage.text is Some(t0) else { fail("first") }
  assert_eq(t0.full_text, "Hi")
  eng.tick(ToggleAuto)
  assert_true(eng.auto)
  // auto + None_ while Yield → Advance (text already complete → next line)
  eng.tick(None_)
  guard eng.stage.text is Some(t1) else { fail("second") }
  assert_eq(t1.full_text, "There")
}
