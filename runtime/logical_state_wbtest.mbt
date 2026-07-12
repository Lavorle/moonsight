///|
fn logical_state_test_engine() -> Engine raise {
  let source =
    #|- scene "s"
    #|@layer.show "bg" "bg_room"
    #|yuki:Logical state.
    #|
  let ir = @script.compile_to_ir(source, file="logical_state.yuki")
  Engine::from_ir(ir, entry="s", module_id="logical-state-test")
}

///|
fn assert_logical_state_eq(
  actual : EngineLogicalState,
  expected : EngineLogicalState,
) -> Unit raise {
  assert_eq(actual.module_id, expected.module_id)
  assert_eq(actual.vm.scene, expected.vm.scene)
  assert_eq(actual.vm.ip, expected.vm.ip)
  assert_true(actual.vm.stack == expected.vm.stack)
  assert_eq(actual.vm.halted, expected.vm.halted)
  assert_true(actual.vm.wait == expected.vm.wait)
  assert_true(actual.vm.choose_result_var == expected.vm.choose_result_var)
  assert_eq(actual.stage.scene, expected.stage.scene)
  assert_true(actual.stage.vars == expected.stage.vars)
  assert_true(actual.stage.layers == expected.stage.layers)
  assert_true(actual.stage.text == expected.stage.text)
  match (actual.stage.choices, expected.stage.choices) {
    (None, None) => ()
    (Some(actual), Some(expected)) => {
      assert_true(actual.options == expected.options)
      assert_true(actual.selected == expected.selected)
    }
    _ => fail("logical choice snapshots differ")
  }
  assert_eq(actual.stage.overlay_opacity, expected.stage.overlay_opacity)
  assert_eq(actual.stage.fade_to, expected.stage.fade_to)
  assert_eq(actual.stage.fade_remaining, expected.stage.fade_remaining)
  assert_eq(actual.stage.wait_remaining, expected.stage.wait_remaining)
  assert_eq(actual.stage.dissolve_phase, expected.stage.dissolve_phase)
  assert_eq(actual.stage.dissolve_total, expected.stage.dissolve_total)
  assert_true(actual.stage.bgm == expected.stage.bgm)
  assert_true(actual.stage.se == expected.stage.se)
  assert_true(actual.ui.mode == expected.ui.mode)
  assert_eq(actual.ui.stack.length(), expected.ui.stack.length())
  for i in 0..<actual.ui.stack.length() {
    assert_eq(actual.ui.stack[i].name, expected.ui.stack[i].name)
    assert_true(actual.ui.stack[i].mode == expected.ui.stack[i].mode)
    assert_eq(actual.ui.stack[i].focus, expected.ui.stack[i].focus)
  }
  assert_eq(actual.ui.hud_focus, expected.ui.hud_focus)
  assert_eq(actual.ui.scroll_y, expected.ui.scroll_y)
  assert_true(actual.backlog.entries == expected.backlog.entries)
  assert_eq(actual.backlog.capacity, expected.backlog.capacity)
  assert_eq(actual.backlog.last_key, expected.backlog.last_key)
  assert_true(actual.audio == expected.audio)
  assert_eq(actual.auto, expected.auto)
}

///|
test "save v5 is projected from the logical state facade" {
  let eng = logical_state_test_engine()
  eng.tick(None_)
  eng.stage.set_var("route", Str("a"))
  let state = EngineLogicalState::capture(eng)
  let game = SaveGame::from_logical_state(state, saved_at="")
  assert_eq(game.format_version, 5)
  assert_eq(game.scene, state.vm.scene)
  assert_eq(game.ip, state.vm.ip)
  assert_true(game.vars == state.stage.vars)
  assert_true(game.layers == state.stage.layers)
  assert_true(game.audio == state.audio)
}

///|
test "logical state restores all subsystem snapshots" {
  @audio.reset_global_mixer()
  let eng = logical_state_test_engine()
  eng.tick(None_)
  eng.stage.set_var("route", Str("a"))
  eng.ui.mode = Menu
  eng.backlog.push(speaker=Some("yuki"), text="Remember this")
  eng.backlog_last_key = "yuki-Remember this"
  eng.auto = true
  eng.stage.bgm = Some("theme")
  @audio.global_mixer().play_bgm("theme", volume=0.4)
  let state = EngineLogicalState::capture(eng)

  eng.stage.set_var("route", Str("changed"))
  eng.ui.mode = Playing
  eng.backlog.clear()
  eng.auto = false
  eng.stage.bgm = None
  @audio.global_mixer().stop_bgm()

  eng.restore_logical_state(state)
  assert_logical_state_eq(EngineLogicalState::capture(eng), state)
  @audio.reset_global_mixer()
}

///|
test "logical validation failure is atomic" {
  let eng = logical_state_test_engine()
  eng.tick(None_)
  eng.stage.set_var("keep", Int(7))
  let before = EngineLogicalState::capture(eng)
  let invalid = {
    ..before,
    vm: { ..before.vm, scene: "missing" },
    stage: { ..before.stage, scene: "missing" },
  }
  try eng.restore_logical_state(invalid) catch {
    SaveError::UnknownScene(scene~) => assert_eq(scene, "missing")
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected UnknownScene")
  }
  assert_logical_state_eq(EngineLogicalState::capture(eng), before)
}

///|
test "backend reconciliation retries from the committed snapshot" {
  @audio.reset_global_mixer()
  let eng = logical_state_test_engine()
  eng.stage.bgm = Some("theme")
  @audio.global_mixer().play_bgm("theme", volume=0.35)
  let state = EngineLogicalState::capture(eng)
  let prepared = eng.prepare_logical_state(state)
  eng.publish_prepared_logical_state(prepared)
  assert_true(eng.pending_backend_audio is Some(_))

  @audio.global_mixer().stop_bgm()
  eng.reconcile_backends()
  assert_true(eng.pending_backend_audio is None)
  assert_true(@audio.global_mixer().bgm == Some("theme"))
  assert_eq(@audio.global_mixer().bgm_volume, 0.35)
  @audio.reset_global_mixer()
}
