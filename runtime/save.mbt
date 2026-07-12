///|
/// Current save format version.
///
/// v2 adds explicit `wait`, `choices`, `choose_result_var`, and `auto`.
/// v3 adds layer tweens / `pending_hide`, plus `fade_to`, `fade_remaining`,
/// and `wait_remaining`.
/// v4 adds `scale` on layers (default 1.0). Writers always emit v4; loaders
/// accept v2, v3, and v4. Old v3 blobs without `scale` inject 1.0 on load.
pub let save_format_version : Int = 4

///|
/// Call-stack frame reserved for nested scene calls.
///
/// Phase 1 VM does not push frames yet; saves always store an empty stack.
pub(all) struct StackFrame {
  scene : String
  ip : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Logical audio snapshot (Stage bgm/se ids + mixer volume).
///
/// `bgm_volume` is optional in JSON so legacy `"audio":{}` blobs still decode;
/// missing volume is treated as 1.0 on load. Optional fade mid-state fields
/// restore in-flight fades when present.
pub(all) struct AudioLogicState {
  bgm : String?
  se : String?
  /// Logical BGM gain (None = legacy / default 1.0).
  bgm_volume : Double?
  /// Fade target when a fade was in progress at save time.
  bgm_fade_to : Double?
  /// Seconds left on BGM fade (None/0 = not fading).
  bgm_fade_remaining : Double?
  /// When true, stop BGM after the restored fade completes.
  bgm_fade_stop : Bool?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Human-debuggable save payload (JSON via `ToJson`/`FromJson`).
///
/// Format v3: full `LayerState` (tweens + pending_hide) and timed fade/wait fields.
/// Format v4: adds `scale` on each layer (missing on old v3 → default 1.0).
/// Additive `saved_at` (ISO timestamp or empty) is tolerated when missing on load.
pub(all) struct SaveGame {
  format_version : Int
  module_id : String
  scene : String
  ip : Int
  call_stack : Array[StackFrame]
  vars : Map[String, Value]
  layers : Array[LayerState]
  text : TextBlock?
  overlay_opacity : Double
  audio : AudioLogicState
  /// VM wait kind at save time (Yield / Choose / …).
  wait : WaitKind
  /// Active choice labels when `wait` is Choose (None when no choice UI).
  choices : Array[String]?
  /// Variable that receives the choice index while waiting Choose.
  choose_result_var : String?
  /// Auto-advance flag.
  auto : Bool
  /// Overlay fade target opacity.
  fade_to : Double
  /// Wall-clock seconds left for overlay fade (0 = done / snap).
  fade_remaining : Double
  /// Seconds left for timed `@flow.wait` (0 = not in timed wait).
  wait_remaining : Double
  /// Host-supplied save timestamp (ISO-8601 or empty when no clock FFI).
  saved_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// v2 layer snapshot (no tweens / pending_hide).
struct LayerStateV2 {
  id : String
  kind : LayerKind
  resource : String
  z : Int
  x : Double
  y : Double
  opacity : Double
  visible : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// v2 save payload (pre-tween fields). Used only for loading old blobs.
struct SaveGameV2 {
  format_version : Int
  module_id : String
  scene : String
  ip : Int
  call_stack : Array[StackFrame]
  vars : Map[String, Value]
  layers : Array[LayerStateV2]
  text : TextBlock?
  overlay_opacity : Double
  audio : AudioLogicState
  wait : WaitKind
  choices : Array[String]?
  choose_result_var : String?
  auto : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Errors from parsing or applying a save blob.
pub(all) suberror SaveError {
  UnsupportedVersion(version~ : Int)
  InvalidJson(message~ : String)
  DecodeFailed(message~ : String)
  ModuleMismatch(expected~ : String, found~ : String)
  UnknownScene(scene~ : String)
  InvalidInstructionPointer(scene~ : String, ip~ : Int, max_ip~ : Int)
  UnsupportedCallStack(depth~ : Int)
  InvalidContinuation(message~ : String)
} derive(Eq, Debug)

///|
pub impl Show for SaveError with fn output(self : SaveError, logger : &Logger) -> Unit {
  match self {
    UnsupportedVersion(version~) =>
      logger.write_string(
        "unsupported save format_version \{version} (expected 2, 3, or 4)",
      )
    InvalidJson(message~) =>
      logger.write_string("invalid save JSON: \{message}")
    DecodeFailed(message~) =>
      logger.write_string("failed to decode save game: \{message}")
    ModuleMismatch(expected~, found~) =>
      logger.write_string(
        "save module_id mismatch: expected \{expected}, found \{found}",
      )
    UnknownScene(scene~) =>
      logger.write_string("save references unknown scene: \{scene}")
    InvalidInstructionPointer(scene~, ip~, max_ip~) =>
      logger.write_string(
        "save instruction pointer \{ip} is invalid for scene \{scene} (expected 0..\{max_ip})",
      )
    UnsupportedCallStack(depth~) =>
      logger.write_string(
        "save call_stack depth \{depth} is unsupported by this runtime",
      )
    InvalidContinuation(message~) =>
      logger.write_string("invalid save continuation: \{message}")
  }
}

///|
pub fn is_supported_save_version(version : Int) -> Bool {
  version == 2 || version == 3 || version == 4
}

///|
/// Snapshot engine state to a JSON string.
///
/// `slot` is reserved for host storage keys (localStorage / file path); Phase 1
/// does not embed it in the blob. Consumes `stage.save_hint` (clears it).
/// Always writes format v4.
pub fn Engine::save(self : Engine, slot? : Int = 0) -> String {
  ignore(slot)
  self.stage.save_hint = false
  let vars : Map[String, Value] = {}
  for k, v in self.stage.vars {
    vars[k] = v
  }
  let choices : Array[String]? = match self.stage.choices {
    None => None
    Some(c) => Some(c.options.copy())
  }
  let game : SaveGame = {
    format_version: save_format_version,
    module_id: self.module_id,
    scene: self.vm.scene,
    ip: self.vm.ip,
    call_stack: [],
    vars,
    layers: self.stage.layers.copy(),
    text: self.stage.text,
    overlay_opacity: self.stage.overlay_opacity,
    audio: audio_logic_from_mixer(self.stage.bgm, self.stage.se),
    wait: self.vm.wait,
    choices,
    choose_result_var: self.vm.choose_result_var,
    auto: self.auto,
    fade_to: self.stage.fade_to,
    fade_remaining: self.stage.fade_remaining,
    wait_remaining: self.stage.wait_remaining,
    // No wall-clock FFI in pure runtime; host may patch `saved_at` if needed.
    saved_at: "",
  }
  game.to_json().stringify()
}

///|
/// Restore engine state from a JSON save blob.
///
/// Accepts `format_version` 2, 3, or 4; rejects others. Reloads scene ops for
/// the saved scene name and applies `ip`, vars, layers, text, overlay, audio,
/// wait, choices, and v3 fade/wait remaining fields. v3 layers without `scale`
/// default to 1.0; v4 is the native scale-aware shape.
pub fn Engine::load(self : Engine, blob : String) -> Unit raise SaveError {
  let game = parse_save_game(blob)
  let ops = validate_save_game(self, game)
  apply_save_game(self, game, ops)
  // Spec: load returns to narrative play with no residual modal stack.
  self.clear_screens_to_playing()
  // Session backlog is not part of save; drop lines from the prior playthrough.
  self.backlog.clear()
  self.backlog_last_key = ""
  // Prefs are not in the save blob; re-apply current gains after mixer restore.
  self.sync_mixer_prefs()
}

///|
/// Parse and validate a save against this engine without mutating runtime state.
///
/// Hosts should use this for slot classification so version, identity, scene,
/// instruction-position, and continuation rules remain runtime-authoritative.
pub fn Engine::validate_save(self : Engine, blob : String) -> Unit raise SaveError {
  let game = parse_save_game(blob)
  ignore(validate_save_game(self, game))
}

///|
/// Decode a `SaveGame` without applying it (for tests and host inspection).
///
/// Checks `format_version` on the raw JSON object before full decode so
/// unsupported versions fail with `UnsupportedVersion` even if other fields
/// would not decode under newer schemas. v2 blobs are upgraded to the live
/// `SaveGame` shape with defaulted tween / fade / wait / scale fields.
/// v3/v4 share the same decode path; missing additive fields are injected.
pub fn parse_save_game(blob : String) -> SaveGame raise SaveError {
  let json = @json.parse(blob) catch {
    err => raise SaveError::InvalidJson(message=err.to_string())
  }
  let version = reject_unsupported_version(json)
  if version == 2 {
    let v2 : SaveGameV2 = @json.from_json(json) catch {
      err => raise SaveError::DecodeFailed(message=err.to_string())
    }
    return save_game_from_v2(v2)
  }
  // Old v3 blobs omit `saved_at` and/or layer `scale`; inject defaults.
  let json = ensure_saved_at_default(json)
  let json = ensure_layer_scale_default(json)
  let game : SaveGame = @json.from_json(json) catch {
    err => raise SaveError::DecodeFailed(message=err.to_string())
  }
  if !is_supported_save_version(game.format_version) {
    raise SaveError::UnsupportedVersion(version=game.format_version)
  }
  game
}

///|
/// Ensure `saved_at` is present (default `""`) for additive load compatibility.
fn ensure_saved_at_default(json : Json) -> Json {
  match json {
    Object(map) => {
      if map.get("saved_at") is None {
        map["saved_at"] = Json::string("")
      }
      json
    }
    _ => json
  }
}

///|
/// Ensure each layer has `scale` (default `1.0`) so pre-v4 / old v3 blobs decode.
fn ensure_layer_scale_default(json : Json) -> Json {
  match json {
    Object(map) => {
      match map.get("layers") {
        Some(Array(layers)) => {
          for layer in layers {
            match layer {
              Object(lm) =>
                if lm.get("scale") is None {
                  lm["scale"] = Json::number(1.0)
                }
              _ => ()
            }
          }
        }
        _ => ()
      }
      json
    }
    _ => json
  }
}

///|
/// UI label for save slot `i`.
///
/// - empty: `"Slot {i} (empty)"`
/// - occupied with `saved_at`: `"Slot {i} · {saved_at}"`
/// - occupied without timestamp: `"Slot {i} · saved"`
pub fn slot_label(i : Int, saved : SaveGame?) -> String {
  match saved {
    None => "Slot \{i} (empty)"
    Some(game) =>
      if game.saved_at == "" {
        "Slot \{i} · saved"
      } else {
        "Slot \{i} · \{game.saved_at}"
      }
  }
}

///|
/// Returns accepted version, or raises if unsupported / unreadable.
fn reject_unsupported_version(json : Json) -> Int raise SaveError {
  match json {
    Object(map) =>
      match map.get("format_version") {
        Some(Number(n, ..)) => {
          let version = n.to_int()
          if !is_supported_save_version(version) {
            raise SaveError::UnsupportedVersion(version~)
          }
          version
        }
        _ =>
          // Missing/non-numeric version: let full FromJson surface DecodeFailed.
          save_format_version
      }
    _ => save_format_version
  }
}

///|
fn layer_state_from_v2(layer : LayerStateV2) -> LayerState {
  {
    id: layer.id,
    kind: layer.kind,
    resource: layer.resource,
    z: layer.z,
    x: layer.x,
    y: layer.y,
    opacity: layer.opacity,
    scale: 1.0,
    visible: layer.visible,
    tweens: [],
    pending_hide: false,
  }
}

///|
fn save_game_from_v2(v2 : SaveGameV2) -> SaveGame {
  let layers : Array[LayerState] = []
  for layer in v2.layers {
    layers.push(layer_state_from_v2(layer))
  }
  {
    format_version: v2.format_version,
    module_id: v2.module_id,
    scene: v2.scene,
    ip: v2.ip,
    call_stack: v2.call_stack,
    vars: v2.vars,
    layers,
    text: v2.text,
    overlay_opacity: v2.overlay_opacity,
    audio: v2.audio,
    wait: v2.wait,
    choices: v2.choices,
    choose_result_var: v2.choose_result_var,
    auto: v2.auto,
    fade_to: 0.0,
    fade_remaining: 0.0,
    wait_remaining: 0.0,
    saved_at: "",
  }
}

///|
fn validate_save_game(
  eng : Engine,
  game : SaveGame,
) -> Array[@script.IrOp] raise SaveError {
  // Empty module_id is the legacy v2-v4 compatibility case. Once a save is
  // scoped, it must match the runtime identity exactly; an unconfigured runtime
  // therefore cannot silently load another project's scoped save.
  if game.module_id != "" && game.module_id != eng.module_id {
    raise SaveError::ModuleMismatch(
      expected=eng.module_id,
      found=game.module_id,
    )
  }
  if !game.call_stack.is_empty() {
    raise SaveError::UnsupportedCallStack(depth=game.call_stack.length())
  }
  let ops = match load_scene_ops(eng.vm.ir, game.scene) {
    Some(ops) => ops
    None => raise SaveError::UnknownScene(scene=game.scene)
  }
  let max_ip = ops.length()
  if game.ip < 0 || game.ip > max_ip {
    raise SaveError::InvalidInstructionPointer(
      scene=game.scene,
      ip=game.ip,
      max_ip~,
    )
  }
  match game.wait {
    Choose =>
      if game.choices is None || game.choose_result_var is None {
        raise SaveError::InvalidContinuation(
          message="Choose requires choices and choose_result_var",
        )
      }
    _ =>
      if game.choices is Some(_) || game.choose_result_var is Some(_) {
        raise SaveError::InvalidContinuation(
          message="non-Choose wait cannot carry choice state",
        )
      }
  }
  ops
}

///|
fn apply_save_game(
  eng : Engine,
  game : SaveGame,
  ops : Array[@script.IrOp],
) -> Unit {
  eng.vm.ops = ops
  eng.vm.halted = game.wait is Halted
  eng.vm.last_error = None
  eng.vm.scene = game.scene
  eng.vm.ip = game.ip
  eng.vm.stack = []
  eng.vm.choose_result_var = game.choose_result_var
  eng.vm.wait = game.wait
  eng.auto = game.auto
  eng.stage.scene = game.scene
  let vars : Map[String, Value] = {}
  for k, v in game.vars {
    vars[k] = v
  }
  eng.stage.vars = vars
  eng.stage.layers = game.layers.copy()
  eng.stage.text = game.text
  eng.stage.overlay_opacity = game.overlay_opacity
  eng.stage.fade_to = game.fade_to
  eng.stage.fade_remaining = game.fade_remaining
  eng.stage.wait_remaining = game.wait_remaining
  // Dual-phase dissolve is runtime-only (not in save format). Always hard-clear
  // so a mid-dissolve playthrough cannot leak phase into the loaded session;
  // fade_* fields from the blob still apply as a simple single-phase fade.
  eng.stage.dissolve_phase = 0
  eng.stage.dissolve_total = 0.0
  // During fade-out, stage.bgm is None while mixer still holds the track id.
  // Keep that split after load so a later save does not re-persist phantom BGM.
  let fade_out = match game.audio.bgm_fade_stop {
    Some(true) => true
    _ => false
  }
  eng.stage.bgm = if fade_out { None } else { game.audio.bgm }
  eng.stage.se = game.audio.se
  restore_mixer_from_audio(game.audio)
  match game.choices {
    Some(opts) => eng.stage.set_choices(opts)
    None => eng.stage.clear_choices()
  }
  eng.stage.save_hint = false
}

///|
/// Snapshot Stage ids + live mixer volume / fade for the save blob.
///
/// During a fade-out stop, Stage clears `bgm` immediately while the mixer still
/// holds the track. Prefer mixer identity so load can restore an audible fade.
fn audio_logic_from_mixer(bgm : String?, se : String?) -> AudioLogicState {
  let m = @audio.global_mixer()
  let fade_to = m.bgm_fade_to
  let fade_rem = m.bgm_fade_remaining
  let fade_stop = m.bgm_fade_stop
  let saved_bgm = if fade_stop {
    match m.bgm {
      Some(_) as id => id
      None => bgm
    }
  } else {
    bgm
  }
  {
    bgm: saved_bgm,
    se,
    bgm_volume: Some(m.bgm_volume),
    bgm_fade_to: fade_to,
    bgm_fade_remaining: if fade_rem > 0.0 { Some(fade_rem) } else { None },
    bgm_fade_stop: if fade_stop { Some(true) } else { None },
  }
}

///|
/// Restore logical mixer volume (and optional mid-fade) after Stage ids apply.
fn restore_mixer_from_audio(audio : AudioLogicState) -> Unit {
  let vol = match audio.bgm_volume {
    Some(v) => v
    None => 1.0
  }
  let m = @audio.global_mixer()
  m.apply_logic(audio.bgm, audio.se, volume=vol)
  match (audio.bgm_fade_to, audio.bgm_fade_remaining) {
    (Some(target), Some(rem)) =>
      if rem > 0.0 {
        let stop = match audio.bgm_fade_stop {
          Some(true) => true
          _ => false
        }
        m.fade_bgm_to(target, rem, stop=stop)
      }
    _ => ()
  }
}
