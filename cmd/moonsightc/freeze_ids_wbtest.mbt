///|
test "freeze IDs is deterministic and idempotent" {
  let src =
    #|- scene "intro"
    #|y:Hello
    #|@flow.choice "Yes" "No" --result c
    #|
  let first = freeze_ids_source(src)
  let second = freeze_ids_source(src)
  assert_eq(first, second)
  assert_eq(freeze_ids_source(first), first)
  assert_true(first.contains("@meta.id \"intro.op1\""))
  assert_true(first.contains("@meta.id \"intro.op2\""))
}
