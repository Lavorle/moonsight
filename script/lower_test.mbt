///|
test "lower dialogue to text host ops and yield" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|
  let ir = @script.compile_to_ir(src, file="t.yuki")
  assert_true(ir.scenes.contains("s"))
  let ops = ir.scenes["s"].ops
  assert_true(ops.length() >= 4)
  guard ops[0] is Host(name="text.begin", args~) else { fail("text.begin") }
  guard args is [Str("y")] else { fail("speaker y") }
  guard ops[1] is Host(name="text.type", args=type_args) else {
    fail("text.type")
  }
  guard type_args is [Str("Hi")] else { fail("type Hi") }
  guard ops[2] is Host(name="text.end", args=end_args) else { fail("text.end") }
  assert_eq(end_args.length(), 0)
  guard ops[3] is Yield else { fail("Yield") }
  assert_eq(ir.entry, "s")
}

///|
test "lower flow.jump command to host op" {
  let src =
    #|- scene "s"
    #|@flow.jump "other"
    #|
  let ir = @script.compile_to_ir(src, file="t.yuki")
  let ops = ir.scenes["s"].ops
  assert_true(ops.length() >= 1)
  guard ops[0] is Host(name="flow.jump", args~) else { fail("flow.jump") }
  guard args is [Str("other")] else { fail("scene other") }
}

///|
test "lower dialogue with inline command" {
  // wait is not a builtin; file extern required
  // Inline markup is `[cmd args]` (Yukimi-style brackets).
  let src =
    #|- extern wait time=1
    #|- scene "s"
    #|y:Hi[wait 1]there
    #|
  let ir = @script.compile_to_ir(src, file="t.yuki")
  let ops = ir.scenes["s"].ops
  // begin, type Hi, host wait, type there, end, yield
  assert_true(ops.length() >= 6)
  guard ops[0] is Host(name="text.begin", ..) else { fail("begin") }
  guard ops[1] is Host(name="text.type", args=a1) else { fail("type1") }
  guard a1 is [Str("Hi")] else { fail("Hi") }
  guard ops[2] is Host(name="wait", args=a2) else { fail("wait") }
  guard a2 is [Int(1)] else { fail("wait arg") }
  guard ops[3] is Host(name="text.type", args=a3) else { fail("type2") }
  guard a3 is [Str("there")] else { fail("there") }
  guard ops[4] is Host(name="text.end", ..) else { fail("end") }
  guard ops[5] is Yield else { fail("yield") }
}
