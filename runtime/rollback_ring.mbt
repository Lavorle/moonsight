///|
pub(all) struct RollbackCheckpoint[T] {
  state : T
  estimated_bytes : Int
}

///|
pub(all) enum RollbackPushResult {
  Accepted(evicted~ : Int)
  RejectedOversize(estimated_bytes~ : Int, max_bytes~ : Int)
  RejectedInvalidSize(Int)
} derive(Debug, Eq)

///|
pub(all) enum RollbackTake[T] {
  Checkpoint(T)
  Unavailable(String)
} derive(Debug, Eq)

///|
/// Bounded rollback checkpoint storage. The payload type remains owned by the
/// shared logical-state kernel; this type owns only reachability/accounting.
pub(all) struct RollbackRing[T] {
  entries : Array[RollbackCheckpoint[T]]
  max_count : Int
  max_bytes : Int
  mut retained_bytes : Int
  mut high_water_bytes : Int
  mut evictions : Int
  mut rejections : Int
  mut barriers : Int
  mut last_barrier : String?
}

///|
pub fn[T] RollbackRing::new(
  max_count? : Int = 64,
  max_bytes? : Int = 16 * 1024 * 1024,
) -> RollbackRing[T] raise {
  if max_count <= 0 {
    fail("rollback max_count must be positive")
  }
  if max_bytes <= 0 {
    fail("rollback max_bytes must be positive")
  }
  {
    entries: [],
    max_count,
    max_bytes,
    retained_bytes: 0,
    high_water_bytes: 0,
    evictions: 0,
    rejections: 0,
    barriers: 0,
    last_barrier: None,
  }
}

///|
pub fn[T] RollbackRing::count(self : RollbackRing[T]) -> Int {
  self.entries.length()
}

///|
pub fn[T] RollbackRing::bytes(self : RollbackRing[T]) -> Int {
  self.retained_bytes
}

///|
/// Add a checkpoint, evicting oldest entries until both frozen limits hold.
/// A single oversize checkpoint is rejected before history is changed.
pub fn[T] RollbackRing::push(
  self : RollbackRing[T],
  state : T,
  estimated_bytes~ : Int,
) -> RollbackPushResult {
  if estimated_bytes < 0 {
    self.rejections += 1
    return RejectedInvalidSize(estimated_bytes)
  }
  if estimated_bytes > self.max_bytes {
    self.rejections += 1
    return RejectedOversize(estimated_bytes~, max_bytes=self.max_bytes)
  }
  let mut evicted = 0
  while self.entries.length() >= self.max_count ||
        self.retained_bytes + estimated_bytes > self.max_bytes {
    let oldest = self.entries.remove(0)
    self.retained_bytes -= oldest.estimated_bytes
    self.evictions += 1
    evicted += 1
  }
  self.entries.push({ state, estimated_bytes })
  self.retained_bytes += estimated_bytes
  if self.retained_bytes > self.high_water_bytes {
    self.high_water_bytes = self.retained_bytes
  }
  self.last_barrier = None
  Accepted(evicted~)
}

///|
/// Remove the newest reachable checkpoint, or return a stable diagnostic.
pub fn[T] RollbackRing::take_latest(self : RollbackRing[T]) -> RollbackTake[T] {
  match self.entries.pop() {
    Some(entry) => {
      self.retained_bytes -= entry.estimated_bytes
      Checkpoint(entry.state)
    }
    None =>
      match self.last_barrier {
        Some(reason) => Unavailable(reason)
        None => Unavailable("rollback.unavailable.empty")
      }
  }
}

///|
/// Clear session history for new game, successful load, or return to title.
pub fn[T] RollbackRing::clear(self : RollbackRing[T]) -> Unit {
  self.entries.clear()
  self.retained_bytes = 0
  self.last_barrier = None
}

///|
/// A successful irreversible effect clears all older reachability and leaves a
/// visible reason until a later checkpoint is successfully captured.
pub fn[T] RollbackRing::apply_barrier(
  self : RollbackRing[T],
  reason : String,
) -> Unit {
  self.entries.clear()
  self.retained_bytes = 0
  self.barriers += 1
  self.last_barrier = Some(reason)
}

///|
/// Apply Director effect policy after execution. Failed effects never change
/// reachability; checkpointed and compensatable effects preserve history.
pub fn[T] RollbackRing::after_effect(
  self : RollbackRing[T],
  effect : CommandEffect,
  succeeded~ : Bool,
) -> Unit {
  if !succeeded {
    return
  }
  match effect {
    Barrier(reason) => self.apply_barrier(reason)
    Checkpointed | CompensatableAudio => ()
  }
}
