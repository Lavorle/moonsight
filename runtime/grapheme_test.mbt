///|
test "grapheme boundaries ascii" {
  let b = grapheme_boundaries("ab")
  assert_eq(b, [0, 1, 2])
}

///|
test "grapheme boundaries cjk" {
  let s = "你好"
  let b = grapheme_boundaries(s)
  assert_eq(b.length(), 3) // 0, end of 你, end of 好
  assert_eq(b[0], 0)
  assert_eq(b[b.length() - 1], s.length())
}

///|
test "combining accent is one grapheme" {
  // e + combining acute
  let s = "e\u{0301}"
  let b = grapheme_boundaries(s)
  assert_eq(b.length(), 2) // 0 and full length
  assert_eq(advance_visible_utf16(s, 0, 1), s.length())
}

///|
test "zwj family emoji is one grapheme" {
  // Family: man+ZWJ+woman+ZWJ+girl+ZWJ+boy — same sequence as host-web fixtures.
  let s = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
  let b = grapheme_boundaries(s)
  assert_eq(b.length(), 2)
  assert_eq(advance_visible_utf16(s, 0, 1), s.length())
}

///|
test "clamp floors to boundary" {
  let s = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}X"
  let mid = 2 // inside the family cluster for UTF-16
  let c = clamp_to_grapheme_boundary(s, mid)
  assert_true(c == 0 || c == grapheme_boundaries(s)[1])
  // mid inside first cluster must clamp to a boundary — never mid if mid not boundary
  let bounds = grapheme_boundaries(s)
  let mut is_bound = false
  for b in bounds {
    if b == mid {
      is_bound = true
    }
  }
  if !is_bound {
    assert_true(c != mid)
  }
}

///|
test "grapheme_count and visible_prefix" {
  assert_eq(grapheme_count(""), 0)
  assert_eq(grapheme_count("ab"), 2)
  assert_eq(grapheme_count("e\u{0301}"), 1)
  let s = "e\u{0301}X"
  assert_eq(visible_prefix(s, 1), "")
  assert_eq(visible_prefix(s, 2), "e\u{0301}")
  assert_eq(visible_prefix(s, 99), s)
}

///|
test "advance_visible_utf16 steps by grapheme" {
  let s = "a\u{0301}bc"
  // clusters: á | b | c  — utf16 ends at 2, 3, 4
  assert_eq(advance_visible_utf16(s, 0, 1), 2)
  assert_eq(advance_visible_utf16(s, 2, 1), 3)
  assert_eq(advance_visible_utf16(s, 0, 3), 4)
  assert_eq(advance_visible_utf16(s, 0, 99), 4)
}
