///|
/// Browser host entry: export packed frames; JS owns WebGPU.
///
/// Architecture (Phase 1):
/// - MoonBit: Engine tick + `build_draw_list` + float pack
/// - JS: `MoonSightGpu` pipelines / textures / submit
///
/// Wasm-GC arrays are opaque to JS, so the pack is exposed via
/// `export_frame` (returns length) + `frame_at`.

///|
struct HostSession {
  mut engine : @runtime.Engine?
  mut atlas : @render.GlyphAtlas
  mut resources : @render.ResourceTable
  layout : @render.UiLayout
  mut frame : FixedArray[Float]
}

///|
let session : Ref[HostSession] = Ref({
  engine: None,
  atlas: @render.GlyphAtlas::new(),
  resources: @render.ResourceTable::new(),
  layout: @render.UiLayout::default_fhd(),
  frame: (FixedArray::make(0, 0.0) : FixedArray[Float]),
})

///|
fn demo_source() -> String {
  // Keep syntax aligned with runtime smoke tests (speaker dialogue + layer).
  let src =
    #|- scene "main"
    #|@layer.show "bg" "bg/demo"
    #|yuki:Welcome to MoonSight.
    #|yuki:WebGPU host smoke — click or press Enter to advance.
    #|
  src
}

///|
/// Boot a built-in demo script with the full standard host registry.
pub fn init_demo() -> Unit {
  let src = demo_source()
  match load_source_inner(src, file="demo.yuki") {
    Ok(_) => ()
    Err(msg) => println("init_demo failed: \{msg}")
  }
}

///|
/// Compile MoonYuki source, install engine, reset atlas/resources/frame.
pub fn load_source(src : String) -> Int {
  match load_source_inner(src, file="fetched.yuki") {
    Ok(_) => 0
    Err(_) => 1
  }
}

///|
fn load_source_inner(src : String, file~ : String) -> Result[Unit, String] {
  let ir = @script.compile_to_ir(src, file~) catch {
    _ => return Err("compile failed")
  }
  let entry = ir.entry
  let eng = @runtime.Engine::from_ir(
    ir,
    entry~,
    director=@std_commands.standard_registry(),
  )
  let s = session.val
  s.engine = Some(eng)
  s.atlas = @render.GlyphAtlas::new()
  s.resources = @render.ResourceTable::new()
  s.frame = (FixedArray::make(0, 0.0) : FixedArray[Float])
  // Pre-intern common UI resources so JS can upload placeholders early.
  ignore(s.resources.intern(@render.ui_dialogue_box))
  ignore(s.resources.intern(@render.ui_nameplate))
  ignore(s.resources.intern(@render.ui_choice_row))
  ignore(s.resources.intern("bg/demo"))
  Ok(())
}

///|
/// Tick engine with intent/dt, pack draw list; returns pack length.
///
/// `intent_code` — see `docs/draw-list-pack.md`.
/// `dt_ms` — frame delta in milliseconds.
pub fn export_frame(intent_code : Int, dt_ms : Float) -> Int {
  let s = session.val
  match s.engine {
    None => {
      let empty : FixedArray[Float] = FixedArray::make(
        @render.pack_header_len, 0.0,
      )
      empty[0] = @render.pack_version
      s.frame = empty
      return s.frame.length()
    }
    Some(eng) => {
      let dt = dt_ms.to_double() / 1000.0
      let intent = @render.intent_from_code(intent_code)
      eng.tick(intent, dt~)
      let view = eng.view()
      let measure = @render.fixed_width_measure(s.layout.default_char_advance)
      let dl = @render.build_draw_list_with_atlas(
        view,
        s.layout,
        s.atlas,
        measure~,
      )
      s.frame = @render.pack_draw_list(dl, s.resources)
      s.frame.length()
    }
  }
}

///|
/// Length of the last packed frame.
pub fn frame_len() -> Int {
  session.val.frame.length()
}

///|
/// Read one float from the last packed frame (0 if out of range).
pub fn frame_at(i : Int) -> Float {
  let f = session.val.frame
  if i < 0 || i >= f.length() {
    0.0
  } else {
    f[i]
  }
}

///|
pub fn resource_count() -> Int {
  session.val.resources.count()
}

///|
pub fn resource_name(id : Int) -> String {
  session.val.resources.name_of(id)
}

///|
/// Snapshot engine save JSON (host stores under `moonsight/save/{slot}`).
pub fn save_json(slot : Int) -> String {
  let s = session.val
  match s.engine {
    None => ""
    Some(eng) => eng.save(slot~)
  }
}

///|
/// Apply a save JSON blob (0 ok, 1 error).
pub fn load_json(json : String) -> Int {
  let s = session.val
  match s.engine {
    None => 1
    Some(eng) =>
      try {
        eng.load(json)
        0
      } catch {
        _ => 1
      }
  }
}

///|
/// Number of glyphs waiting for host rasterization.
pub fn pending_glyph_count() -> Int {
  session.val.atlas.pending_queue.length()
}

///|
fn pending_pair(i : Int) -> (Char, Int)? {
  let q = session.val.atlas.pending_queue
  if i < 0 || i >= q.length() {
    None
  } else {
    Some(q[i])
  }
}

///|
/// Codepoint of pending glyph at index (0 if OOB).
pub fn pending_glyph_cp(i : Int) -> Int {
  match pending_pair(i) {
    None => 0
    Some((ch, _)) => ch.to_int()
  }
}

///|
/// Pixel size of pending glyph at index.
pub fn pending_glyph_size(i : Int) -> Int {
  match pending_pair(i) {
    None => 0
    Some((_, size)) => size
  }
}

///|
/// Atlas pixel X already allocated for pending glyph `i` (0 if missing).
pub fn pending_glyph_atlas_x(i : Int) -> Int {
  match pending_pair(i) {
    None => 0
    Some((ch, size)) =>
      match session.val.atlas.get_entry(ch, size) {
        None => 0
        Some(e) => e.atlas_x
      }
  }
}

///|
pub fn pending_glyph_atlas_y(i : Int) -> Int {
  match pending_pair(i) {
    None => 0
    Some((ch, size)) =>
      match session.val.atlas.get_entry(ch, size) {
        None => 0
        Some(e) => e.atlas_y
      }
  }
}

///|
pub fn pending_glyph_atlas_w(i : Int) -> Int {
  match pending_pair(i) {
    None => 0
    Some((ch, size)) =>
      match session.val.atlas.get_entry(ch, size) {
        None => 0
        Some(e) => e.atlas_w
      }
  }
}

///|
pub fn pending_glyph_atlas_h(i : Int) -> Int {
  match pending_pair(i) {
    None => 0
    Some((ch, size)) =>
      match session.val.atlas.get_entry(ch, size) {
        None => 0
        Some(e) => e.atlas_h
      }
  }
}

///|
/// Host finished rasterizing a glyph into the atlas texture.
pub fn mark_glyph_ready(
  cp : Int,
  size : Int,
  atlas_x : Int,
  atlas_y : Int,
  atlas_w : Int,
  atlas_h : Int,
) -> Unit {
  let ch = cp.unsafe_to_char()
  session.val.atlas.mark_ready(ch, size, atlas_x~, atlas_y~, atlas_w~, atlas_h~)
}

///|
/// Drain pending queue snapshot (after JS has read indices). Returns count drained.
pub fn clear_pending_glyphs() -> Int {
  let taken = session.val.atlas.take_pending()
  taken.length()
}

///|
fn main {
  // Linked as `_start`. Prefer explicit `init_demo` from JS after GPU init.
  println("moonsight host_web ready")
}
