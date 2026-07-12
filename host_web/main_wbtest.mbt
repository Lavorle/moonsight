///|
test "host module identity export reaches save JSON" {
  let source =
    #|- scene "main"
    #|yuki:Identity smoke.
    #|
  assert_eq(load_source(source), 0)
  assert_eq(set_module_id("identity-smoke"), 0)
  let save = save_json(0)
  assert_true(save.contains("identity-smoke"))
}

///|
test "load_json exposes save validation errors separately from VM errors" {
  let source =
    #|- scene "main"
    #|yuki:Validation smoke.
    #|
  assert_eq(load_source(source), 0)
  assert_eq(set_module_id("saved-module"), 0)
  let save = save_json(0)
  assert_eq(set_module_id("active-module"), 0)
  assert_eq(load_json(save), 1)
  assert_true(load_error().contains("module_id mismatch"))
  assert_eq(last_error(), "")
}

///|
test "menu slot load diagnostics are consumable through host exports" {
  let source =
    #|- scene "main"
    #|yuki:Menu load diagnostic smoke.
    #|
  assert_eq(load_source(source), 0)
  assert_eq(set_module_id("foreign-module"), 0)
  let save = save_json(0)
  assert_eq(set_module_id("active-module"), 0)
  assert_eq(set_slot_json(2, save), 0)
  guard session.val.engine is Some(eng) else { fail("engine") }
  let caps : &@runtime.Capabilities = eng
  caps.load_slot(2)
  assert_eq(slot_load_error_slot(), 2)
  assert_true(consume_slot_load_error().contains("module_id mismatch"))
  assert_eq(slot_load_error_slot(), -1)
  assert_eq(consume_slot_load_error(), "")
}
