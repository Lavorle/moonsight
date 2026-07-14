///|
test "layer show updates stage snapshot fields" {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="bg",
    layer=@runtime.LayerKind::Background,
    resource="bg_room",
    z=0,
  )
  assert_eq(st.layers.length(), 1)
  assert_eq(st.layers[0].resource, "bg_room")
  assert_eq(st.layers[0].id, "bg")
  assert_true(st.layers[0].kind == @runtime.LayerKind::Background)
  assert_eq(st.layers[0].z, 0)
  assert_true(st.layers[0].visible)
  assert_eq(st.layers[0].opacity, 1.0)
}

///|
test "show_layer replaces same id and hide_layer removes" {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="y",
    layer=@runtime.LayerKind::Character,
    resource="char_y",
    z=10,
  )
  st.show_layer(
    id="y",
    layer=@runtime.LayerKind::Character,
    resource="char_y_smile",
    z=10,
    x=100.0,
    y=0.0,
  )
  assert_eq(st.layers.length(), 1)
  assert_eq(st.layers[0].resource, "char_y_smile")
  assert_eq(st.layers[0].x, 100.0)
  st.hide_layer(id="y")
  assert_eq(st.layers.length(), 0)
}

///|
test "snapshot_layers returns a copy sorted by z" {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="fx",
    layer=@runtime.LayerKind::Effect,
    resource="spark",
    z=5,
  )
  st.show_layer(
    id="bg",
    layer=@runtime.LayerKind::Background,
    resource="bg_room",
    z=0,
  )
  st.show_layer(id="ui", layer=@runtime.LayerKind::UI, resource="panel", z=20)
  let snap = st.snapshot_layers()
  assert_eq(snap.length(), 3)
  assert_eq(snap[0].id, "bg")
  assert_eq(snap[1].id, "fx")
  assert_eq(snap[2].id, "ui")
  // mutating snapshot must not affect stage
  snap.clear()
  assert_eq(st.layers.length(), 3)
}

///|
test "vars set and get with None_ default" {
  let st = @runtime.Stage::new()
  assert_true(st.get_var("missing") == @runtime.Value::None_)
  st.set_var("met_y", @runtime.Value::Bool(true))
  st.set_var("score", @runtime.Value::Int(3))
  st.set_var("name", @runtime.Value::Str("Y"))
  assert_true(st.get_var("met_y") == @runtime.Value::Bool(true))
  assert_true(st.get_var("score") == @runtime.Value::Int(3))
  assert_true(st.get_var("name") == @runtime.Value::Str("Y"))
}

///|
test "Value::truthy treats zero empty none as false" {
  assert_false(@runtime.Value::Int(0).truthy())
  assert_false(@runtime.Value::Bool(false).truthy())
  assert_false(@runtime.Value::None_.truthy())
  assert_false(@runtime.Value::Str("").truthy())
  assert_true(@runtime.Value::Int(1).truthy())
  assert_true(@runtime.Value::Float(0.0).truthy())
  assert_true(@runtime.Value::Bool(true).truthy())
  assert_true(@runtime.Value::Str("x").truthy())
}

///|
test "text typewriter begin type_more complete" {
  let st = @runtime.Stage::new()
  st.begin_text(speaker="y")
  guard st.text is Some(t0) else { fail("begin_text") }
  guard t0.speaker is Some("y") else { fail("speaker y") }
  assert_eq(t0.full_text, "")
  assert_eq(t0.visible_chars, 0)
  assert_false(t0.complete)
  st.type_more("Hi")
  st.type_more(" there")
  guard st.text is Some(t1) else { fail("type_more") }
  assert_eq(t1.full_text, "Hi there")
  // typewriter not yet complete: chars still hidden until reveal/complete
  assert_eq(t1.visible_chars, 0)
  assert_false(t1.complete)
  st.complete_text()
  guard st.text is Some(t2) else { fail("complete") }
  assert_eq(t2.visible_chars, t2.full_text.length())
  assert_true(t2.complete)
}

///|
test "choices set select and clear" {
  let st = @runtime.Stage::new()
  st.set_choices(["Yes", "No"])
  guard st.choices is Some(c0) else { fail("set_choices") }
  assert_eq(c0.options.length(), 2)
  assert_eq(c0.options[0], "Yes")
  // Focus starts on the first row for keyboard/mouse confirmation.
  guard c0.selected is Some(0) else { fail("default focus 0") }
  st.select_choice(1)
  guard st.choices is Some(c1) else { fail("select") }
  guard c1.selected is Some(1) else { fail("selected 1") }
  st.move_choice_focus(1)
  guard st.choices is Some(c2) else { fail("move") }
  // 1 + 1 wraps to 0 with two options.
  guard c2.selected is Some(0) else { fail("wrap to 0") }
  st.clear_choices()
  assert_true(st.choices is None)
}

///|
test "logical resolution constants" {
  assert_eq(@runtime.logical_width, 1920)
  assert_eq(@runtime.logical_height, 1080)
}

///|
test "Intent variants are constructible" {
  let intents : Array[@runtime.Intent] = [
    @runtime.Intent::None_,
    @runtime.Intent::Advance,
    @runtime.Intent::Select(0),
    @runtime.Intent::SkipTyping,
    @runtime.Intent::OpenMenu,
    @runtime.Intent::ToggleAuto,
    @runtime.Intent::MenuUp,
    @runtime.Intent::MenuDown,
    @runtime.Intent::MenuLeft,
    @runtime.Intent::MenuRight,
    @runtime.Intent::OpenBacklog,
    @runtime.Intent::Rollback,
  ]
  assert_eq(intents.length(), 12)
  assert_true(intents[2] == @runtime.Intent::Select(0))
}

///|
test "stage stable dialogue and choices relocalize atomically" {
  let stage = @runtime.Stage::new()
  stage.begin_text(
    speaker="Alice",
    speaker_id="speaker.alice",
    text_id="dialogue.greeting",
  )
  stage.type_more("Hello")
  stage.complete_text()
  stage.set_localized_choices(["Yes", "No"], ["choice.yes", "choice.no"])
  let catalogs = @runtime.LocaleCatalogs::new(default_locale="en", catalogs={
    "en": {
      "speaker.alice": "Alice",
      "dialogue.greeting": "Hello",
      "choice.yes": "Yes",
      "choice.no": "No",
    },
    "zh-CN": {
      "speaker.alice": "爱丽丝",
      "dialogue.greeting": "你好",
      "choice.yes": "是",
      "choice.no": "否",
    },
  })
  stage.relocalize(catalogs, "zh-CN")
  guard stage.text is Some(text) else { fail("localized text") }
  assert_true(text.speaker == Some("爱丽丝"))
  assert_eq(text.full_text, "你好")
  assert_true(text.complete)
  assert_eq(text.visible_chars, text.full_text.length())
  guard stage.choices is Some(choices) else { fail("localized choices") }
  assert_true(choices.options == ["是", "否"])
  assert_true(choices.option_ids == [Some("choice.yes"), Some("choice.no")])
}

///|
test "partial stage relocalization requires a grapheme-derived boundary" {
  let stage = @runtime.Stage::new()
  stage.begin_text(text_id="dialogue.greeting")
  stage.type_more("Hello")
  stage.reveal_chars(2)
  let catalogs = @runtime.LocaleCatalogs::new(default_locale="en", catalogs={
    "en": { "dialogue.greeting": "Hello" },
    "zh-CN": { "dialogue.greeting": "你好" },
  })
  try stage.relocalize(catalogs, "zh-CN") catch {
    _ => ()
  } noraise {
    _ => fail("partial switch without grapheme boundary must fail")
  }
  guard stage.text is Some(before) else { fail("original text") }
  assert_eq(before.full_text, "Hello")
  assert_eq(before.visible_chars, 2)

  stage.relocalize(catalogs, "zh-CN", partial_visible_utf16=1)
  guard stage.text is Some(after) else { fail("localized text") }
  assert_eq(after.full_text, "你好")
  assert_eq(after.visible_chars, 1)
}

///|
test "H3 typewriter reveal does not split combining mark" {
  let st = @runtime.Stage::new()
  st.begin_text(speaker="y")
  // e + combining acute — one grapheme cluster of UTF-16 length 2
  st.type_more("e\u{0301}X")
  st.reveal_chars(1)
  guard st.text is Some(t1) else { fail("after first reveal") }
  assert_eq(t1.visible_chars, 2)
  assert_eq(visible_prefix(t1.full_text, t1.visible_chars), "e\u{0301}")
  assert_false(t1.complete)
  st.reveal_chars(1)
  guard st.text is Some(t2) else { fail("after second reveal") }
  assert_eq(t2.visible_chars, 3)
  assert_true(t2.complete)
}

///|
test "H3 typewriter reveal treats ZWJ family as one grapheme" {
  let st = @runtime.Stage::new()
  st.begin_text()
  let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
  st.type_more(family + "!")
  st.reveal_chars(1)
  guard st.text is Some(t) else { fail("after reveal") }
  assert_eq(t.visible_chars, family.length())
  assert_false(t.complete)
  st.reveal_chars(1)
  guard st.text is Some(t2) else { fail("after full") }
  assert_eq(t2.visible_chars, family.length() + 1)
  assert_true(t2.complete)
}

///|
test "H3 ASCII reveal_chars remains one unit per char" {
  let st = @runtime.Stage::new()
  st.begin_text()
  st.type_more("Hi")
  st.reveal_chars(1)
  guard st.text is Some(t) else { fail("reveal") }
  assert_eq(t.visible_chars, 1)
  st.reveal_chars(1)
  guard st.text is Some(t2) else { fail("reveal2") }
  assert_eq(t2.visible_chars, 2)
  assert_true(t2.complete)
}

///|
test "tick_layer_tweens eases opacity linearly" {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="y",
    layer=@runtime.LayerKind::Character,
    resource="char_y",
    z=10,
    opacity=0.0,
  )
  st.start_layer_tween(
    id="y",
    prop=@runtime.TweenProp::Opacity,
    to=1.0,
    duration=1.0,
  )
  st.tick_layer_tweens(0.25)
  assert_eq(st.layers[0].opacity, 0.25)
  st.tick_layer_tweens(0.75)
  assert_eq(st.layers[0].opacity, 1.0)
  assert_eq(st.layers[0].tweens.length(), 0)
}

///|
test "layer scale snaps and tweens" {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="y",
    layer=@runtime.LayerKind::Character,
    resource="char_y",
    z=0,
  )
  assert_eq(st.layers[0].scale, 1.0)
  st.start_layer_tween(
    id="y",
    prop=@runtime.TweenProp::Scale,
    to=0.5,
    duration=0.0,
  )
  assert_eq(st.layers[0].scale, 0.5)
  st.start_layer_tween(
    id="y",
    prop=@runtime.TweenProp::Scale,
    to=1.0,
    duration=1.0,
  )
  st.tick_layer_tweens(0.5)
  let s = st.layers[0].scale
  assert_true(s > 0.74 && s < 0.76)
}

///|
test "snapshot_layers sorts by kind then z" {
  let st = @runtime.Stage::new()
  st.show_layer(id="c", layer=@runtime.LayerKind::Character, resource="c", z=0)
  st.show_layer(id="b", layer=@runtime.LayerKind::Background, resource="b", z=5)
  st.show_layer(id="e", layer=@runtime.LayerKind::Effect, resource="e", z=0)
  let snap = st.snapshot_layers()
  assert_eq(snap[0].id, "b")
  assert_eq(snap[1].id, "c")
  assert_eq(snap[2].id, "e")
}

///|
test "pending_hide removes layer after opacity tween" {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="y",
    layer=@runtime.LayerKind::Character,
    resource="c",
    z=1,
    opacity=1.0,
  )
  st.begin_hide_layer(id="y", duration=0.5)
  st.tick_layer_tweens(0.5)
  assert_eq(st.layers.length(), 0)
}

///|
/// Host re-show during hide cancels pending_hide and opacity→0 tween.
test "builtin layer.show cancels pending hide tween" {
  let st = @runtime.Stage::new()
  assert_true(
    @runtime.dispatch_builtin("layer.show", st, [
      @runtime.Value::Str("y"),
      @runtime.Value::Str("c"),
      @runtime.Value::Str("#:opacity"),
      @runtime.Value::Float(1.0),
    ]) ==
    @runtime.HostResult::Ok,
  )
  assert_eq(st.layers.length(), 1)
  assert_true(
    @runtime.dispatch_builtin("layer.hide", st, [
      @runtime.Value::Str("y"),
      @runtime.Value::Str("#:duration"),
      @runtime.Value::Float(0.5),
    ]) ==
    @runtime.HostResult::Ok,
  )
  assert_true(st.layers[0].pending_hide)
  st.tick_layer_tweens(0.25)
  assert_eq(st.layers.length(), 1)
  assert_true(
    @runtime.dispatch_builtin("layer.show", st, [
      @runtime.Value::Str("y"),
      @runtime.Value::Str("c"),
    ]) ==
    @runtime.HostResult::Ok,
  )
  assert_eq(st.layers.length(), 1)
  assert_true(!st.layers[0].pending_hide)
  let opacity_after_reshow = st.layers[0].opacity
  st.tick_layer_tweens(0.5)
  assert_eq(st.layers.length(), 1)
  assert_true(!st.layers[0].pending_hide)
  assert_eq(st.layers[0].opacity, opacity_after_reshow)
  assert_true(st.layers[0].opacity > 0.0)
}

///|
test "split_host_args separates positional and #:named pairs" {
  let args : Array[@runtime.Value] = [
    @runtime.Value::Str("id"),
    @runtime.Value::Str("#:z"),
    @runtime.Value::Int(3),
    @runtime.Value::Str("res"),
    @runtime.Value::Str("#:opacity"),
    @runtime.Value::Float(0.5),
  ]
  let (pos, named) = @runtime.split_host_args(args)
  assert_eq(pos.length(), 2)
  assert_true(pos[0] == @runtime.Value::Str("id"))
  assert_true(pos[1] == @runtime.Value::Str("res"))
  assert_true(named.get("z") is Some(@runtime.Value::Int(3)))
  assert_true(named.get("opacity") is Some(@runtime.Value::Float(0.5)))
}
