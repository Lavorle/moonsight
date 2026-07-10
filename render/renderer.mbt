///|
/// Pack a full `DrawList` into one float buffer for the host frame loop.
///
/// Combined layout (version 1):
/// ```
/// [version, sprite_count, glyph_count, veil_opacity,
///  ...sprites (7 floats each),
///  ...glyphs (10 floats each)]
/// ```

///|
/// Allocate and fill a combined pack from `list`, interning resource names.
pub fn pack_draw_list(
  list : DrawList,
  resources : ResourceTable,
) -> FixedArray[Float] {
  let sc = list.sprites.length()
  let gc = list.glyphs.length()
  let len = pack_header_len + sc * sprite_stride + gc * glyph_stride
  let out : FixedArray[Float] = FixedArray::make(len, 0.0)
  out[0] = pack_version
  out[1] = Float::from_int(sc)
  out[2] = Float::from_int(gc)
  out[3] = list.veil_opacity
  let after_sprites = write_sprites(
    out,
    pack_header_len,
    list.sprites,
    resources,
  )
  ignore(write_glyphs(out, after_sprites, list.glyphs))
  out
}

///|
/// Byte length of a combined pack for a given sprite/glyph counts.
pub fn pack_byte_length(sprite_count : Int, glyph_count : Int) -> Int {
  (pack_header_len + sprite_count * sprite_stride + glyph_count * glyph_stride) *
  4
}

///|
/// Read sprite_count from a combined pack (0 if too short).
pub fn pack_sprite_count(pack : FixedArray[Float]) -> Int {
  if pack.length() < pack_header_len {
    0
  } else {
    pack[1].to_int()
  }
}

///|
/// Read glyph_count from a combined pack (0 if too short).
pub fn pack_glyph_count(pack : FixedArray[Float]) -> Int {
  if pack.length() < pack_header_len {
    0
  } else {
    pack[2].to_int()
  }
}

///|
/// Read veil opacity from a combined pack (0 if too short).
pub fn pack_veil(pack : FixedArray[Float]) -> Float {
  if pack.length() < pack_header_len {
    0.0
  } else {
    pack[3]
  }
}
