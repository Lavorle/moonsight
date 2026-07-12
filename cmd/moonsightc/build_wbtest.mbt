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
    Json::object({
      "schema_version": Json::number(1.0),
      "entries": Json::array([]),
    }),
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

///|
test "legacy save projection maps resume display state to stable IDs" {
  let source =
    #|- scene "intro"
    #|@meta.id "intro.line" presentation="intro.text"
    #|Alice:Hello
    #|@meta.id "intro.pick" choices="intro.yes,intro.no"
    #|@flow.choice "Yes" "No" --result answer
    #|
  let identified = @script.compile_to_identified_ir(source, file="compat.yuki")
  let json = build_legacy_save_compatibility(identified).stringify()
  assert_true(json.contains("\"operation_id\":\"intro.line\""))
  assert_true(json.contains("\"presentation_id\":\"intro.text\""))
  assert_true(json.contains("\"legacy_text\":\"Hello\""))
  assert_true(json.contains("\"choice_ids\":[\"intro.yes\",\"intro.no\"]"))
}

///|
test "native SHA-256 file digest matches the standard vector" {
  let path = "/tmp/moonsight-sha256-vector.txt"
  write_string_to_file(path, "abc")
  let digest = sha256_file(path)
  remove_file(path)
  assert_eq(
    digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "localized package compile requires explicit stable IDs" {
  let path = "/tmp/moonsight-localized-missing-id.yuki"
  write_string_to_file(path, "- scene \"s\"\ny:Hello\n")
  let rejected = try {
    compile_yuki_paths_with_ids(
      [path][0:1],
      locale="ja",
      require_explicit_ids=true,
    )
    |> ignore
    false
  } catch {
    IoError(message) => message.contains("missing author ID")
  }
  remove_file(path)
  assert_true(rejected)
}
