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
test "lower flow.choice to Choose op" {
  let src =
    #|- scene "s"
    #|@flow.choice "Yes" "No" --result c
    #|
  let ir = @script.compile_to_ir(src, file="choice.yuki")
  let ops = ir.scenes["s"].ops
  guard ops[0] is Choose(options~, result_var~) else { fail("Choose") }
  assert_eq(result_var, "c")
  assert_eq(options.length(), 2)
  assert_eq(options[0], "Yes")
  assert_eq(options[1], "No")
}

///|
test "lower flow.jump_if equality to JumpIfNot plus flow.jump" {
  let src =
    #|- scene "s"
    #|@flow.jump_if act 0 "talk"
    #|@flow.jump "leave"
    #|
  let ir = @script.compile_to_ir(src, file="jif.yuki")
  let ops = ir.scenes["s"].ops
  // var.eq tmp, JumpIfNot, flow.jump talk, Label, flow.jump leave, Return
  guard ops[0] is Host(name="var.eq", args=eq_args) else { fail("var.eq") }
  assert_eq(eq_args.length(), 3)
  guard eq_args[1] is Var("act") else { fail("lhs act") }
  guard eq_args[2] is Int(0) else { fail("rhs 0") }
  guard ops[1] is JumpIfNot(cond~, ..) else { fail("JumpIfNot") }
  guard cond is Var(_) else { fail("cond var") }
  guard ops[2] is Host(name="flow.jump", args=jargs) else { fail("jump talk") }
  guard jargs is [Str("talk")] else { fail("talk scene") }
  guard ops[3] is Label(_) else { fail("Label") }
  guard ops[4] is Host(name="flow.jump", args=j2) else { fail("jump leave") }
  guard j2 is [Str("leave")] else { fail("leave") }
}

///|
test "lower flow.jump_if_not truthy form" {
  let src =
    #|- scene "s"
    #|@flow.jump_if_not flag "other"
    #|
  let ir = @script.compile_to_ir(src, file="jifn.yuki")
  let ops = ir.scenes["s"].ops
  guard ops[0] is JumpIf(cond~, ..) else { fail("JumpIf") }
  guard cond is Var("flag") else { fail("flag") }
  guard ops[1] is Host(name="flow.jump", args~) else { fail("flow.jump") }
  guard args is [Str("other")] else { fail("other") }
  guard ops[2] is Label(_) else { fail("Label") }
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

///|
test "lower preserves named host args as marker pairs" {
  let src =
    #|- scene "s"
    #|@layer.show "bg" "bg_room" kind=background duration=0.4
    #|
  let ir = @script.compile_to_ir(src, file="named.yuki")
  let ops = ir.scenes["s"].ops
  guard ops[0] is Host(name="layer.show", args~) else { fail("layer.show") }
  // id, resource, #:kind, background, #:duration, 0.4
  assert_true(args.length() >= 6)
  guard args[0] is Str("bg") else { fail("id") }
  guard args[1] is Str("bg_room") else { fail("res") }
  guard args[2] is Str("#:kind") else { fail("kind marker") }
  // bare `background` is Ident → Var (not Str); hosts may accept either later
  guard args[3] is Var("background") else { fail("kind val") }
  guard args[4] is Str("#:duration") else { fail("dur marker") }
  guard args[5] is Float(0.4) else { fail("dur val") }
}

///|
test "explicit IDs survive lowering while metadata directives do not execute" {
  let src =
    #|- scene "s"
    #|@meta.id "intro.greeting" presentation="text.intro.greeting"
    #|y:Hello
    #|@meta.id "intro.choice" choices="choice.yes,choice.no"
    #|@flow.choice "Yes" "No" --result c
    #|
  let identified = @script.compile_to_identified_ir(src, file="ids.yuki")
  assert_eq(identified.stable_operations.length(), 2)
  assert_eq(
    identified.stable_operations[0].operation_id.value,
    "intro.greeting",
  )
  guard identified.stable_operations[0].presentation_id is Some(id) else {
    fail("presentation ID")
  }
  assert_eq(id.value, "text.intro.greeting")
  assert_eq(identified.stable_operations[1].choice_ids.length(), 2)
  let ops = identified.ir.scenes["s"].ops
  for op in ops {
    guard op is Host(name="meta.id", ..) else { continue }
    fail("meta.id must not reach executable IR")
  }
}
