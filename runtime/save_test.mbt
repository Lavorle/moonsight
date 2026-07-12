///|
fn load_min_demo_engine() -> @runtime.Engine raise {
  let src =
    #|- scene "s"
    #|@layer.show "bg" "bg_room"
    #|y:Hi
    #|
  let ir = @script.compile_to_ir(src, file="min_demo.yuki")
  @runtime.Engine::from_ir(ir, entry="s")
}

///|
fn load_min_demo_engine_for(module_id : String) -> @runtime.Engine raise {
  let src =
    #|- scene "s"
    #|@layer.show "bg" "bg_room"
    #|y:Hi
    #|
  let ir = @script.compile_to_ir(src, file="min_demo.yuki")
  @runtime.Engine::from_ir(ir, entry="s", module_id~)
}

///|
test "save roundtrip restores scene ip vars and layers" {
  let eng = load_min_demo_engine()
  eng.tick(Intent::Advance)
  eng.stage.set_var("met_y", Value::Bool(true))
  let blob = eng.save(slot=0)
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  assert_eq(eng2.vm.scene, eng.vm.scene)
  assert_eq(eng2.vm.ip, eng.vm.ip)
  assert_true(eng2.stage.get_var("met_y") == Value::Bool(true))
  assert_eq(eng2.stage.layers.length(), eng.stage.layers.length())
}

///|
test "save rejects unsupported format_version" {
  let eng = load_min_demo_engine()
  // Option fields must be omitted (not JSON null) for FromJson.
  let bad =
    #|{"format_version":99,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{},"layers":[],"overlay_opacity":0,"audio":{},"wait":{"$tag":"Running"},"auto":false}
  try eng.load(bad) catch {
    err =>
      inspect(
        err.to_string(),
        content="unsupported save format_version 99 (expected 2, 3, 4, or 5)",
      )
  } noraise {
    _ => fail("expected UnsupportedVersion")
  }
}

///|
test "save consumes save_hint flag" {
  let eng = load_min_demo_engine()
  eng.stage.save_hint = true
  ignore(eng.save(slot=0))
  assert_true(!eng.stage.save_hint)
}

///|
test "save blob is format_version 5" {
  let eng = load_min_demo_engine()
  eng.tick(None_)
  let blob = eng.save()
  let game = @runtime.parse_save_game(blob)
  assert_eq(game.format_version, 5)
  assert_eq(game.scene, eng.vm.scene)
  assert_eq(game.ip, eng.vm.ip)
  assert_true(game.wait == Yield)
}

///|
test "save roundtrip restores Choose wait and choices" {
  let src =
    #|- scene "s"
    #|@flow.choice "Talk" "Leave" --result act
    #|@var.set "after" 1
    #|
  let ir = @script.compile_to_ir(src, file="choice_save.yuki")
  let eng = @runtime.Engine::from_ir(ir, entry="s")
  eng.tick(None_)
  assert_true(eng.vm.wait == Choose)
  guard eng.stage.choices is Some(_) else { fail("choices present") }
  let blob = eng.save()
  let eng2 = @runtime.Engine::from_ir(ir, entry="s")
  eng2.load(blob)
  assert_true(eng2.vm.wait == Choose)
  assert_true(eng2.vm.choose_result_var is Some("act"))
  guard eng2.stage.choices is Some(ch) else { fail("restored choices") }
  assert_eq(ch.options.length(), 2)
  assert_eq(ch.options[0], "Talk")
  eng2.tick(Select(1))
  assert_true(eng2.stage.get_var("act") == Int(1))
  assert_true(eng2.stage.get_var("after") == Int(1))
}

///|
test "save roundtrip restores Yield with incomplete typewriter text" {
  let eng = load_min_demo_engine()
  eng.tick(None_, dt=0.0)
  guard eng.stage.text is Some(t0) else { fail("text") }
  assert_true(!t0.complete)
  let blob = eng.save()
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  assert_true(eng2.vm.wait == Yield)
  guard eng2.stage.text is Some(t1) else { fail("restored text") }
  assert_eq(t1.full_text, "Hi")
  assert_true(!t1.complete)
}

///|
/// Save v5 persists the full dual-phase dissolve continuation so load resumes
/// the same logical transition rather than degrading it to a simple fade.
test "save during dissolve restores dual-phase" {
  let eng = load_min_demo_engine()
  // Start dual-phase dissolve and advance into Out half.
  ignore(
    @std_commands.standard_registry().call("trans.dissolve", eng.stage, [
      Float(1.0),
    ]),
  )
  eng.tick(None_, dt=0.25)
  assert_eq(eng.stage.dissolve_phase, 1)
  assert_true(eng.stage.dissolve_total > 0.0)
  assert_true(eng.stage.fade_remaining > 0.0)
  let saved_fade_to = eng.stage.fade_to
  let saved_fade_rem = eng.stage.fade_remaining
  let saved_overlay = eng.stage.overlay_opacity
  let blob = eng.save()
  // Target engine has unrelated residual dissolve state that load replaces.
  let eng2 = load_min_demo_engine()
  eng2.stage.dissolve_phase = 2
  eng2.stage.dissolve_total = 9.0
  eng2.stage.overlay_opacity = 0.9
  eng2.stage.fade_remaining = 3.0
  eng2.load(blob)
  assert_eq(eng2.stage.dissolve_phase, eng.stage.dissolve_phase)
  assert_eq(eng2.stage.dissolve_total, eng.stage.dissolve_total)
  // Fade fields restore the matching point within the dual-phase transition.
  assert_eq(eng2.stage.fade_to, saved_fade_to)
  assert_eq(eng2.stage.fade_remaining, saved_fade_rem)
  assert_eq(eng2.stage.overlay_opacity, saved_overlay)
}

///|
test "save roundtrip restores tweens and wait_remaining" {
  let eng = load_min_demo_engine()
  eng.stage.show_layer(
    id="y",
    layer=Character,
    resource="char_y",
    z=10,
    opacity=0.5,
  )
  eng.stage.start_layer_tween(id="y", prop=Opacity, to=1.0, duration=0.4)
  eng.stage.wait_remaining = 0.8
  eng.stage.fade_to = 1.0
  eng.stage.fade_remaining = 0.5
  eng.stage.overlay_opacity = 0.3
  let blob = eng.save()
  let game = @runtime.parse_save_game(blob)
  assert_eq(game.format_version, 5)
  assert_eq(game.wait_remaining, 0.8)
  assert_eq(game.fade_to, 1.0)
  assert_eq(game.fade_remaining, 0.5)
  assert_eq(game.overlay_opacity, 0.3)
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  assert_eq(eng2.stage.wait_remaining, 0.8)
  assert_eq(eng2.stage.fade_to, 1.0)
  assert_eq(eng2.stage.fade_remaining, 0.5)
  assert_eq(eng2.stage.overlay_opacity, 0.3)
  let mut found = false
  for layer in eng2.stage.layers {
    if layer.id == "y" {
      found = true
      assert_eq(layer.opacity, 0.5)
      assert_eq(layer.tweens.length(), 1)
      assert_true(layer.tweens[0].prop == Opacity)
      assert_eq(layer.tweens[0].to, 1.0)
      assert_eq(layer.tweens[0].remaining, 0.4)
      assert_true(!layer.pending_hide)
    }
  }
  assert_true(found)
}

///|
test "load v2 save still works" {
  let eng = load_min_demo_engine()
  // v2 blob: no fade_to / fade_remaining / wait_remaining; layers lack tweens/pending_hide
  let v2 =
    #|{"format_version":2,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{"met":["Bool",true]},"layers":[{"id":"bg","kind":"Background","resource":"bg_room","z":0,"x":0,"y":0,"opacity":1,"visible":true}],"overlay_opacity":0,"audio":{},"wait":"Running","auto":false}
  eng.load(v2)
  assert_eq(eng.vm.scene, "s")
  assert_eq(eng.vm.ip, 0)
  assert_true(eng.vm.wait == Running)
  assert_true(eng.stage.get_var("met") == Bool(true))
  assert_eq(eng.stage.layers.length(), 1)
  assert_eq(eng.stage.layers[0].id, "bg")
  assert_true(eng.stage.layers[0].kind == Background)
  assert_eq(eng.stage.layers[0].tweens.length(), 0)
  assert_true(!eng.stage.layers[0].pending_hide)
  assert_eq(eng.stage.layers[0].scale, 1.0)
  assert_eq(eng.stage.wait_remaining, 0.0)
  assert_eq(eng.stage.fade_to, 0.0)
  assert_eq(eng.stage.fade_remaining, 0.0)
}

///|
test "save roundtrip restores bgm_volume" {
  @audio.reset_global_mixer()
  let eng = load_min_demo_engine()
  eng.stage.bgm = Some("bgm_soft")
  @audio.global_mixer().play_bgm("bgm_soft", volume=0.42)
  let blob = eng.save()
  let game = @runtime.parse_save_game(blob)
  assert_true(game.audio.bgm_volume is Some(0.42))
  @audio.reset_global_mixer()
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  guard eng2.stage.bgm is Some(stage_bgm) else { fail("stage bgm") }
  assert_eq(stage_bgm, "bgm_soft")
  assert_eq(@audio.global_mixer().bgm_volume, 0.42)
  guard @audio.global_mixer().bgm is Some(id) else { fail("mixer bgm") }
  assert_eq(id, "bgm_soft")
  @audio.reset_global_mixer()
}

///|
test "save header saved_at roundtrip and missing defaults empty" {
  let eng = load_min_demo_engine()
  eng.tick(None_)
  let blob = eng.save()
  let game = @runtime.parse_save_game(blob)
  assert_eq(game.format_version, 5)
  assert_eq(game.saved_at, "")
  // Explicit saved_at survives round-trip through JSON.
  let with_ts =
    #|{"format_version":3,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{},"layers":[],"overlay_opacity":0,"audio":{},"wait":"Running","auto":false,"fade_to":0,"fade_remaining":0,"wait_remaining":0,"saved_at":"2026-07-10T12:00:00Z"}
  let g2 = @runtime.parse_save_game(with_ts)
  assert_eq(g2.saved_at, "2026-07-10T12:00:00Z")
  assert_eq(g2.scene, "s")
  // Old v3 blob without saved_at still loads (default "").
  let legacy =
    #|{"format_version":3,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{},"layers":[],"overlay_opacity":0,"audio":{},"wait":"Running","auto":false,"fade_to":0,"fade_remaining":0,"wait_remaining":0}
  let g3 = @runtime.parse_save_game(legacy)
  assert_eq(g3.saved_at, "")
  assert_eq(g3.scene, "s")
}

///|
test "slot_label empty and filled" {
  assert_eq(slot_label(0, None), "Slot 0 (empty)")
  assert_eq(slot_label(3, None), "Slot 3 (empty)")
  let bare : SaveGame = {
    format_version: 3,
    module_id: "",
    scene: "chapter1",
    ip: 0,
    call_stack: [],
    vars: {},
    layers: [],
    text: None,
    overlay_opacity: 0.0,
    audio: {
      bgm: None,
      se: None,
      bgm_volume: None,
      bgm_fade_to: None,
      bgm_fade_remaining: None,
      bgm_fade_stop: None,
    },
    wait: Running,
    choices: None,
    choose_result_var: None,
    auto: false,
    fade_to: 0.0,
    fade_remaining: 0.0,
    wait_remaining: 0.0,
    dissolve_phase: 0,
    dissolve_total: 0.0,
    saved_at: "",
  }
  assert_eq(slot_label(1, Some(bare)), "Slot 1 · saved")
  let stamped = { ..bare, saved_at: "2026-07-10T12:00:00Z" }
  assert_eq(slot_label(2, Some(stamped)), "Slot 2 · 2026-07-10T12:00:00Z")
}

///|
test "save mid fade-out restores audible fade toward stop" {
  @audio.reset_global_mixer()
  let q = @audio.QueueBackend::new()
  let b : &@audio.AudioBackend = q
  @audio.install_mixer(@audio.Mixer::with_backend(b))
  let eng = load_min_demo_engine()
  eng.stage.bgm = Some("bgm_soft")
  @audio.global_mixer().play_bgm("bgm_soft", volume=1.0)
  // Stop with fade: stage clears immediately; mixer still holds track + fade.
  eng.stage.bgm = None
  @audio.global_mixer().fade_bgm_to(0.0, 1.0, stop=true)
  @audio.global_mixer().tick(0.5)
  assert_true(@audio.global_mixer().bgm is Some(_))
  assert_true(
    @audio.global_mixer().bgm_volume > 0.4 &&
    @audio.global_mixer().bgm_volume < 0.6,
  )
  let blob = eng.save()
  let game = @runtime.parse_save_game(blob)
  // Blob must carry mixer identity + fade-stop mid-state (not null bgm).
  guard game.audio.bgm is Some(saved_id) else { fail("saved bgm id") }
  assert_eq(saved_id, "bgm_soft")
  assert_true(game.audio.bgm_fade_stop is Some(true))
  assert_true(game.audio.bgm_fade_remaining is Some(_))
  @audio.reset_global_mixer()
  let q2 = @audio.QueueBackend::new()
  let b2 : &@audio.AudioBackend = q2
  @audio.install_mixer(@audio.Mixer::with_backend(b2))
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  // Stage stays clear during restored fade-out; mixer still holds the id.
  assert_true(eng2.stage.bgm is None)
  guard @audio.global_mixer().bgm is Some(id) else {
    fail("mixer bgm after load")
  }
  assert_eq(id, "bgm_soft")
  assert_true(@audio.global_mixer().bgm_fade_stop)
  assert_true(@audio.global_mixer().bgm_fade_remaining > 0.0)
  // Finish the restored fade → StopBgm; both stage and mixer clear.
  q2.clear()
  @audio.global_mixer().tick(1.0)
  assert_true(@audio.global_mixer().bgm is None)
  assert_true(eng2.stage.bgm is None)
  guard q2.get(q2.len() - 1) is Some(@audio.StopBgm) else { fail("StopBgm") }
  // Second save must not revive BGM after fade completed.
  let blob2 = eng2.save()
  let game2 = @runtime.parse_save_game(blob2)
  assert_true(game2.audio.bgm is None)
  @audio.reset_global_mixer()
}

///|
test "save roundtrip preserves layer scale" {
  let eng = load_min_demo_engine()
  eng.tick(Intent::Advance)
  eng.stage.start_layer_tween(
    id="bg",
    prop=@runtime.TweenProp::Scale,
    to=0.5,
    duration=0.0,
  )
  let blob = eng.save(slot=0)
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  assert_eq(eng2.stage.layers[0].scale, 0.5)
  let game = @runtime.parse_save_game(blob)
  assert_eq(game.format_version, 5)
}

///|
test "save rejects unsupported format_version message lists 2-5" {
  let eng = load_min_demo_engine()
  let bad =
    #|{"format_version":99,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{},"layers":[],"overlay_opacity":0,"audio":{},"wait":{"$tag":"Running"},"auto":false}
  try eng.load(bad) catch {
    err =>
      // Message must mention supported versions including 4
      assert_true(err.to_string().contains("4"))
  } noraise {
    _ => fail("expected UnsupportedVersion")
  }
}

///|
test "load v3 save without layer scale defaults to 1.0" {
  let eng = load_min_demo_engine()
  // v3 blob: layers lack `scale` (pre-scale field); must still decode.
  let v3 =
    #|{"format_version":3,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{},"layers":[{"id":"bg","kind":"Background","resource":"bg_room","z":0,"x":0,"y":0,"opacity":1,"visible":true,"tweens":[],"pending_hide":false}],"overlay_opacity":0,"audio":{},"wait":"Running","auto":false,"fade_to":0,"fade_remaining":0,"wait_remaining":0}
  eng.load(v3)
  assert_eq(eng.vm.scene, "s")
  assert_eq(eng.stage.layers.length(), 1)
  assert_eq(eng.stage.layers[0].id, "bg")
  assert_eq(eng.stage.layers[0].scale, 1.0)
  assert_eq(eng.stage.layers[0].tweens.length(), 0)
  assert_true(!eng.stage.layers[0].pending_hide)
}

///|
test "save writes configured module identity without requiring format v5" {
  let eng = load_min_demo_engine_for("demo-project")
  let game = @runtime.parse_save_game(eng.save())
  assert_eq(game.format_version, 5)
  assert_eq(game.module_id, "demo-project")
}

///|
test "load rejects a save from another module before mutating runtime state" {
  @audio.reset_global_mixer()
  let source = load_min_demo_engine_for("project-a")
  source.tick(None_)
  let blob = source.save()
  let target = load_min_demo_engine_for("project-b")
  target.tick(None_)
  target.stage.set_var("keep", Int(7))
  target.stage.overlay_opacity = 0.37
  target.auto = true
  target.ui.mode = Title
  let prefs_json =
    #|{"text_speed":1.5,"auto_mode":true,"master_volume":0.25,"bgm_volume":0.5,"se_volume":0.75}
  ignore(target.set_prefs_json(prefs_json))
  target.stage.bgm = Some("keep-bgm")
  @audio.global_mixer().play_bgm("keep-bgm", volume=0.6)
  let scene_before = target.vm.scene
  let ip_before = target.vm.ip
  let wait_before = target.vm.wait
  let layer_count_before = target.stage.layers.length()
  let ui_mode_before = target.ui.mode
  let prefs_before = target.ui.prefs
  let mixer_bgm_before = @audio.global_mixer().bgm
  let mixer_volume_before = @audio.global_mixer().bgm_volume
  let mixer_pref_master_before = @audio.global_mixer().pref_master
  let mixer_pref_bgm_before = @audio.global_mixer().pref_bgm
  let mixer_pref_se_before = @audio.global_mixer().pref_se
  try target.load(blob) catch {
    SaveError::ModuleMismatch(expected~, found~) => {
      assert_eq(expected, "project-b")
      assert_eq(found, "project-a")
    }
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected ModuleMismatch")
  }
  assert_eq(target.vm.scene, scene_before)
  assert_eq(target.vm.ip, ip_before)
  assert_true(target.vm.wait == wait_before)
  assert_true(target.stage.get_var("keep") == Int(7))
  assert_eq(target.stage.layers.length(), layer_count_before)
  assert_eq(target.stage.overlay_opacity, 0.37)
  assert_true(target.auto)
  assert_true(target.ui.mode == ui_mode_before)
  assert_true(target.ui.prefs == prefs_before)
  assert_true(@audio.global_mixer().bgm == mixer_bgm_before)
  assert_eq(@audio.global_mixer().bgm_volume, mixer_volume_before)
  assert_eq(@audio.global_mixer().pref_master, mixer_pref_master_before)
  assert_eq(@audio.global_mixer().pref_bgm, mixer_pref_bgm_before)
  assert_eq(@audio.global_mixer().pref_se, mixer_pref_se_before)
  @audio.reset_global_mixer()
}

///|
test "load accepts legacy v2 save without module identity in configured runtime" {
  let eng = load_min_demo_engine_for("project-a")
  let v2 =
    #|{"format_version":2,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{"met":["Bool",true]},"layers":[],"overlay_opacity":0,"audio":{},"wait":"Running","auto":false}
  eng.load(v2)
  assert_eq(eng.vm.scene, "s")
  assert_true(eng.stage.get_var("met") == Bool(true))
}

///|
test "load rejects unknown scene and stale ip before mutating state" {
  let eng = load_min_demo_engine_for("project-a")
  eng.tick(None_)
  eng.stage.set_var("keep", Str("yes"))
  let base = @runtime.parse_save_game(eng.save())
  let scene_before = eng.vm.scene
  let ip_before = eng.vm.ip
  let wait_before = eng.vm.wait
  let unknown = { ..base, scene: "missing" }.to_json().stringify()
  try eng.load(unknown) catch {
    SaveError::UnknownScene(scene~) => assert_eq(scene, "missing")
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected UnknownScene")
  }
  assert_eq(eng.vm.scene, scene_before)
  assert_eq(eng.vm.ip, ip_before)
  assert_true(eng.vm.wait == wait_before)
  assert_true(eng.stage.get_var("keep") == Str("yes"))
  let stale = { ..base, ip: 999 }.to_json().stringify()
  try eng.load(stale) catch {
    SaveError::InvalidInstructionPointer(scene~, ip~, max_ip~) => {
      assert_eq(scene, "s")
      assert_eq(ip, 999)
      assert_true(max_ip < 999)
    }
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected InvalidInstructionPointer")
  }
  assert_eq(eng.vm.scene, scene_before)
  assert_eq(eng.vm.ip, ip_before)
  assert_true(eng.vm.wait == wait_before)
  assert_true(eng.stage.get_var("keep") == Str("yes"))
}

///|
test "load rejects unsupported stack and inconsistent choice continuation" {
  let eng = load_min_demo_engine_for("project-a")
  let base = @runtime.parse_save_game(eng.save())
  let stacked = { ..base, call_stack: [{ scene: "s", ip: 0 }] }
    .to_json()
    .stringify()
  try eng.load(stacked) catch {
    SaveError::UnsupportedCallStack(depth~) => assert_eq(depth, 1)
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected UnsupportedCallStack")
  }
  let inconsistent = {
      ..base,
      wait: Choose,
      choices: None,
      choose_result_var: None,
    }
    .to_json()
    .stringify()
  try eng.load(inconsistent) catch {
    SaveError::InvalidContinuation(message~) =>
      assert_true(message.contains("Choose"))
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected InvalidContinuation")
  }
}

///|
test "supported save versions are authoritative and remain exactly v2 through v5" {
  assert_true(@runtime.is_supported_save_version(2))
  assert_true(@runtime.is_supported_save_version(3))
  assert_true(@runtime.is_supported_save_version(4))
  assert_true(@runtime.is_supported_save_version(5))
  assert_true(!@runtime.is_supported_save_version(1))
  assert_true(!@runtime.is_supported_save_version(6))
}

///|
test "validate_save exposes typed checks without mutating engine state" {
  let eng = load_min_demo_engine_for("project-a")
  eng.tick(None_)
  eng.stage.set_var("keep", Int(9))
  let game = @runtime.parse_save_game(eng.save())
  let invalid = { ..game, scene: "missing" }.to_json().stringify()
  let scene_before = eng.vm.scene
  let ip_before = eng.vm.ip
  try eng.validate_save(invalid) catch {
    SaveError::UnknownScene(scene~) => assert_eq(scene, "missing")
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected UnknownScene")
  }
  assert_eq(eng.vm.scene, scene_before)
  assert_eq(eng.vm.ip, ip_before)
  assert_true(eng.stage.get_var("keep") == Int(9))
}
