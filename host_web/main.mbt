///|
/// Browser host entry: export packed frames; JS owns WebGPU and Web Audio.
///
/// Architecture (Phase 1):
/// - MoonBit: Engine tick + `build_draw_list` + float pack + logical audio mixer
/// - JS: `MoonSightGpu` pipelines / textures / submit; HTMLAudio / Web Audio playback
///
/// Wasm-GC arrays are opaque to JS, so the pack is exposed via
/// `export_frame` (returns length) + `frame_at`. Audio events drain via
/// `audio_event_*` exports.

///|
struct HostSession {
  mut engine : @runtime.Engine?
  mut atlas : @render.GlyphAtlas
  mut resources : @render.ResourceTable
  layout : @render.UiLayout
  mut frame : FixedArray[Float]
  /// Shared with the installed global mixer (`QueueBackend` records play/stop).
  mut audio_queue : @audio.QueueBackend
}

///|
let session : Ref[HostSession] = Ref({
  engine: None,
  atlas: @render.GlyphAtlas::new(),
  resources: @render.ResourceTable::new(),
  layout: @render.UiLayout::default_fhd(),
  frame: (FixedArray::make(0, 0.0) : FixedArray[Float]),
  audio_queue: @audio.QueueBackend::new(),
})

///|
/// Point the process-global mixer at this session's queue backend.
fn install_session_audio() -> Unit {
  let s = session.val
  let b : &@audio.AudioBackend = s.audio_queue
  @audio.install_mixer(@audio.Mixer::with_backend(b))
}

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
/// Load compiled MSB bytecode (binary string: each char code unit is one byte).
///
/// Preferred browser path: fetch `game.msb`, then pass Latin-1 / binary string.
/// Returns 0 on success, 1 on decode/install failure.
pub fn load_msb(raw : String) -> Int {
  match load_msb_inner(raw) {
    Ok(_) => 0
    Err(_) => 1
  }
}

///|
/// Last soft engine/VM error message (empty if none).
pub fn last_error() -> String {
  match session.val.engine {
    None => ""
    Some(eng) =>
      match eng.vm.last_error {
        None => ""
        Some(msg) => msg
      }
  }
}

///|
fn load_msb_inner(raw : String) -> Result[Unit, String] {
  let n = raw.length()
  let bytes = Bytes::makei(n, i => raw[i].to_byte())
  let ir = @script.decode_module(bytes) catch {
    _ => return Err("msb decode failed")
  }
  install_engine_from_ir(ir)
  Ok(())
}

///|
fn load_source_inner(src : String, file~ : String) -> Result[Unit, String] {
  let ir = @script.compile_to_ir(src, file~) catch {
    _ => return Err("compile failed")
  }
  install_engine_from_ir(ir)
  Ok(())
}

///|
fn install_engine_from_ir(ir : @script.IrModule) -> Unit {
  let entry = ir.entry
  let app = @runtime.UiApp::new()
  @std_ui.register(app)
  // Optional project UI overlay (stub no-op unless moonsightc linked ui_package).
  @project_ui.register(app)
  let eng = @runtime.Engine::from_ir(
    ir,
    entry~,
    director=@std_commands.standard_registry(),
    app~,
  )
  let s = session.val
  s.engine = Some(eng)
  s.atlas = @render.GlyphAtlas::new()
  s.resources = @render.ResourceTable::new()
  s.frame = (FixedArray::make(0, 0.0) : FixedArray[Float])
  // Fresh audio queue for the new session; host commands write via global mixer.
  s.audio_queue = @audio.QueueBackend::new()
  install_session_audio()
  // Pre-intern common UI resources so JS can upload placeholders early.
  ignore(s.resources.intern(@render.ui_dialogue_box))
  ignore(s.resources.intern(@render.ui_nameplate))
  ignore(s.resources.intern(@render.ui_choice_row))
  ignore(s.resources.intern(@render.ui_menu_dim))
  ignore(s.resources.intern(@render.ui_button))
  ignore(s.resources.intern(@render.ui_button_focus))
  ignore(s.resources.intern("ui.button_hover"))
  ignore(s.resources.intern("ui.choice_row_focus"))
  ignore(s.resources.intern("ui.choice_row_hover"))
  ignore(s.resources.intern("ui.slider_track"))
  ignore(s.resources.intern("ui.slider_fill"))
  ignore(s.resources.intern("bg/demo"))
}

///|
/// Cold start: Title mode + push `title` when registered. Returns 0 ok, 1 no engine.
pub fn boot_title() -> Int {
  match session.val.engine {
    None => 1
    Some(eng) => {
      eng.boot_title()
      0
    }
  }
}

///|
/// Current prefs JSON (empty if no engine).
pub fn prefs_json() -> String {
  match session.val.engine {
    None => ""
    Some(eng) => eng.prefs_json()
  }
}

///|
/// Apply prefs JSON (0 ok, 1 error).
pub fn set_prefs_json(json : String) -> Int {
  match session.val.engine {
    None => 1
    Some(eng) => eng.set_prefs_json(json)
  }
}

///|
/// Configured save slot count.
pub fn save_slot_count() -> Int {
  match session.val.engine {
    None => 0
    Some(eng) => eng.ui.save_slots
  }
}

///|
/// Apply multi-slot capacity from host manifest (`save_slots`, clamp 1..20).
/// Returns 0 ok, 1 if no engine.
pub fn set_save_slots(n : Int) -> Int {
  match session.val.engine {
    None => 1
    Some(eng) => {
      eng.set_save_slots(n)
      0
    }
  }
}

///|
/// In-memory slot blob (empty string if empty/missing).
pub fn get_slot_json(slot : Int) -> String {
  match session.val.engine {
    None => ""
    Some(eng) =>
      match eng.get_slot_blob(slot) {
        None => ""
        Some(b) => b
      }
  }
}

///|
/// Seed / update in-memory slot blob (host localStorage mirror). 0 ok, 1 error.
pub fn set_slot_json(slot : Int, json : String) -> Int {
  match session.val.engine {
    None => 1
    Some(eng) => {
      eng.set_slot_blob(slot, json)
      0
    }
  }
}

///|
/// Pointer path: logical pixels, phase 0=move, 1=down, 2=up, 3=leave.
/// Returns hover_kind: 0 none, 1 button, 2 choice, 3 slider.
pub fn export_pointer(x : Float, y : Float, phase : Int) -> Int {
  let s = session.val
  match s.engine {
    None => 0
    Some(eng) => eng.pointer_event(x.to_double(), y.to_double(), phase~)
  }
}

///|
/// Wheel: logical x,y and vertical dy (dy>0 => reveal older content).
/// Returns hover_kind after the event (0 when no engine / no modal).
pub fn export_wheel(x : Float, y : Float, dy : Float) -> Int {
  match session.val.engine {
    None => 0
    Some(eng) => eng.wheel_event(x.to_double(), y.to_double(), dy.to_double())
  }
}

///|
/// Tick engine with intent/dt, pack draw list; returns pack length.
///
/// `intent_code` — see `docs/draw-list-pack.md`.
/// `dt_ms` — frame delta in milliseconds.
/// `skip_held` — non-zero while Ctrl is held (host maps hold → skip burst).
pub fn export_frame(intent_code : Int, dt_ms : Float, skip_held : Int) -> Int {
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
      eng.tick(intent, dt~, skip_held=skip_held != 0)
      let view = eng.view()
      // Phase 4 Task 4: paint only UiDrawOp from UiRuntime (no hard-coded dialogue).
      eng.sync_ui_bind()
      let canvas_w = s.layout.canvas_w.to_double()
      let canvas_h = s.layout.canvas_h.to_double()
      let bind = eng.ui.bind
      let ops : Array[@runtime.UiDrawOp] = if eng.ui.stack_depth() > 0 {
        eng.ui.paint_modal(canvas_w~, canvas_h~, bind~)
      } else if eng.ui.mode is @runtime.UiMode::Playing {
        eng.ui.paint_hud(canvas_w~, canvas_h~, bind~)
      } else {
        []
      }
      let dl = @render.build_draw_list_with_atlas(
        view,
        s.layout,
        s.atlas,
        ui_ops=ops,
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
///
/// `Engine::load` restores mixer BGM/volume/fade from the save audio block.
pub fn load_json(json : String) -> Int {
  let s = session.val
  match s.engine {
    None => 1
    Some(eng) =>
      try {
        // Engine::load restores save state and clears the modal stack → Playing.
        eng.load(json)
        0
      } catch {
        _ => 1
      }
  }
}

// ---------------------------------------------------------------------------
// Audio event drain for JS (QueueBackend behind the global mixer)
//
// kind codes: 0=PlayBgm, 1=StopBgm, 2=PlaySe, 3=SetBgmVolume
// ---------------------------------------------------------------------------

///|
pub fn audio_event_count() -> Int {
  session.val.audio_queue.len()
}

///|
/// Event kind at index: 0 PlayBgm, 1 StopBgm, 2 PlaySe, 3 SetBgmVolume, -1 OOB.
pub fn audio_event_kind(i : Int) -> Int {
  match session.val.audio_queue.get(i) {
    None => -1
    Some(PlayBgm(..)) => 0
    Some(StopBgm) => 1
    Some(PlaySe(..)) => 2
    Some(SetBgmVolume(..)) => 3
  }
}

///|
/// Resource id for PlayBgm / PlaySe (empty for StopBgm / SetBgmVolume / OOB).
pub fn audio_event_resource(i : Int) -> String {
  match session.val.audio_queue.get(i) {
    Some(PlayBgm(resource~, ..)) => resource
    Some(PlaySe(resource~, ..)) => resource
    _ => ""
  }
}

///|
/// 1 if BGM should loop, else 0.
pub fn audio_event_looped(i : Int) -> Int {
  match session.val.audio_queue.get(i) {
    Some(PlayBgm(looped~, ..)) => if looped { 1 } else { 0 }
    _ => 0
  }
}

///|
pub fn audio_event_volume(i : Int) -> Float {
  match session.val.audio_queue.get(i) {
    Some(PlayBgm(volume~, ..)) => Float::from_double(volume)
    Some(PlaySe(volume~, ..)) => Float::from_double(volume)
    Some(SetBgmVolume(volume~)) => Float::from_double(volume)
    _ => 0.0
  }
}

///|
/// Clear the drained event queue after JS has applied them.
pub fn audio_clear_events() -> Int {
  let n = session.val.audio_queue.len()
  session.val.audio_queue.clear()
  n
}

///|
/// Current logical BGM id (empty if none) — diagnostic / resume helpers.
pub fn audio_bgm() -> String {
  match @audio.global_mixer().bgm {
    None => ""
    Some(id) => id
  }
}

///|
/// Current logical SE id (empty if none).
pub fn audio_se() -> String {
  match @audio.global_mixer().se {
    None => ""
    Some(id) => id
  }
}

///|
/// SE sequence counter (increments on each play_se).
pub fn audio_se_seq() -> Int {
  @audio.global_mixer().se_seq
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
  install_session_audio()
  println("moonsight host_web ready")
}
