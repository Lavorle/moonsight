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
  ]
  assert_eq(intents.length(), 11)
  assert_true(intents[2] == @runtime.Intent::Select(0))
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
