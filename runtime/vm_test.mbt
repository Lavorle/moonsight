///|
test "vm runs dialogue then yields; advance continues" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:There
    #|
  let ir = @script.compile_to_ir(src, file="t.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  // First tick without intent shows first line and hangs on Yield.
  eng.tick(None_)
  guard eng.stage.text is Some(t) else { fail("text") }
  assert_eq(t.full_text, "Hi")
  // First Advance completes typing if incomplete; second advances to next yield.
  eng.tick(Advance)
  eng.tick(Advance)
  guard eng.stage.text is Some(t2) else { fail("second") }
  assert_eq(t2.full_text, "There")
}

///|
test "vm from_ir starts at entry scene and halts after return" {
  let src =
    #|- scene "s"
    #|@var.set "x" 1
    #|
  let ir = @script.compile_to_ir(src, file="halt.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  assert_eq(eng.stage.scene, "s")
  assert_true(eng.stage.get_var("x") == Int(1))
  assert_true(eng.vm.wait == Halted)
}

///|
test "advance completes incomplete text before resuming" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|y:Next
    #|
  let ir = @script.compile_to_ir(src, file="type.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  // Force incomplete typewriter state as if gradual reveal were mid-way.
  match eng.stage.text {
    Some(t) =>
      eng.stage.text = Some({
        speaker: t.speaker,
        speaker_id: t.speaker_id,
        full_text: t.full_text,
        text_id: t.text_id,
        visible_chars: 0,
        complete: false,
      })
    None => fail("expected text")
  }
  eng.tick(Advance)
  guard eng.stage.text is Some(t1) else { fail("after complete") }
  assert_true(t1.complete)
  assert_eq(t1.full_text, "Hi")
  assert_true(eng.vm.wait == Yield)
  eng.tick(Advance)
  guard eng.stage.text is Some(t2) else { fail("next line") }
  assert_eq(t2.full_text, "Next")
}

///|
test "vm handles JumpScene from host flow.jump" {
  let src =
    #|- scene "a"
    #|@flow.jump "b"
    #|- scene "b"
    #|@var.set "landed" 1
    #|
  let ir = @script.compile_to_ir(src, file="jump.yuki")
  let dir = @runtime.Director::new()
  dir.register_fn("flow.jump", (stage, args) => {
    ignore(stage)
    match args {
      [Str(s), ..] => JumpScene(s)
      _ => Error("flow.jump")
    }
  })
  dir.register_fn("var.set", (stage, args) => {
    match args {
      [Str(name), value, ..] => {
        stage.set_var(name, value)
        Ok
      }
      _ => Error("var.set")
    }
  })
  let eng = @runtime.Engine::from_ir(ir, entry="a", director=dir)
  eng.tick(None_)
  assert_eq(eng.vm.scene, "b")
  assert_eq(eng.stage.scene, "b")
  assert_true(eng.stage.get_var("landed") == Int(1))
  assert_true(eng.vm.wait == Halted)
}

///|
fn build_long_var_set_scene(n : Int) -> String {
  let mut src = #|- scene "s"
#|
  for i in 0..<n {
    src = src + "@var.set \"x\" \{i}\n"
  }
  src
}

///|
test "H5 budget exhaustion increments counter without halt" {
  let src = build_long_var_set_scene(30)
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(src, file="h5.yuki"),
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.vm.run_until_wait(eng.director, eng.stage, budget=2)
  assert_true(!eng.vm.halted)
  assert_true(eng.vm.wait == Running)
  assert_eq(eng.vm.budget_exhaustions, 1)
  assert_true(eng.vm.last_budget_exhausted)
  // Next frame with full budget finishes; last flag clears on non-exhaust exit.
  eng.vm.run_until_wait(eng.director, eng.stage, budget=10000)
  assert_true(eng.vm.halted)
  assert_true(eng.vm.wait == Halted)
  assert_eq(eng.vm.budget_exhaustions, 1)
  assert_true(!eng.vm.last_budget_exhausted)
  assert_true(eng.stage.get_var("x") == Int(29))
}

///|
test "H5 short script keeps budget exhaustion counter at zero" {
  let src =
    #|- scene "s"
    #|@var.set "x" 1
    #|
  let eng = @runtime.Engine::from_ir(
    @script.compile_to_ir(src, file="h5-short.yuki"),
    entry="s",
    director=@std_commands.standard_registry(),
  )
  eng.vm.run_until_wait(eng.director, eng.stage)
  assert_true(eng.vm.halted)
  assert_eq(eng.vm.budget_exhaustions, 0)
  assert_true(!eng.vm.last_budget_exhausted)
}
