///|
test "package manifest includes deterministic raw artifact digests" {
  let cfg = parse_project_config(
    "{\"name\":\"demo\",\"supported_locales\":[\"en\"],\"default_locale\":\"en\"}",
  )
  let manifest = build_manifest_json(
    cfg,
    { "bg": "assets/bg.png" },
    {},
    {
      "assets/bg.png": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "game.msb": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    },
  )
  let json = @json.parse(manifest)
  guard json is Object(fields) else { fail("manifest object") }
  guard fields["digests"] is Object(digests) else { fail("digests object") }
  assert_eq(
    digests["game.msb"],
    Json::string(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
  )
  assert_eq(
    digests["assets/bg.png"],
    Json::string(
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ),
  )
}
