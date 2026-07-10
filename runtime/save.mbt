///|
/// Current save format version (Phase 1 JSON).
///
/// v2 adds explicit `wait`, `choices`, `choose_result_var`, and `auto`.
pub let save_format_version : Int = 2

///|
/// Call-stack frame reserved for nested scene calls.
///
/// Phase 1 VM does not push frames yet; saves always store an empty stack.
pub(all) struct StackFrame {
  scene : String
  ip : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Logical audio snapshot (mirrors Stage bgm/se until audio package owns state).
pub(all) struct AudioLogicState {
  bgm : String?
  se : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Human-debuggable Phase 1 save payload (JSON via `ToJson`/`FromJson`).
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
        "unsupported save format_version \{version} (expected \{save_format_version})",
      )
    InvalidJson(message~) =>
      logger.write_string("invalid save JSON: \{message}")
    DecodeFailed(message~) =>
      logger.write_string("failed to decode save game: \{message}")
  }
}

///|
/// Snapshot engine state to a JSON string.
///
/// `slot` is reserved for host storage keys (localStorage / file path); Phase 1
/// does not embed it in the blob. Consumes `stage.save_hint` (clears it).
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
    audio: { bgm: self.stage.bgm, se: self.stage.se },
    wait: self.vm.wait,
    choices,
    choose_result_var: self.vm.choose_result_var,
    auto: self.auto,
  }
  game.to_json().stringify()
}

///|
/// Restore engine state from a JSON save blob.
///
/// Rejects unsupported `format_version`. Reloads scene ops for the saved scene
/// name and applies `ip`, vars, layers, text, overlay, audio, wait, and choices.
pub fn Engine::load(self : Engine, blob : String) -> Unit raise SaveError {
  apply_save_game(self, parse_save_game(blob))
}

///|
/// Decode a `SaveGame` without applying it (for tests and host inspection).
///
/// Checks `format_version` on the raw JSON object before full decode so
/// unsupported versions fail with `UnsupportedVersion` even if other fields
/// would not decode under v1 schemas.
pub fn parse_save_game(blob : String) -> SaveGame raise SaveError {
  let json = @json.parse(blob) catch {
    err => raise SaveError::InvalidJson(message=err.to_string())
  }
  reject_unsupported_version(json)
  let game : SaveGame = @json.from_json(json) catch {
    err => raise SaveError::DecodeFailed(message=err.to_string())
  }
  if game.format_version != save_format_version {
    raise SaveError::UnsupportedVersion(version=game.format_version)
  }
  game
}

///|
fn reject_unsupported_version(json : Json) -> Unit raise SaveError {
  match json {
    Object(map) =>
      match map.get("format_version") {
        Some(Number(n, ..)) => {
          let version = n.to_int()
          if version != save_format_version {
            raise SaveError::UnsupportedVersion(version~)
          }
        }
        _ => ()
      }
    _ => ()
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
  eng.stage.bgm = game.audio.bgm
  eng.stage.se = game.audio.se
  match game.choices {
    Some(opts) => eng.stage.set_choices(opts)
    None => eng.stage.clear_choices()
  }
  eng.stage.save_hint = false
}
