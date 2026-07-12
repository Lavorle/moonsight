///|
test "author ID grammar accepts portable stable IDs" {
  assert_eq(@script.parse_author_id("intro.line_1").value, "intro.line_1")
  assert_eq(@script.parse_author_id("choice-1.yes").value, "choice-1.yes")
  assert_eq(@script.parse_author_id("_ui.save_slot").value, "_ui.save_slot")
}

///|
test "author ID grammar rejects empty segments and non-ASCII syntax" {
  let invalid = ["", ".intro", "intro.", "intro..line", "1intro", "介绍.line"]
  for id in invalid {
    let rejected = try {
      @script.parse_author_id(id) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
