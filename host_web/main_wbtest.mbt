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
test "load_json exposes typed save validation errors through last_error" {
  let source =
    #|- scene "main"
    #|yuki:Validation smoke.
    #|
  assert_eq(load_source(source), 0)
  assert_eq(set_module_id("saved-module"), 0)
  let save = save_json(0)
  assert_eq(set_module_id("active-module"), 0)
  assert_eq(load_json(save), 1)
  assert_true(last_error().contains("module_id mismatch"))
}
