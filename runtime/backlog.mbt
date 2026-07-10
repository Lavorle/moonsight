///|
/// One completed dialogue line retained for session backlog UI.
pub(all) struct BacklogEntry {
  speaker : String?
  text : String
} derive(Debug, Eq)

///|
/// Ring buffer of completed dialogue lines (oldest at index 0).
///
/// When `push` would exceed `capacity`, the oldest entry is dropped.
pub(all) struct BacklogStore {
  mut entries : Array[BacklogEntry]
  capacity : Int
}

///|
/// Create an empty backlog. Default capacity is 100 lines.
pub fn BacklogStore::new(capacity~ : Int = 100) -> BacklogStore {
  let cap = if capacity < 1 { 1 } else { capacity }
  {
    entries: [],
    capacity: cap,
  }
}

///|
/// Append a completed line; drop oldest when over capacity.
pub fn BacklogStore::push(
  self : BacklogStore,
  speaker~ : String?,
  text~ : String,
) -> Unit {
  self.entries.push({ speaker, text })
  while self.entries.length() > self.capacity {
    ignore(self.entries.remove(0))
  }
}

///|
/// Remove all entries.
pub fn BacklogStore::clear(self : BacklogStore) -> Unit {
  self.entries.clear()
}

///|
/// Number of retained lines.
pub fn BacklogStore::len(self : BacklogStore) -> Int {
  self.entries.length()
}

///|
/// Entry at index `i` (0 = oldest). Panics if out of range.
pub fn BacklogStore::get(self : BacklogStore, i : Int) -> BacklogEntry {
  self.entries[i]
}
