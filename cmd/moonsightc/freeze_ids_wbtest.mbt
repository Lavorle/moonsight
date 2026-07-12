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
  assert_true(first.contains("presentation=\"intro.text1\""))
  assert_true(first.contains("speaker=\"intro.speaker.y\""))
  assert_true(
    first.contains("choices=\"intro.choice2.option1,intro.choice2.option2\""),
  )
  let compat = freeze_compatibility_json(src)
  assert_eq(compat, freeze_compatibility_json(src))
  assert_true(compat.contains("\"operation_id\": \"intro.op1\""))
}
