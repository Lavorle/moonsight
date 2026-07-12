///|
/// One completed dialogue line retained for session backlog UI.
pub(all) struct BacklogEntry {
  speaker : String?
  text : String
  /// Stable catalog references retained across locale changes.
  speaker_id : String?
  text_id : String?
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
pub fn BacklogStore::new(capacity? : Int = 100) -> BacklogStore {
  let cap = if capacity < 1 { 1 } else { capacity }
  { entries: [], capacity: cap }
}

///|
/// Append a completed line; drop oldest when over capacity.
pub fn BacklogStore::push(
  self : BacklogStore,
  speaker~ : String?,
  text~ : String,
  speaker_id? : String = "",
  text_id? : String = "",
) -> Unit {
  self.entries.push({
    speaker,
    text,
    speaker_id: if speaker_id == "" { None } else { Some(speaker_id) },
    text_id: if text_id == "" { None } else { Some(text_id) },
  })
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

///|
/// Re-resolve stable backlog references for a locale switch. Resolution is
/// prepared in a separate array so any missing catalog key leaves all existing
/// display strings unchanged.
pub fn BacklogStore::relocalize(
  self : BacklogStore,
  catalogs : LocaleCatalogs,
  locale : String,
) -> Unit raise {
  let prepared : Array[BacklogEntry] = []
  for entry in self.entries {
    let speaker = match entry.speaker_id {
      Some(id) => Some(catalogs.resolve(locale, id))
      None => entry.speaker
    }
    let text = match entry.text_id {
      Some(id) => catalogs.resolve(locale, id)
      None => entry.text
    }
    prepared.push({ ..entry, speaker, text })
  }
  self.entries = prepared
}
