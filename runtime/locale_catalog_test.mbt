///|
test "locale catalogs resolve stable keys without text fallback" {
  let catalogs = LocaleCatalogs::new(default_locale="en", catalogs={
    "en": { "dialogue.greeting": "Hello", "ui.save": "Save" },
    "zh-CN": { "dialogue.greeting": "你好", "ui.save": "保存" },
  })
  assert_eq(catalogs.resolve("zh-CN", "dialogue.greeting"), "你好")
  assert_eq(catalogs.resolve("fr", "ui.save"), "Save")
  try ignore(catalogs.resolve("zh-CN", "ui.missing")) catch {
    _ => ()
  } noraise {
    _ => fail("missing text must not fall back")
  }
}

///|
test "locale catalogs reject incomplete or structurally divergent locales" {
  try
    ignore(
      LocaleCatalogs::new(default_locale="en", catalogs={
        "en": { "dialogue.greeting": "Hello", "ui.save": "Save" },
        "zh-CN": { "dialogue.greeting": "你好" },
      }),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected missing key error")
  }
  try
    ignore(
      LocaleCatalogs::new(default_locale="en", catalogs={
        "en": { "dialogue.greeting": "Hello" },
        "zh_cn": { "dialogue.greeting": "你好" },
      }),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("expected invalid locale error")
  }
}
