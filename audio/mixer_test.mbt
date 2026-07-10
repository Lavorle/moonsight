///|
test "bgm play and stop update logical state" {
  let m = Mixer::new()
  m.play_bgm("bgm_soft", looped=true, volume=0.8)
  guard m.bgm is Some(id) else { fail("expected bgm") }
  assert_eq(id, "bgm_soft")
  assert_eq(m.bgm_volume, 0.8)
  assert_true(m.bgm_loop)
  m.stop_bgm()
  assert_true(m.bgm is None)
}

///|
test "play_se bumps sequence and records last id" {
  let m = Mixer::new()
  m.play_se("click", volume=0.5)
  guard m.se is Some(a) else { fail("se") }
  assert_eq(a, "click")
  assert_eq(m.se_volume, 0.5)
  assert_eq(m.se_seq, 1)
  m.play_se("click")
  assert_eq(m.se_seq, 2)
}

///|
test "queue backend records play stop se events" {
  let q = QueueBackend::new()
  let b : &AudioBackend = q
  let m = Mixer::with_backend(b)
  m.play_bgm("bgm_soft", looped=true, volume=0.8)
  m.play_se("click", volume=1.0)
  m.stop_bgm()
  assert_eq(q.len(), 3)
  guard q.get(0) is Some(PlayBgm(resource~, looped~, volume~)) else {
    fail("PlayBgm")
  }
  assert_eq(resource, "bgm_soft")
  assert_true(looped)
  assert_eq(volume, 0.8)
  guard q.get(1) is Some(PlaySe(resource=se_res, volume=se_vol)) else {
    fail("PlaySe")
  }
  assert_eq(se_res, "click")
  assert_eq(se_vol, 1.0)
  guard q.get(2) is Some(StopBgm) else { fail("StopBgm") }
  let taken = q.take()
  assert_eq(taken.length(), 3)
  assert_eq(q.len(), 0)
}

///|
test "stop_bgm when already silent does not enqueue" {
  let q = QueueBackend::new()
  let m = Mixer::with_backend((q : &AudioBackend))
  m.stop_bgm()
  assert_eq(q.len(), 0)
}

///|
test "apply_logic restores bgm without replaying se" {
  let q = QueueBackend::new()
  let m = Mixer::with_backend((q : &AudioBackend))
  m.apply_logic(Some("bgm_soft"), Some("click"))
  guard m.bgm is Some(id) else { fail("bgm") }
  assert_eq(id, "bgm_soft")
  guard m.se is Some(se) else { fail("se mirror") }
  assert_eq(se, "click")
  // only BGM play, no SE event
  assert_eq(q.len(), 1)
  guard q.get(0) is Some(PlayBgm(resource~, ..)) else { fail("bgm only") }
  assert_eq(resource, "bgm_soft")
}

///|
test "global mixer install and host-style play" {
  reset_global_mixer()
  let q = QueueBackend::new()
  install_mixer(Mixer::with_backend((q : &AudioBackend)))
  global_mixer().play_bgm("bgm_soft")
  global_mixer().play_se("click")
  assert_eq(q.len(), 2)
  reset_global_mixer()
}

///|
test "bgm fade approaches target volume" {
  let q = QueueBackend::new()
  let m = Mixer::with_backend((q : &AudioBackend))
  m.play_bgm("a", volume=0.0)
  q.clear()
  m.fade_bgm_to(1.0, 1.0)
  m.tick(0.5)
  // volume mid ~0.5
  assert_true(m.bgm_volume > 0.4 && m.bgm_volume < 0.6)
  m.tick(0.5)
  assert_true(m.bgm_volume >= 0.99)
  // Mid-fade and end emit SetBgmVolume (not PlayBgm).
  assert_true(q.len() >= 2)
  guard q.get(0) is Some(SetBgmVolume(volume~)) else { fail("SetBgmVolume") }
  assert_true(volume > 0.4 && volume < 0.6)
}

///|
test "bgm fade stop reaches zero then stops" {
  let q = QueueBackend::new()
  let m = Mixer::with_backend((q : &AudioBackend))
  m.play_bgm("a", volume=1.0)
  q.clear()
  m.fade_bgm_to(0.0, 1.0, stop=true)
  m.tick(0.5)
  assert_true(m.bgm is Some(_))
  assert_true(m.bgm_volume > 0.4 && m.bgm_volume < 0.6)
  m.tick(0.5)
  assert_true(m.bgm is None)
  guard q.get(q.len() - 1) is Some(StopBgm) else { fail("StopBgm at end") }
}
