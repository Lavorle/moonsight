///|
test "rollback ring enforces count and byte limits with observable eviction" {
  let ring : RollbackRing[String] = RollbackRing::new(max_count=3, max_bytes=10)
  assert_true(ring.push("a", estimated_bytes=3) == Accepted(evicted=0))
  assert_true(ring.push("b", estimated_bytes=3) == Accepted(evicted=0))
  assert_true(ring.push("c", estimated_bytes=3) == Accepted(evicted=0))
  assert_true(ring.push("d", estimated_bytes=3) == Accepted(evicted=1))
  assert_eq(ring.count(), 3)
  assert_eq(ring.bytes(), 9)
  assert_eq(ring.evictions, 1)
  assert_eq(ring.high_water_bytes, 9)
  assert_true(ring.take_latest() == Checkpoint("d"))
  assert_eq(ring.bytes(), 6)
}

///|
test "oversize rollback checkpoint preserves usable history" {
  let ring : RollbackRing[String] = RollbackRing::new(max_count=3, max_bytes=10)
  ignore(ring.push("usable", estimated_bytes=4))
  assert_true(
    ring.push("too-large", estimated_bytes=11) ==
    RejectedOversize(estimated_bytes=11, max_bytes=10),
  )
  assert_eq(ring.count(), 1)
  assert_eq(ring.bytes(), 4)
  assert_eq(ring.rejections, 1)
  assert_true(ring.take_latest() == Checkpoint("usable"))
}

///|
test "rollback barriers clear reachability and next capture re-enables rollback" {
  let ring : RollbackRing[String] = RollbackRing::new()
  ignore(ring.push("before", estimated_bytes=10))
  ring.apply_barrier("rollback.barrier.audio-se")
  assert_eq(ring.count(), 0)
  assert_eq(ring.bytes(), 0)
  assert_true(
    ring.take_latest() == Unavailable("rollback.barrier.audio-se"),
  )
  ignore(ring.push("after", estimated_bytes=10))
  assert_true(ring.take_latest() == Checkpoint("after"))
}

///|
test "rollback default limits are frozen at 64 entries and 16 MiB" {
  let ring : RollbackRing[Int] = RollbackRing::new()
  assert_eq(ring.max_count, 64)
  assert_eq(ring.max_bytes, 16 * 1024 * 1024)
}
