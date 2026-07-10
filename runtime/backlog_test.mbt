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
