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

///|
test "MSB1 encoding is deterministic across scene insertion order" {
  let a : Map[String, IrScene] = {}
  a["z"] = { name: "z", ops: [Return] }
  a["a"] = { name: "a", ops: [Return] }
  let b : Map[String, IrScene] = {}
  b["a"] = { name: "a", ops: [Return] }
  b["z"] = { name: "z", ops: [Return] }
  assert_eq(
    @script.encode_module({ scenes: a, entry: "a" }),
    @script.encode_module({ scenes: b, entry: "a" }),
  )
}

///|
test "MSB2 catalog encoding is deterministic across map and locale order" {
  let ir = @script.compile_to_ir(minimal_src(), file="t.yuki")
  let en1 : Map[String, String] = {}
  en1["line.z"] = "Z"
  en1["line.a"] = "A"
  let en2 : Map[String, String] = {}
  en2["line.a"] = "A"
  en2["line.z"] = "Z"
  let ja : Map[String, String] = { "line.a": "あ", "line.z": "ん" }
  let first = @script.encode_msb2({
    ir,
    catalogs: [{ locale: "ja", entries: ja }, { locale: "en", entries: en1 }],
  })
  let second = @script.encode_msb2({
    ir,
    catalogs: [{ locale: "en", entries: en2 }, { locale: "ja", entries: ja }],
  })
  assert_eq(first, second)
  assert_eq(first[0], b'M')
  assert_eq(first[3], b'2')
}
