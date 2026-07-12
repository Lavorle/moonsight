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
  assert_true(EngineLogicalState::capture(eng) == state)
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
  assert_true(EngineLogicalState::capture(eng) == before)
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
  assert_true(eng.backend_reconcile_pending())

  @audio.global_mixer().stop_bgm()
  eng.reconcile_backends()
  assert_true(!eng.backend_reconcile_pending())
  assert_true(@audio.global_mixer().bgm == Some("theme"))
  assert_eq(@audio.global_mixer().bgm_volume, 0.35)
  @audio.reset_global_mixer()
}
