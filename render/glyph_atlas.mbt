///|
/// UV rectangle (pixels) for one glyph in the atlas texture.
///
/// CPU bitmap ownership lives on the host (JS canvas → WebGPU upload).
/// MoonBit only tracks bookkeeping rects and a pending queue.
pub(all) struct AtlasEntry {
  atlas_x : Int
  atlas_y : Int
  atlas_w : Int
  atlas_h : Int
  /// True until the host rasterizes this slot and calls `mark_ready`.
  pending : Bool
} derive(Debug, Eq)

///|
/// Maximum square atlas edge (H4). Single cells larger than this are
/// terminal 0×0 non-pending overflows.
let atlas_max_edge : Int = 4096

///|
/// Dynamic glyph atlas bookkeeping (no pixels).
///
/// Entries are nested maps: codepoint → px size → `AtlasEntry`. Nested keys
/// avoid 32-bit packed-key overflow for CJK (and higher) codepoints.
///
/// Packing cell is `size×size` pixels (approx). Layout pen advance is separate
/// (`measure` / `default_char_advance`) and may not equal the cell edge;
/// Task 12 host rasterization paints into the allocated cell and may refine
/// `atlas_w`/`atlas_h` via `mark_ready`.
///
/// On shelf overflow the square atlas doubles (up to `atlas_max_edge`),
/// bumps `generation`, and repacks all known glyphs so the host can rebuild
/// the GPU texture.
pub(all) struct GlyphAtlas {
  mut width : Int
  mut height : Int
  /// Bumped on every grow/repack so the host can discard stale GPU pixels.
  mut generation : Int
  /// codepoint → size_px → entry
  mut entries : Map[Int, Map[Int, AtlasEntry]]
  /// Shelf-pack cursor.
  mut cursor_x : Int
  mut cursor_y : Int
  mut row_h : Int
  /// Glyphs requested but not yet marked ready by the host.
  mut pending_queue : Array[(Char, Int)]
} derive(Debug)

///|
/// Create an empty atlas of the given pixel dimensions (default 1024×1024).
pub fn GlyphAtlas::new(width? : Int = 1024, height? : Int = 1024) -> GlyphAtlas {
  {
    width,
    height,
    generation: 0,
    entries: {},
    cursor_x: 0,
    cursor_y: 0,
    row_h: 0,
    pending_queue: [],
  }
}

///|
/// Normalize size used as the inner map key (non-negative).
fn atlas_size_key(size : Int) -> Int {
  if size < 0 {
    0
  } else {
    size
  }
}

///|
fn atlas_max2(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn atlas_min2(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// Smallest power of two ≥ `n` (clamped growth uses `atlas_max_edge` separately).
fn atlas_next_pow2(n : Int) -> Int {
  if n <= 1 {
    1
  } else {
    let mut p = 1
    while p < n {
      // Stop runaway if n is huge; caller also clamps to MAX.
      if p >= atlas_max_edge {
        return atlas_max_edge
      }
      p = p * 2
    }
    p
  }
}

///|
/// Terminal overflow: never re-queued; host skips 0×0.
fn atlas_terminal_entry() -> AtlasEntry {
  { atlas_x: 0, atlas_y: 0, atlas_w: 0, atlas_h: 0, pending: false }
}

///|
/// Look up an existing entry without allocating.
fn GlyphAtlas::lookup(self : GlyphAtlas, ch : Char, size : Int) -> AtlasEntry? {
  let cp = ch.to_int()
  let sk = atlas_size_key(size)
  match self.entries.get(cp) {
    None => None
    Some(by_size) => by_size.get(sk)
  }
}

///|
/// Insert or replace an entry under (codepoint, size).
fn GlyphAtlas::store(
  self : GlyphAtlas,
  ch : Char,
  size : Int,
  entry : AtlasEntry,
) -> Unit {
  let cp = ch.to_int()
  let sk = atlas_size_key(size)
  match self.entries.get(cp) {
    Some(by_size) => by_size[sk] = entry
    None => {
      let by_size : Map[Int, AtlasEntry] = {}
      by_size[sk] = entry
      self.entries[cp] = by_size
    }
  }
}

///|
/// Ensure `(ch, size)` is on the pending queue at most once.
fn GlyphAtlas::ensure_pending(self : GlyphAtlas, ch : Char, size : Int) -> Unit {
  let mut found = false
  for item in self.pending_queue {
    let (c, s) = item
    if c == ch && s == size {
      found = true
    }
  }
  if !found {
    self.pending_queue.push((ch, size))
  }
}

///|
/// Try to shelf-pack a cell. Returns `None` if it does not fit.
fn GlyphAtlas::try_shelf_place(
  self : GlyphAtlas,
  cw : Int,
  cell_h : Int,
) -> AtlasEntry? {
  if cw > self.width || cell_h > self.height {
    return None
  }
  if self.cursor_x + cw > self.width {
    self.cursor_x = 0
    self.cursor_y = self.cursor_y + self.row_h
    self.row_h = 0
  }
  if self.cursor_y + cell_h > self.height {
    return None
  }
  let e : AtlasEntry = {
    atlas_x: self.cursor_x,
    atlas_y: self.cursor_y,
    atlas_w: cw,
    atlas_h: cell_h,
    pending: true,
  }
  self.cursor_x = self.cursor_x + cw
  if cell_h > self.row_h {
    self.row_h = cell_h
  }
  Some(e)
}

///|
/// Grow square atlas and repack every known positive cell plus `(ch,size)`.
fn GlyphAtlas::grow_and_repack(
  self : GlyphAtlas,
  ch : Char,
  size : Int,
  cw : Int,
  cell_h : Int,
) -> AtlasEntry {
  let need = atlas_max2(cw, cell_h)
  let candidate = atlas_max2(self.width * 2, atlas_next_pow2(need))
  let new_edge = atlas_min2(atlas_max_edge, candidate)
  if new_edge <= self.width {
    let entry = atlas_terminal_entry()
    self.store(ch, size, entry)
    return entry
  }
  // Snapshot placements that still have positive cells (skip terminals).
  let known : Array[(Char, Int, Int, Int)] = []
  for cp, by_size in self.entries {
    for sk, e in by_size {
      if e.atlas_w > 0 && e.atlas_h > 0 {
        known.push((cp.unsafe_to_char(), sk, e.atlas_w, e.atlas_h))
      }
    }
  }
  self.width = new_edge
  self.height = new_edge
  self.generation = self.generation + 1
  self.entries = {}
  self.cursor_x = 0
  self.cursor_y = 0
  self.row_h = 0
  self.pending_queue = []
  for item in known {
    let (c, s, w, h) = item
    let _ = self.get_or_queue(c, s, cell_w=w, cell_h=h)
  }
  self.get_or_queue(ch, size, cell_w=cw, cell_h=cell_h)
}

///|
/// Look up or allocate a rect for `ch` at font pixel size `size` (lookup key).
///
/// `cell_w` / `cell_h` are shelf dimensions. Height should exceed the em size
/// slightly so canvas descenders (`g`, `y`, `p`, …) are not clipped.
///
/// Shelf overflow grows the square atlas up to 4096 (H4). A single cell larger
/// than MAX, or overflow after MAX, is a terminal 0×0 non-pending entry.
pub fn GlyphAtlas::get_or_queue(
  self : GlyphAtlas,
  ch : Char,
  size : Int,
  cell_w? : Int,
  cell_h? : Int,
) -> AtlasEntry {
  match self.lookup(ch, size) {
    Some(e) => {
      // If still pending (host stamp failed / font not ready), ensure the
      // pair is on the queue so JS can retry next frame.
      // Terminal overflows have pending=false and must not re-queue.
      if e.pending {
        self.ensure_pending(ch, size)
      }
      e
    }
    None => {
      let default_h = if size < 1 { 1 } else { size }
      let mut ht = match cell_h {
        None => default_h
        Some(h) => h
      }
      if ht < 1 {
        ht = 1
      }
      let cell_h = ht
      let mut cw = match cell_w {
        None => cell_h
        Some(w) => w
      }
      if cw < 1 {
        cw = 1
      }
      let need = atlas_max2(cw, cell_h)
      if need > atlas_max_edge {
        let entry = atlas_terminal_entry()
        self.store(ch, size, entry)
        return entry
      }
      match self.try_shelf_place(cw, cell_h) {
        Some(entry) => {
          self.store(ch, size, entry)
          self.pending_queue.push((ch, size))
          entry
        }
        None =>
          if self.width < atlas_max_edge {
            self.grow_and_repack(ch, size, cw, cell_h)
          } else {
            let entry = atlas_terminal_entry()
            self.store(ch, size, entry)
            entry
          }
      }
    }
  }
}

///|
/// Host finished rasterizing a glyph: clear pending and optionally update UV.
pub fn GlyphAtlas::mark_ready(
  self : GlyphAtlas,
  ch : Char,
  size : Int,
  atlas_x~ : Int,
  atlas_y~ : Int,
  atlas_w~ : Int,
  atlas_h~ : Int,
) -> Unit {
  self.store(ch, size, { atlas_x, atlas_y, atlas_w, atlas_h, pending: false })
  // Drop matching entries from the queue (stable filter).
  let kept : Array[(Char, Int)] = []
  for item in self.pending_queue {
    let (c, s) = item
    if !(c == ch && s == size) {
      kept.push(item)
    }
  }
  self.pending_queue = kept
}

///|
/// Snapshot of glyphs still waiting for host rasterization.
pub fn GlyphAtlas::take_pending(self : GlyphAtlas) -> Array[(Char, Int)] {
  let out = self.pending_queue.copy()
  self.pending_queue = []
  out
}

///|
/// Whether a glyph already has a non-pending atlas entry.
pub fn GlyphAtlas::contains(self : GlyphAtlas, ch : Char, size : Int) -> Bool {
  match self.lookup(ch, size) {
    Some({ pending: false, .. }) => true
    _ => false
  }
}

///|
/// Look up the current atlas entry for `(ch, size)` if present (pending or ready).
pub fn GlyphAtlas::get_entry(
  self : GlyphAtlas,
  ch : Char,
  size : Int,
) -> AtlasEntry? {
  self.lookup(ch, size)
}
