///|
/// Pack sprites into a dense float buffer for the JS WebGPU bridge.
///
/// Layout (after optional external header): for each sprite
/// `x, y, w, h, opacity, resId, z` — see `docs/draw-list-pack.md`.

///|
/// Write `sprites` into `out` starting at `offset`. Interns resource names.
/// Returns the next write index.
pub fn write_sprites(
  out : FixedArray[Float],
  offset : Int,
  sprites : Array[SpriteDraw],
  resources : ResourceTable,
) -> Int {
  let mut i = offset
  for s in sprites {
    out[i] = s.x
    out[i + 1] = s.y
    out[i + 2] = s.w
    out[i + 3] = s.h
    out[i + 4] = s.opacity
    out[i + 5] = Float::from_int(resources.intern(s.resource))
    out[i + 6] = Float::from_int(s.z)
    i = i + sprite_stride
  }
  i
}

///|
/// Standalone sprite pack: `[count, ...records]` (no version/veil header).
pub fn pack_sprites(
  sprites : Array[SpriteDraw],
  resources : ResourceTable,
) -> FixedArray[Float] {
  let n = sprites.length()
  let out : FixedArray[Float] = FixedArray::make(1 + n * sprite_stride, 0.0)
  out[0] = Float::from_int(n)
  ignore(write_sprites(out, 1, sprites, resources))
  out
}

///|
/// Write glyph quads into `out` starting at `offset`.
///
/// Each glyph: `atlas_x, atlas_y, atlas_w, atlas_h, x, y, r, g, b, a`.
pub fn write_glyphs(
  out : FixedArray[Float],
  offset : Int,
  glyphs : Array[GlyphDraw],
) -> Int {
  let mut i = offset
  for g in glyphs {
    out[i] = Float::from_int(g.atlas_x)
    out[i + 1] = Float::from_int(g.atlas_y)
    out[i + 2] = Float::from_int(g.atlas_w)
    out[i + 3] = Float::from_int(g.atlas_h)
    out[i + 4] = g.x
    out[i + 5] = g.y
    out[i + 6] = g.color.r
    out[i + 7] = g.color.g
    out[i + 8] = g.color.b
    out[i + 9] = g.color.a
    i = i + glyph_stride
  }
  i
}

///|
/// Standalone glyph pack: `[count, ...records]`.
pub fn pack_glyphs(glyphs : Array[GlyphDraw]) -> FixedArray[Float] {
  let n = glyphs.length()
  let out : FixedArray[Float] = FixedArray::make(1 + n * glyph_stride, 0.0)
  out[0] = Float::from_int(n)
  ignore(write_glyphs(out, 1, glyphs))
  out
}
