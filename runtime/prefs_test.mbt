///|
test "prefs defaults" {
  let p = Prefs::default()
  assert_eq(p.text_speed, 1.0)
  assert_true(!p.auto_mode)
  assert_eq(p.master_volume, 1.0)
  assert_eq(p.bgm_volume, 1.0)
  assert_eq(p.se_volume, 1.0)
}

///|
test "prefs clamp ranges" {
  let p : Prefs = {
    text_speed: 10.0,
    auto_mode: true,
    master_volume: 2.0,
    bgm_volume: -0.5,
    se_volume: 0.5,
  }
  let c = p.clamp()
  assert_eq(c.text_speed, 3.0)
  assert_true(c.auto_mode)
  assert_eq(c.master_volume, 1.0)
  assert_eq(c.bgm_volume, 0.0)
  assert_eq(c.se_volume, 0.5)
  let lo : Prefs = {
    text_speed: 0.0,
    auto_mode: false,
    master_volume: -1.0,
    bgm_volume: 1.5,
    se_volume: 3.0,
  }
  let c2 = lo.clamp()
  assert_eq(c2.text_speed, 0.25)
  assert_eq(c2.master_volume, 0.0)
  assert_eq(c2.bgm_volume, 1.0)
  assert_eq(c2.se_volume, 1.0)
}

///|
test "prefs adjust and set clamp" {
  let p = Prefs::default()
  let p2 = p.adjust("text_speed", 5.0)
  assert_eq(p2.text_speed, 3.0)
  let p3 = p.adjust("master_volume", -2.0)
  assert_eq(p3.master_volume, 0.0)
  let p4 = p.adjust("bgm_volume", -0.25)
  assert_eq(p4.bgm_volume, 0.75)
  let p5 = p.set("se_volume", Float(0.3))
  assert_eq(p5.se_volume, 0.3)
  let p6 = p.set("text_speed", Int(2))
  assert_eq(p6.text_speed, 2.0)
  let p7 = p.set("auto_mode", Bool(true))
  assert_true(p7.auto_mode)
  let p8 = p.set("master_volume", Float(9.0))
  assert_eq(p8.master_volume, 1.0)
  // unknown key / wrong type leaves prefs unchanged
  let p9 = p.set("nope", Float(1.0))
  assert_eq(p9.text_speed, p.text_speed)
  assert_eq(p9.master_volume, p.master_volume)
  let p10 = p.set("text_speed", Bool(true))
  assert_eq(p10.text_speed, p.text_speed)
}

///|
test "prefs json roundtrip" {
  let p = Prefs::default()
    .set("text_speed", Float(1.5))
    .set("auto_mode", Bool(true))
    .set("master_volume", Float(0.8))
    .set("bgm_volume", Float(0.6))
    .set("se_volume", Float(0.4))
  let s = p.to_json_string()
  let p2 = Prefs::from_json_string(s)
  assert_eq(p2.text_speed, 1.5)
  assert_true(p2.auto_mode)
  assert_eq(p2.master_volume, 0.8)
  assert_eq(p2.bgm_volume, 0.6)
  assert_eq(p2.se_volume, 0.4)
}

///|
test "prefs from_json missing fields use defaults and clamp" {
  let partial =
    #|{"text_speed": 9.0, "bgm_volume": 0.2}
  let p = Prefs::from_json_string(partial)
  assert_eq(p.text_speed, 3.0)
  assert_true(!p.auto_mode)
  assert_eq(p.master_volume, 1.0)
  assert_eq(p.bgm_volume, 0.2)
  assert_eq(p.se_volume, 1.0)
  let empty = Prefs::from_json_string("{}")
  let d = Prefs::default()
  assert_eq(empty.text_speed, d.text_speed)
  assert_true(empty.auto_mode == d.auto_mode)
  assert_eq(empty.master_volume, d.master_volume)
  assert_eq(empty.bgm_volume, d.bgm_volume)
  assert_eq(empty.se_volume, d.se_volume)
}

///|
test "prefs from_json rejects invalid json" {
  try Prefs::from_json_string("not-json") catch {
    _ => ()
  } noraise {
    _ => fail("expected error on invalid json")
  }
}
