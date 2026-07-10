///|
fn minimal_src() -> String {
  let s =
    #|- scene "s"
    #|y:Hi
    #|
  s
}

///|
test "bytecode roundtrip" {
  let ir = @script.compile_to_ir(minimal_src(), file="t.yuki")
  let bytes = @script.encode_module(ir)
  // magic MSB1
  assert_true(bytes.length() >= 4)
  assert_eq(bytes[0], b'M')
  assert_eq(bytes[1], b'S')
  assert_eq(bytes[2], b'B')
  assert_eq(bytes[3], b'1')
  let ir2 = @script.decode_module(bytes)
  assert_eq(ir2.entry, "s")
  assert_eq(ir2.scenes.length(), ir.scenes.length())
  assert_true(ir2.scenes.contains("s"))
  let ops = ir2.scenes["s"].ops
  assert_true(ops.length() >= 4)
  guard ops[0] is Host(name="text.begin", ..) else { fail("begin roundtrip") }
  guard ops[1] is Host(name="text.type", args~) else { fail("type roundtrip") }
  guard args is [Str("Hi")] else { fail("Hi roundtrip") }
  guard ops[3] is Yield else { fail("Yield roundtrip") }
}

///|
test "bytecode roundtrip multi scene with jump host" {
  let src =
    #|- scene "a"
    #|@flow.jump "b"
    #|- scene "b"
    #|y:Done
    #|
  let ir = @script.compile_to_ir(src, file="m.yuki")
  let ir2 = @script.decode_module(@script.encode_module(ir))
  assert_eq(ir2.scenes.length(), 2)
  assert_true(ir2.scenes.contains("a"))
  assert_true(ir2.scenes.contains("b"))
  guard ir2.scenes["a"].ops[0] is Host(name="flow.jump", args~) else {
    fail("jump")
  }
  guard args is [Str("b")] else { fail("target b") }
}
