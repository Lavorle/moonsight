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
  eng.stage.fade_remaining = 0.5
  // Wall-clock: duration 0.5 from 0→1 is halfway after 0.25s total
  eng.tick(None_, dt=0.25)
  assert_true(eng.stage.overlay_opacity > 0.45)
  assert_true(eng.stage.overlay_opacity < 0.55)
  assert_true(eng.stage.fade_remaining > 0.2)
  assert_true(eng.stage.fade_remaining < 0.3)
  // Finish remaining wall-clock time → reaches ~1.0 after 0.5s total
  eng.tick(None_, dt=0.25)
  assert_eq(eng.stage.overlay_opacity, 1.0)
  assert_eq(eng.stage.fade_remaining, 0.0)
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
  // Complete typewriter (text.end no longer force-completes).
  eng.tick(Advance)
  guard eng.stage.text is Some(t_done) else { fail("complete") }
  assert_true(t_done.complete)
  eng.tick(ToggleAuto)
  assert_true(eng.auto)
  // auto + None_ while Yield → Advance to next line
  eng.tick(None_)
  guard eng.stage.text is Some(t1) else { fail("second") }
  assert_eq(t1.full_text, "There")
}

///|
test "typewriter reveals chars over ticks without complete_on_end" {
  let src =
    #|- scene "s"
    #|y:Hello
    #|
  let ir = @script.compile_to_ir(src, file="tw.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  // dt=0: run to Yield but do not reveal
  eng.tick(None_, dt=0.0)
  guard eng.stage.text is Some(t0) else { fail("text") }
  assert_eq(t0.full_text, "Hello")
  assert_true(!t0.complete)
  assert_eq(t0.visible_chars, 0)
  // One frame at 1/40s → ~1 char (engine floors to at least 1 when dt>0)
  eng.tick(None_, dt=0.025)
  guard eng.stage.text is Some(t1) else { fail("tick1") }
  assert_true(t1.visible_chars >= 1)
  assert_true(t1.visible_chars < t1.full_text.length() || t1.complete)
  // Enough ticks to finish
  for _ in 0..<20 {
    eng.tick(None_, dt=0.05)
  }
  guard eng.stage.text is Some(t2) else { fail("done") }
  assert_true(t2.complete)
  assert_eq(t2.visible_chars, t2.full_text.length())
}

///|
test "jump_if branches Talk vs Leave to different scenes" {
  let src =
    #|- scene "s"
    #|@flow.choice "Talk" "Leave" --result act
    #|@flow.jump_if act 0 "talk"
    #|@flow.jump "leave"
    #|- scene "talk"
    #|@var.set "path" 1
    #|- scene "leave"
    #|@var.set "path" 2
    #|
  let ir = @script.compile_to_ir(src, file="branch.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.tick(None_)
  eng.tick(Select(0))
  assert_eq(eng.vm.scene, "talk")
  assert_true(eng.stage.get_var("path") == Int(1))

  let eng2 = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng2.tick(None_)
  eng2.tick(Select(1))
  assert_eq(eng2.vm.scene, "leave")
  assert_true(eng2.stage.get_var("path") == Int(2))
}

///|
test "missing scene sets last_error and halts" {
  let src =
    #|- scene "s"
    #|@flow.jump "nope"
    #|
  let ir = @script.compile_to_ir(src, file="miss.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.tick(None_)
  assert_true(eng.vm.wait == Halted)
  guard eng.vm.last_error is Some(msg) else { fail("last_error") }
  assert_true(msg.contains("nope"))
}

///|
test "flow.wait duration resumes after real time" {
  let src =
    #|- scene "s"
    #|@flow.wait 0.5
    #|@var.set "done" true
    #|
  let ir = @script.compile_to_ir(src, file="wait.yuki")
  let eng = @runtime.Engine::from_ir(
    ir,
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.tick(None_, dt=0.0)
  // After first run should be Yield with wait_remaining ~ 0.5
  assert_true(eng.vm.wait == Yield)
  assert_true(eng.stage.wait_remaining > 0.0)
  // Advance must not skip
  eng.tick(Advance, dt=0.1)
  assert_true(eng.vm.wait == Yield)
  assert_true(eng.stage.get_var("done") == None_)
  eng.tick(None_, dt=0.5)
  assert_true(
    eng.stage.get_var("done") == Bool(true) ||
    eng.vm.wait == Halted ||
    eng.vm.wait == Running,
  )
  // After enough time, var set
  eng.tick(None_, dt=0.1)
  assert_true(eng.stage.get_var("done") == Bool(true))
}

///|
test "layer opacity tween advances on engine tick" {
  let src =
    #|- scene "s"
    #|@flow.yield
    #|
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(src, file="t.yuki"),
    entry="s",
  )
  eng.stage.show_layer(id="y", layer=Character, resource="c", z=1, opacity=0.0)
  eng.stage.start_layer_tween(id="y", prop=Opacity, to=1.0, duration=1.0)
  eng.tick(None_, dt=0.5)
  assert_eq(eng.stage.layers[0].opacity, 0.5)
}
