///|
/// Packed-frame layout constants shared by MoonBit packers and JS bridge.
///
/// **GPU ownership:** WebGPU lives in JS (`MoonSightGpu`). MoonBit only packs
/// draw data as floats and tracks logical resource ids / atlas bookkeeping.
/// See `docs/draw-list-pack.md`.

///|
/// Pack format version written at index 0 of a combined frame buffer.
pub let pack_version : Float = 1.0

///|
/// Floats per sprite record after the header: x,y,w,h,opacity,resId,z
pub let sprite_stride : Int = 7

///|
/// Floats per glyph record:
/// `atlas_x,atlas_y,atlas_w,atlas_h, x,y, screen_w,screen_h, r,g,b,a`
pub let glyph_stride : Int = 12

///|
/// Combined pack header length:
/// `[version, sprite_count, glyph_count, veil_opacity]`
pub let pack_header_len : Int = 4

///|
/// Logical resource id table: string resource keys ↔ dense Int ids for packing.
///
/// Id `0` is reserved for the missing / solid-white placeholder texture.
pub(all) struct ResourceTable {
  mut next_id : Int
  mut name_to_id : Map[String, Int]
  mut id_to_name : Array[String]
} derive(Debug)

///|
/// Empty table with placeholder id 0 registered as `""`.
pub fn ResourceTable::new() -> ResourceTable {
  let name_to_id : Map[String, Int] = {}
  name_to_id[""] = 0
  { next_id: 1, name_to_id, id_to_name: [""] }
}

///|
/// Intern a resource name; returns a stable positive id (or 0 for empty).
pub fn ResourceTable::intern(self : ResourceTable, name : String) -> Int {
  if name.length() == 0 {
    return 0
  }
  match self.name_to_id.get(name) {
    Some(id) => id
    None => {
      let id = self.next_id
      self.next_id = id + 1
      self.name_to_id[name] = id
      self.id_to_name.push(name)
      id
    }
  }
}

///|
/// Resolve a packed resource id back to its string key (empty if unknown).
pub fn ResourceTable::name_of(self : ResourceTable, id : Int) -> String {
  if id < 0 || id >= self.id_to_name.length() {
    ""
  } else {
    self.id_to_name[id]
  }
}

///|
/// Number of registered names including the empty placeholder.
pub fn ResourceTable::count(self : ResourceTable) -> Int {
  self.id_to_name.length()
}

///|
/// Intent codes for the host ↔ engine bridge (see `docs/draw-list-pack.md`).
///
/// - `0` None
/// - `1` Advance
/// - `2` SkipTyping
/// - `3` OpenMenu
/// - `4` ToggleAuto
/// - `10 + n` Select(n)
pub fn intent_from_code(code : Int) -> @runtime.Intent {
  if code >= 10 {
    @runtime.Intent::Select(code - 10)
  } else {
    match code {
      1 => @runtime.Intent::Advance
      2 => @runtime.Intent::SkipTyping
      3 => @runtime.Intent::OpenMenu
      4 => @runtime.Intent::ToggleAuto
      _ => @runtime.Intent::None_
    }
  }
}

///|
/// Inverse of `intent_from_code` for tests / debugging.
pub fn intent_to_code(intent : @runtime.Intent) -> Int {
  match intent {
    None_ => 0
    Advance => 1
    SkipTyping => 2
    OpenMenu => 3
    ToggleAuto => 4
    Select(n) => 10 + n
  }
}

///|
/// Documentation stub: GPU device init is owned by JS (`MoonSightGpu.init`).
///
/// MoonBit does not call WebGPU directly in Phase 1 (reduces FFI risk).
pub fn gpu_owned_by_js() -> Bool {
  true
}
