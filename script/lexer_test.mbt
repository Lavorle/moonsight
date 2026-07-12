///|
test "lex scene header and dialogue" {
  let src =
    #|- scene "intro"
    #|y:Hello
    #|@wait 1
    #|
  let tokens = @script.lex(src, file="t.yuki")
  assert_true(tokens.length() >= 6)
  // First meaningful tokens: Minus, Ident(scene), String("intro"), ...
  guard tokens[0] is { kind: Minus, .. } else { fail("expected Minus") }
  guard tokens[1] is { kind: Ident(name), .. } && name == "scene" else {
    fail("expected Ident(scene)")
  }
  guard tokens[2] is { kind: StringLit(s), .. } && s == "intro" else {
    fail("expected StringLit(intro)")
  }
  // After Newline: dialogue
  guard tokens[3] is { kind: Newline, .. } else {
    fail("expected Newline after scene line")
  }
  guard tokens[4] is { kind: DialogueSpeaker(spk), .. } && spk == "y" else {
    fail("expected DialogueSpeaker(y)")
  }
  guard tokens[5] is { kind: DialogueText(text), .. } && text == "Hello" else {
    fail("expected DialogueText(Hello)")
  }
  // After Newline: @wait 1
  guard tokens[6] is { kind: Newline, .. } else {
    fail("expected Newline after dialogue")
  }
  guard tokens[7] is { kind: At, .. } else { fail("expected At") }
  guard tokens[8] is { kind: Ident(cmd), .. } && cmd == "wait" else {
    fail("expected Ident(wait)")
  }
  guard tokens[9] is { kind: IntLit(n), .. } && n == 1 else {
    fail("expected IntLit(1)")
  }
}

///|
test "lex flags and named args" {
  let src =
    #|@wait --force
    #|@foo bar=1
    #|
  let tokens = @script.lex(src, file="flags.yuki")
  // @wait --force
  guard tokens[0] is { kind: At, .. } else { fail("expected At") }
  guard tokens[1] is { kind: Ident(cmd), .. } && cmd == "wait" else {
    fail("expected Ident(wait)")
  }
  guard tokens[2] is { kind: Flag(f), .. } && f == "force" else {
    fail("expected Flag(force)")
  }
  guard tokens[3] is { kind: Newline, .. } else { fail("expected Newline") }
  // @foo bar=1
  guard tokens[4] is { kind: At, .. } else { fail("expected At") }
  guard tokens[5] is { kind: Ident(cmd), .. } && cmd == "foo" else {
    fail("expected Ident(foo)")
  }
  guard tokens[6] is { kind: Ident(key), .. } && key == "bar" else {
    fail("expected Ident(bar)")
  }
  guard tokens[7] is { kind: IntLit(n), .. } && n == 1 else {
    fail("expected IntLit(1)")
  }
}

///|
test "lex floats bools and spans" {
  let src =
    #|@set x=1.5 flag=true
    #|
  let tokens = @script.lex(src, file="num.yuki")
  guard tokens[0] is { kind: At, .. } else { fail("expected At") }
  guard tokens[1] is { kind: Ident(cmd), .. } && cmd == "set" else {
    fail("expected Ident(set)")
  }
  guard tokens[2] is { kind: Ident(key), .. } && key == "x" else {
    fail("expected Ident(x)")
  }
  guard tokens[3] is { kind: FloatLit(f), .. } && f == 1.5 else {
    fail("expected FloatLit(1.5)")
  }
  guard tokens[4] is { kind: Ident(key), .. } && key == "flag" else {
    fail("expected Ident(flag)")
  }
  guard tokens[5] is { kind: BoolLit(b), .. } && b else {
    fail("expected BoolLit(true)")
  }
  // Span metadata on first token
  assert_eq(tokens[0].span.file, "num.yuki")
  assert_eq(tokens[0].span.line, 1)
  assert_eq(tokens[0].span.col, 1)
}

///|
test "lexer named negative int and float" {
  let src = #|@layer.set "y" x=-200 y=-1.5 duration=0.5
  let toks = @script.lex(src, file="t.yuki")
  let mut saw_neg_int = false
  let mut saw_neg_float = false
  for t in toks {
    match t.kind {
      IntLit(n) => if n == -200 { saw_neg_int = true }
      FloatLit(f) => if f == -1.5 { saw_neg_float = true }
      _ => ()
    }
  }
  assert_true(saw_neg_int)
  assert_true(saw_neg_float)
}

///|
test "diagnostic to_cli format" {
  let span : @script.SourceSpan = {
    file: "demo.yuki",
    line: 3,
    col: 5,
    end_line: 3,
    end_col: 10,
  }
  let d : @script.Diagnostic = {
    severity: Error,
    span,
    message: "unexpected token",
  }
  inspect(d.to_cli(), content="demo.yuki:3:5: unexpected token")
}
