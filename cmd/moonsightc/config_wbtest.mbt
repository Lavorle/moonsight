///|
test "project config defaults to a single en locale" {
  let cfg = parse_project_config("{}")
  assert_eq(cfg.default_locale, "en")
  assert_eq(cfg.supported_locales, ["en"])
}

///|
test "project config accepts the frozen Formal 1.0 locale profile" {
  let cfg = parse_project_config(
    "{\"default_locale\":\"zh-Hans-CN\",\"supported_locales\":[\"en\",\"zh-Hans-CN\",\"es-419\"]}",
  )
  assert_eq(cfg.default_locale, "zh-Hans-CN")
  assert_eq(cfg.supported_locales, ["en", "zh-Hans-CN", "es-419"])
}

///|
test "project config rejects locale tags outside the frozen profile" {
  for tag in ["EN", "en-us", "en-US-x-private", "en_US", "english"] {
    let text =
      "{\"default_locale\":\"" + tag +
      "\",\"supported_locales\":[\"" + tag + "\"]}"
    try parse_project_config(text) catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid locale tag to fail: \{tag}")
    }
  }
}

///|
test "project config requires a unique supported locale set containing the default" {
  for text in [
    "{\"default_locale\":\"fr\",\"supported_locales\":[\"en\"]}",
    "{\"default_locale\":\"en\",\"supported_locales\":[]}",
    "{\"default_locale\":\"en\",\"supported_locales\":[\"en\",\"en\"]}",
  ] {
    try parse_project_config(text) catch {
      _ => ()
    } noraise {
      _ => fail("expected inconsistent locale config to fail: \{text}")
    }
  }
}
