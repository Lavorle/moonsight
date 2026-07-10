///|
/// Current save format version (Phase 1 JSON).
pub let save_format_version : Int = 1

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
  }
  game.to_json().stringify()
}

///|
/// Restore engine state from a JSON save blob.
///
/// Rejects `format_version != 1`. Reloads scene ops for the saved scene name
/// and applies `ip`, vars, layers, text, overlay, and audio fields.
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
  eng.vm.ops = load_scene_ops(eng.vm.ir, game.scene)
  eng.vm.scene = game.scene
  eng.vm.ip = game.ip
  eng.vm.stack = []
  eng.vm.halted = false
  eng.vm.choose_result_var = None
  // Saves are typically taken at a player-facing wait; prefer Yield when text is up.
  eng.vm.wait = match game.text {
    Some(_) => Yield
    None => Running
  }
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
  eng.stage.choices = None
  eng.stage.save_hint = false
}
