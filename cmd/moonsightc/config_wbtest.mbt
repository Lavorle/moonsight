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

///|
test "package manifest emits the frozen locale and schema fields" {
  let cfg = parse_project_config(
    "{\"name\":\"demo\",\"default_locale\":\"zh-Hans-CN\",\"supported_locales\":[\"en\",\"zh-Hans-CN\"]}",
  )
  let manifest = build_manifest_json(cfg, {}, {})
  let json = @json.parse(manifest)
  guard json is Object(fields) else { fail("expected manifest object") }
  assert_eq(fields["package_schema_version"], Json::number(2.0))
  assert_eq(fields["default_locale"], Json::string("zh-Hans-CN"))
  assert_eq(
    fields["supported_locales"],
    Json::array([Json::string("en"), Json::string("zh-Hans-CN")]),
  )
}
