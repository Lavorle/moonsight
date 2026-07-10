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
/// Dynamic glyph atlas bookkeeping (no pixels).
///
/// Entries are nested maps: codepoint → px size → `AtlasEntry`. Nested keys
/// avoid 32-bit packed-key overflow for CJK (and higher) codepoints.
///
/// Packing cell is `size×size` pixels (approx). Layout pen advance is separate
/// (`measure` / `default_char_advance`) and may not equal the cell edge;
/// Task 12 host rasterization paints into the allocated cell and may refine
/// `atlas_w`/`atlas_h` via `mark_ready`.
pub(all) struct GlyphAtlas {
  width : Int
  height : Int
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
/// Look up or allocate a rect for `ch` at font pixel height `size`.
///
/// `cell_w` is the shelf cell width (usually measured advance + padding). Cell
/// height is `size`. Missing glyphs are shelf-packed and queued for the host
/// to rasterize (bitmap or Slug-style outline). Overflow → 0×0 placeholder.
pub fn GlyphAtlas::get_or_queue(
  self : GlyphAtlas,
  ch : Char,
  size : Int,
  cell_w? : Int,
) -> AtlasEntry {
  match self.lookup(ch, size) {
    Some(e) => {
      // If still pending (host stamp failed / font not ready), ensure the
      // pair is on the queue so JS can retry next frame.
      if e.pending {
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
      e
    }
    None => {
      let cell_h = if size < 1 { 1 } else { size }
      let mut cw = match cell_w {
        None => cell_h
        Some(w) => w
      }
      if cw < 1 {
        cw = 1
      }
      // Cell must fit in atlas dimensions; otherwise 0×0 overflow placeholder.
      let entry : AtlasEntry = if cw > self.width || cell_h > self.height {
        { atlas_x: 0, atlas_y: 0, atlas_w: 0, atlas_h: 0, pending: true }
      } else {
        // Advance to next row when this cell does not fit on the current shelf.
        if self.cursor_x + cw > self.width {
          self.cursor_x = 0
          self.cursor_y = self.cursor_y + self.row_h
          self.row_h = 0
        }
        if self.cursor_y + cell_h > self.height {
          // Overflow: zero rect; still track so callers do not re-queue forever.
          { atlas_x: 0, atlas_y: 0, atlas_w: 0, atlas_h: 0, pending: true }
        } else {
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
          e
        }
      }
      self.store(ch, size, entry)
      self.pending_queue.push((ch, size))
      entry
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
