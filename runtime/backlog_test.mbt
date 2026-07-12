///|
test "backlog ring drops oldest at capacity" {
  let b = BacklogStore::new(capacity=3)
  b.push(speaker=Some("a"), text="1")
  b.push(speaker=None, text="2")
  b.push(speaker=Some("c"), text="3")
  b.push(speaker=None, text="4")
  assert_eq(b.len(), 3)
  assert_eq(b.get(0).text, "2")
  assert_eq(b.get(2).text, "4")
}

///|
test "backlog clear empties" {
  let b = BacklogStore::new(capacity=10)
  b.push(speaker=None, text="x")
  b.clear()
  assert_eq(b.len(), 0)
}

///|
test "backlog stable references relocalize atomically" {
  let b = BacklogStore::new(capacity=10)
  b.push(
    speaker=Some("Alice"),
    text="Hello",
    speaker_id="speaker.alice",
    text_id="dialogue.greeting",
  )
  let catalogs = LocaleCatalogs::new(
    default_locale="en",
    catalogs={
      "en": { "speaker.alice": "Alice", "dialogue.greeting": "Hello" },
      "zh-CN": { "speaker.alice": "爱丽丝", "dialogue.greeting": "你好" },
    },
  )
  b.relocalize(catalogs, "zh-CN")
  assert_eq(b.get(0).speaker, Some("爱丽丝"))
  assert_eq(b.get(0).text, "你好")
  assert_eq(b.get(0).speaker_id, Some("speaker.alice"))
  assert_eq(b.get(0).text_id, Some("dialogue.greeting"))
}

///|
test "backlog relocalize failure leaves all resolved strings unchanged" {
  let b = BacklogStore::new(capacity=10)
  b.push(text="Hello", speaker=None, text_id="dialogue.greeting")
  b.push(text="Missing", speaker=None, text_id="dialogue.missing")
  let catalogs = LocaleCatalogs::new(
    default_locale="en",
    catalogs={
      "en": { "dialogue.greeting": "Hello" },
      "zh-CN": { "dialogue.greeting": "你好" },
    },
  )
  try b.relocalize(catalogs, "zh-CN") catch {
    _ => ()
  } noraise {
    _ => fail("expected missing stable key error")
  }
  assert_eq(b.get(0).text, "Hello")
  assert_eq(b.get(1).text, "Missing")
}
