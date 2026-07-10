///|
/// Current save format version.
///
/// v2 adds explicit `wait`, `choices`, `choose_result_var`, and `auto`.
/// v3 adds layer tweens / `pending_hide`, plus `fade_to`, `fade_remaining`,
/// and `wait_remaining`. Writers always emit v3; loaders accept v2 and v3.
pub let save_format_version : Int = 3

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
} derive(Eq, Debug)

///|
pub impl Show for SaveError with fn output(self : SaveError, logger : &Logger) -> Unit {
  match self {
    UnsupportedVersion(version~) =>
      logger.write_string(
        "unsupported save format_version \{version} (expected 2 or 3)",
      )
    InvalidJson(message~) =>
      logger.write_string("invalid save JSON: \{message}")
    DecodeFailed(message~) =>
      logger.write_string("failed to decode save game: \{message}")
  }
}

///|
fn supported_save_version(version : Int) -> Bool {
  version == 2 || version == 3
}

///|
/// Snapshot engine state to a JSON string.
///
/// `slot` is reserved for host storage keys (localStorage / file path); Phase 1
/// does not embed it in the blob. Consumes `stage.save_hint` (clears it).
/// Always writes format v3.
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
    module_id: "",
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
  }
  game.to_json().stringify()
}

///|
/// Restore engine state from a JSON save blob.
///
/// Accepts `format_version` 2 or 3; rejects others. Reloads scene ops for the
/// saved scene name and applies `ip`, vars, layers, text, overlay, audio,
/// wait, choices, and v3 fade/wait remaining fields.
pub fn Engine::load(self : Engine, blob : String) -> Unit raise SaveError {
  apply_save_game(self, parse_save_game(blob))
}

///|
/// Decode a `SaveGame` without applying it (for tests and host inspection).
///
/// Checks `format_version` on the raw JSON object before full decode so
/// unsupported versions fail with `UnsupportedVersion` even if other fields
/// would not decode under newer schemas. v2 blobs are upgraded to the live
/// `SaveGame` shape with defaulted tween / fade / wait fields.
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
  let game : SaveGame = @json.from_json(json) catch {
    err => raise SaveError::DecodeFailed(message=err.to_string())
  }
  if !supported_save_version(game.format_version) {
    raise SaveError::UnsupportedVersion(version=game.format_version)
  }
  game
}

///|
/// Returns accepted version, or raises if unsupported / unreadable.
fn reject_unsupported_version(json : Json) -> Int raise SaveError {
  match json {
    Object(map) =>
      match map.get("format_version") {
        Some(Number(n, ..)) => {
          let version = n.to_int()
          if !supported_save_version(version) {
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
  }
}

///|
fn apply_save_game(eng : Engine, game : SaveGame) -> Unit {
  match load_scene_ops(eng.vm.ir, game.scene) {
    Some(ops) => {
      eng.vm.ops = ops
      eng.vm.halted = game.wait is Halted
      eng.vm.last_error = None
    }
    None => {
      eng.vm.ops = []
      eng.vm.halted = true
      eng.vm.last_error = Some("unknown scene: \{game.scene}")
    }
  }
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
  eng.stage.bgm = game.audio.bgm
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
fn audio_logic_from_mixer(bgm : String?, se : String?) -> AudioLogicState {
  let m = @audio.global_mixer()
  let fade_to = m.bgm_fade_to
  let fade_rem = m.bgm_fade_remaining
  let fade_stop = m.bgm_fade_stop
  {
    bgm,
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
