///|
test "identified IR installs stable dialogue and choice catalogs at runtime" {
  let source =
    #|- scene "s"
    #|@meta.id "op.greeting" presentation="dialogue.greeting"
    #|Alice:Hello
    #|@meta.id "op.route" choices="choice.yes,choice.no"
    #|@flow.choice "Yes" "No" --result answer
    #|
  let identified = @script.compile_localized_to_identified_ir(
    source,
    file="identified_locale.yuki",
    locale="zh-CN",
    require_explicit_ids=true,
  )
  let catalogs : Array[@script.LocaleCatalog] = [
    {
      locale: "en",
      entries: {
        "dialogue.greeting": "Hello",
        "choice.yes": "Yes",
        "choice.no": "No",
      },
    },
    {
      locale: "zh-CN",
      entries: {
        "dialogue.greeting": "你好",
        "choice.yes": "是",
        "choice.no": "否",
      },
    },
  ]
  let eng = Engine::from_identified_ir(
    identified,
    entry="s",
    catalogs~,
    default_locale="en",
    requested_locale="zh-CN",
  )
  eng.tick(None_)
  guard eng.stage.text is Some(text) else { fail("localized dialogue") }
  assert_eq(text.full_text, "你好")
  assert_true(text.text_id == Some("dialogue.greeting"))

  eng.tick(Advance)
  eng.tick(Advance)
  guard eng.stage.choices is Some(choices) else { fail("localized choices") }
  assert_true(choices.options == ["是", "否"])
  assert_true(choices.option_ids == [Some("choice.yes"), Some("choice.no")])
}
