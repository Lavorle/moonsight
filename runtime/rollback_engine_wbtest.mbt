///|
fn rollback_test_engine() -> Engine raise {
  let source =
    #|- scene "s"
    #|n:First line.
    #|n:Second line.
    #|
  let ir = @script.compile_to_ir(source, file="rollback_engine.yuki")
  Engine::from_ir(ir, entry="s", module_id="rollback-engine-test")
}

///|
test "rollback intent restores the latest aggregate logical checkpoint" {
  let eng = rollback_test_engine()
  eng.tick(None_)
  guard eng.stage.text is Some(first) else { fail("first line") }
  assert_eq(first.full_text, "First line.")

  eng.tick(Advance)
  guard eng.stage.text is Some(second) else { fail("second line") }
  assert_eq(second.full_text, "Second line.")
  assert_eq(eng.rollback.count(), 1)

  eng.tick(Rollback)
  guard eng.stage.text is Some(restored) else { fail("restored first line") }
  assert_eq(restored.full_text, "First line.")
  assert_eq(eng.rollback.count(), 0)
}

///|
test "blocked rollback has zero logical or UI mutation" {
  let eng = rollback_test_engine()
  eng.tick(None_)
  eng.ui.scroll_y = 42.0
  let before = EngineLogicalState::capture(eng)

  eng.tick(Rollback)

  assert_logical_state_eq(EngineLogicalState::capture(eng), before)
  assert_eq(eng.rollback_unavailable(), "rollback.unavailable.empty")
}

///|
test "new game title and successful load clear rollback reachability" {
  let eng = rollback_test_engine()
  eng.tick(None_)
  eng.tick(Advance)
  assert_eq(eng.rollback.count(), 1)
  let save = eng.save()

  eng.start_game()
  assert_eq(eng.rollback.count(), 0)
  eng.tick(None_)
  eng.tick(Advance)
  assert_eq(eng.rollback.count(), 1)

  eng.load(save)
  assert_eq(eng.rollback.count(), 0)
  eng.tick(Advance)
  assert_eq(eng.rollback.count(), 1)
  eng.quit_to_title()
  assert_eq(eng.rollback.count(), 0)
}
