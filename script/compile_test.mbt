///|
test "compile_source returns ir and bytecode" {
  let src =
    #|- scene "s"
    #|y:Hi
    #|
  let result = @script.compile_source(src, file="t.yuki")
  assert_eq(result.diags.length(), 0)
  assert_true(result.ir.scenes.contains("s"))
  assert_true(result.bytecode.length() >= 4)
  assert_eq(result.bytecode[0], b'M')
  assert_eq(result.bytecode[1], b'S')
  assert_eq(result.bytecode[2], b'B')
  assert_eq(result.bytecode[3], b'1')
  let ops = result.ir.scenes["s"].ops
  guard ops[0] is Host(name="text.begin", ..) else { fail("begin") }
  guard ops[3] is Yield else { fail("yield") }
}

///|
test "compile_source propagates resolve errors" {
  let src =
    #|- scene "s"
    #|@no_such 1
    #|
  try @script.compile_source(src, file="t.yuki") catch {
    err => {
      guard err is Resolve(ResolveError::UnknownCommand(name~, ..)) else {
        fail("expected Resolve UnknownCommand, got \{to_repr(err)}")
      }
      assert_eq(name, "no_such")
    }
  } noraise {
    _ => fail("expected CompileError")
  }
}
