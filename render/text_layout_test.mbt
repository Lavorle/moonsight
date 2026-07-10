///|
test "layout wraps long line" {
  let runs = layout_text(
    "Hello world from MoonSight",
    max_width=100.0,
    font_size=24.0,
    measure=fixed_width_measure(12.0),
  )
  assert_true(runs.length() >= 2)
}

///|
test "layout single short word is one run" {
  let runs = layout_text(
    "Hi",
    max_width=200.0,
    font_size=24.0,
    measure=fixed_width_measure(12.0),
  )
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].text, "Hi")
  assert_eq(runs[0].width, 24.0)
}

///|
test "layout respects explicit newlines" {
  let runs = layout_text(
    "A\nB\nC",
    max_width=500.0,
    font_size=20.0,
    measure=fixed_width_measure(10.0),
  )
  assert_eq(runs.length(), 3)
  assert_eq(runs[0].text, "A")
  assert_eq(runs[1].text, "B")
  assert_eq(runs[2].text, "C")
  assert_true(runs[1].y > runs[0].y)
}

///|
test "layout hard-breaks overlong token" {
  // 10 chars * 12 = 120 > max_width 50 → multiple runs
  let runs = layout_text(
    "ABCDEFGHIJ",
    max_width=50.0,
    font_size=24.0,
    measure=fixed_width_measure(12.0),
  )
  assert_true(runs.length() >= 2)
  let mut total = 0
  for r in runs {
    total = total + r.text.length()
  }
  assert_eq(total, 10)
}

///|
test "visible_prefix respects typewriter count" {
  assert_eq(visible_prefix("Hello", 0), "")
  assert_eq(visible_prefix("Hello", 3), "Hel")
  assert_eq(visible_prefix("Hello", 99), "Hello")
}

///|
test "measure_string sums advances" {
  let w = measure_string("ab", measure=fixed_width_measure(5.0))
  assert_eq(w, 10.0)
}
