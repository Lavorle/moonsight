///|
test "layer.show and trans.fade mutate stage" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("layer.show", stage, [Str("bg"), Str("bg_room")]) == Ok)
  assert_eq(stage.layers.length(), 1)
  assert_eq(stage.layers[0].resource, "bg_room")
  // Default kind is Character (Phase 2).
  assert_true(stage.layers[0].kind == @runtime.LayerKind::Character)
  ignore(reg.call("trans.fade", stage, [Float(0.0), Float(1.0), Float(0.3)]))
  // duration > 0: start at `from`; wall-clock fade_remaining for engine tick.
  assert_eq(stage.overlay_opacity, 0.0)
  assert_eq(stage.fade_to, 1.0)
  assert_eq(stage.fade_remaining, 0.3)
  assert_eq(stage.dissolve_phase, 0)
  // Zero duration still snaps to target.
  ignore(reg.call("trans.fade", stage, [Float(0.0), Float(1.0)]))
  assert_eq(stage.overlay_opacity, 1.0)
  assert_eq(stage.fade_remaining, 0.0)
  assert_eq(stage.dissolve_phase, 0)
}

///|
/// `@trans.dissolve duration` starts Out phase at opacity 0; duration ≤ 0 clears veil.
test "trans.dissolve goes out then in" {
  let reg = @std_commands.standard_registry()
  let stage = @runtime.Stage::new()
  ignore(reg.call("trans.dissolve", stage, [Float(1.0)]))
  // phase Out, opacity starts 0, fade_remaining is total wall for Out+In.
  assert_eq(stage.dissolve_phase, 1)
  assert_eq(stage.overlay_opacity, 0.0)
  assert_eq(stage.fade_to, 1.0)
  assert_eq(stage.fade_remaining, 1.0)
  // Zero duration clears the veil immediately.
  ignore(reg.call("trans.dissolve", stage, [Float(0.0)]))
  assert_eq(stage.dissolve_phase, 0)
  assert_eq(stage.overlay_opacity, 0.0)
  assert_eq(stage.fade_remaining, 0.0)
}

///|
test "layer.show single-arg empty resource" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("layer.show", stage, [Str("solo")]) == Ok)
  assert_eq(stage.layers[0].id, "solo")
  assert_eq(stage.layers[0].resource, "")
  assert_true(stage.layers[0].kind == @runtime.LayerKind::Character)
}

///|
test "layer.show respects kind and duration opacity" {
  let reg = @std_commands.standard_registry()
  let stage = @runtime.Stage::new()
  // Simulate lowered args: id, res, #:kind, character, #:duration, 0.4, and opacity target via #:opacity
  ignore(
    reg.call("layer.show", stage, [
      Str("y"),
      Str("char_y"),
      Str("#:kind"),
      Str("character"),
      Str("#:opacity"),
      Float(1.0),
      Str("#:duration"),
      Float(0.4),
    ]),
  )
  assert_true(stage.layers[0].kind == @runtime.LayerKind::Character)
  assert_eq(stage.layers[0].opacity, 0.0) // new layer starts 0 when duration>0
  stage.tick_layer_tweens(0.4)
  assert_eq(stage.layers[0].opacity, 1.0)
}

///|
test "layer.set errors on missing id" {
  let reg = @std_commands.standard_registry()
  let stage = @runtime.Stage::new()
  let r = reg.call(
    "layer.set",
    stage,
    [Str("nope"), Str("#:opacity"), Float(1.0)],
  )
  guard r is Error(msg) else { fail("expected error") }
  // Must be registered (not "unknown host") and soft-halt on missing layer id.
  assert_true(!msg.contains("unknown"), msg="got: \{msg}")
  assert_true(
    msg.contains("layer.set") || msg.contains("nope") || msg.contains("missing"),
    msg="got: \{msg}",
  )
}

///|
/// `scale=` snaps on show/set when duration is 0; named args use `#:key` packing.
test "layer.show and layer.set accept scale" {
  let reg = @std_commands.standard_registry()
  let stage = @runtime.Stage::new()
  ignore(
    reg.call(
      "layer.show",
      stage,
      [
        Str("y"),
        Str("char_y"),
        Str("#:kind"),
        Str("character"),
        Str("#:scale"),
        Float(0.5),
      ],
    ),
  )
  assert_eq(stage.layers[0].scale, 0.5)
  ignore(
    reg.call(
      "layer.set",
      stage,
      [Str("y"), Str("#:scale"), Float(1.0), Str("#:duration"), Float(0.0)],
    ),
  )
  assert_eq(stage.layers[0].scale, 1.0)
}

///|
test "layer.show accepts Int and Float coords" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(
    reg.call("layer.show", stage, [
      Str("c"),
      Str("char_y"),
      Int(10),
      Int(100),
      Float(200.5),
      Float(0.5),
    ]) ==
    Ok,
  )
  assert_eq(stage.layers[0].z, 10)
  assert_eq(stage.layers[0].x, 100.0)
  assert_eq(stage.layers[0].y, 200.5)
  assert_eq(stage.layers[0].opacity, 0.5)
}

///|
test "layer.hide and layer.move" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  ignore(reg.call("layer.show", stage, [Str("c"), Str("char_y")]))
  assert_true(reg.call("layer.move", stage, [Str("c"), Int(1), Int(2)]) == Ok)
  assert_eq(stage.layers[0].x, 1.0)
  assert_eq(stage.layers[0].y, 2.0)
  assert_true(reg.call("layer.hide", stage, [Str("c")]) == Ok)
  assert_eq(stage.layers.length(), 0)
}

///|
/// Re-show during an in-flight hide must cancel pending_hide and the opacity→0 tween.
test "layer.show cancels pending hide tween" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  ignore(
    reg.call("layer.show", stage, [
      Str("y"),
      Str("char_y"),
      Str("#:opacity"),
      Float(1.0),
    ]),
  )
  assert_eq(stage.layers.length(), 1)
  assert_eq(stage.layers[0].opacity, 1.0)
  ignore(
    reg.call("layer.hide", stage, [
      Str("y"),
      Str("#:duration"),
      Float(0.5),
    ]),
  )
  assert_true(stage.layers[0].pending_hide)
  // Partial fade, then re-show before hide completes.
  stage.tick_layer_tweens(0.25)
  assert_eq(stage.layers.length(), 1)
  assert_true(stage.layers[0].opacity < 1.0)
  ignore(reg.call("layer.show", stage, [Str("y"), Str("char_y")]))
  assert_eq(stage.layers.length(), 1)
  assert_true(!stage.layers[0].pending_hide)
  let opacity_after_reshow = stage.layers[0].opacity
  // Remaining hide time must not remove the layer or force opacity to 0.
  stage.tick_layer_tweens(0.5)
  assert_eq(stage.layers.length(), 1)
  assert_true(!stage.layers[0].pending_hide)
  assert_eq(stage.layers[0].opacity, opacity_after_reshow)
  assert_true(stage.layers[0].opacity > 0.0)
}

///|
test "text begin type end leaves typewriter incomplete" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("text.begin", stage, [Str("y")]) == Ok)
  assert_true(reg.call("text.type", stage, [Str("Hi")]) == Ok)
  assert_true(reg.call("text.end", stage, []) == Ok)
  guard stage.text is Some(t) else { fail("text") }
  assert_eq(t.full_text, "Hi")
  assert_true(!t.complete)
  assert_eq(t.visible_chars, 0)
}

///|
test "var.set stores values" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("var.set", stage, [Str("flag"), Bool(true)]) == Ok)
  assert_true(stage.get_var("flag") == Bool(true))
}

///|
test "flow.jump returns JumpScene" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(
    reg.call("flow.jump", stage, [Str("other")]) == JumpScene("other"),
  )
}

///|
test "flow.wait and flow.yield return Yield" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("flow.wait", stage, [Float(0.5)]) == Yield)
  assert_true(reg.call("flow.yield", stage, []) == Yield)
}

///|
test "flow.choice sets options and yields" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("flow.choice", stage, [Str("A"), Str("B")]) == Yield)
  guard stage.choices is Some(c) else { fail("choices") }
  assert_eq(c.options.length(), 2)
  assert_eq(c.options[0], "A")
  assert_eq(c.options[1], "B")
}

///|
test "audio.bgm se and sys.save_hint" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  @audio.reset_global_mixer()
  assert_true(reg.call("audio.bgm", stage, [Str("bgm_soft")]) == Ok)
  guard stage.bgm is Some(bgm) else { fail("bgm") }
  assert_eq(bgm, "bgm_soft")
  assert_eq(@audio.global_mixer().bgm_volume, 1.0)
  assert_true(reg.call("audio.se", stage, [Str("click")]) == Ok)
  guard stage.se is Some(se) else { fail("se") }
  assert_eq(se, "click")
  assert_true(reg.call("sys.save_hint", stage, []) == Ok)
  assert_true(stage.save_hint)
  @audio.reset_global_mixer()
}

///|
test "audio.bgm volume and fade named args" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  @audio.reset_global_mixer()
  // Immediate volume.
  assert_true(
    reg.call(
      "audio.bgm",
      stage,
      [Str("bgm_soft"), Str("#:volume"), Float(0.5)],
    ) ==
    Ok,
  )
  assert_eq(@audio.global_mixer().bgm_volume, 0.5)
  // Fade in on new id: start 0 → approach target.
  assert_true(
    reg.call(
      "audio.bgm",
      stage,
      [
        Str("bgm_other"),
        Str("#:volume"),
        Float(0.8),
        Str("#:fade"),
        Float(1.0),
      ],
    ) ==
    Ok,
  )
  assert_eq(@audio.global_mixer().bgm_volume, 0.0)
  @audio.global_mixer().tick(0.5)
  assert_true(
    @audio.global_mixer().bgm_volume > 0.3 &&
    @audio.global_mixer().bgm_volume < 0.5,
  )
  // Stop with fade.
  assert_true(
    reg.call("audio.bgm", stage, [None_, Str("#:fade"), Float(0.4)]) == Ok,
  )
  assert_true(stage.bgm is None)
  assert_true(@audio.global_mixer().bgm is Some(_))
  @audio.global_mixer().tick(0.4)
  assert_true(@audio.global_mixer().bgm is None)
  @audio.reset_global_mixer()
}

///|
test "ui.show and ui.hide queue stage ops" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  assert_true(reg.call("ui.show", stage, [Str("game_menu")]) == Yield)
  assert_eq(stage.ui_ops.length(), 1)
  assert_true(
    stage.ui_ops[0] == @runtime.UiHostOp::Show(name="game_menu", mode=None),
  )
  assert_true(
    reg.call(
      "ui.show",
      stage,
      [Str("save_load"), Str("#:mode"), Str("load")],
    ) ==
    Yield,
  )
  assert_eq(stage.ui_ops.length(), 2)
  assert_true(
    stage.ui_ops[1] ==
    @runtime.UiHostOp::Show(name="save_load", mode=Some("load")),
  )
  assert_true(reg.call("ui.hide", stage, []) == Ok)
  assert_eq(stage.ui_ops.length(), 3)
  assert_true(stage.ui_ops[2] == @runtime.UiHostOp::Hide(name=None))
  assert_true(reg.call("ui.hide", stage, [Str("settings")]) == Ok)
  assert_true(
    stage.ui_ops[3] == @runtime.UiHostOp::Hide(name=Some("settings")),
  )
}

///|
test "registry keys match script.builtin_externs exactly" {
  let reg = @std_commands.standard_registry()
  let reg_names = reg.registered_names()
  let builtin_names = @script.builtin_externs().map(e => e.name)
  builtin_names.sort()
  assert_eq(reg_names.length(), builtin_names.length())
  for i in 0..<reg_names.length() {
    assert_eq(reg_names[i], builtin_names[i])
  }
  // Also match the canonical list helper.
  let expected = @std_commands.standard_host_names()
  expected.sort()
  assert_eq(reg_names.length(), expected.length())
  for i in 0..<reg_names.length() {
    assert_eq(reg_names[i], expected[i])
  }
}

///|
test "unknown host returns Error" {
  let stage = @runtime.Stage::new()
  let reg = @std_commands.standard_registry()
  guard reg.call("no.such", stage, []) is Error(msg) else {
    fail("expected Error")
  }
  assert_true(msg.contains("no.such"))
}
