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
/// Key: packed `codepoint * 65536 + (size & 0xFFFF)`.
pub(all) struct GlyphAtlas {
  width : Int
  height : Int
  mut entries : Map[Int, AtlasEntry]
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
/// Pack codepoint + px size into a map key.
pub fn atlas_key(ch : Char, size : Int) -> Int {
  let s = if size < 0 { 0 } else { size & 0xFFFF }
  ch.to_int() * 65536 + s
}

///|
/// Look up or allocate a rect for `ch` at `size` (approx cell = size×size).
///
/// Missing glyphs are shelf-packed and appended to `pending_queue` for the host
/// to rasterize. Atlas overflow reuses a 0×0 pending placeholder.
pub fn GlyphAtlas::get_or_queue(
  self : GlyphAtlas,
  ch : Char,
  size : Int,
) -> AtlasEntry {
  let key = atlas_key(ch, size)
  match self.entries.get(key) {
    Some(e) => e
    None => {
      let cell = if size < 1 { 1 } else { size }
      // Advance to next row when this cell does not fit.
      if self.cursor_x + cell > self.width {
        self.cursor_x = 0
        self.cursor_y = self.cursor_y + self.row_h
        self.row_h = 0
      }
      let entry : AtlasEntry = if self.cursor_y + cell > self.height {
        // Overflow: zero rect; still track so callers do not re-queue forever.
        { atlas_x: 0, atlas_y: 0, atlas_w: 0, atlas_h: 0, pending: true }
      } else {
        let e : AtlasEntry = {
          atlas_x: self.cursor_x,
          atlas_y: self.cursor_y,
          atlas_w: cell,
          atlas_h: cell,
          pending: true,
        }
        self.cursor_x = self.cursor_x + cell
        if cell > self.row_h {
          self.row_h = cell
        }
        e
      }
      self.entries[key] = entry
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
  let key = atlas_key(ch, size)
  self.entries[key] = { atlas_x, atlas_y, atlas_w, atlas_h, pending: false }
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
  match self.entries.get(atlas_key(ch, size)) {
    Some({ pending: false, .. }) => true
    _ => false
  }
}
