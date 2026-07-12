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
