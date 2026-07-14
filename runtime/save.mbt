///|
/// Current save format version.
///
/// v2 adds explicit `wait`, `choices`, `choose_result_var`, and `auto`.
/// v3 adds layer tweens / `pending_hide`, plus `fade_to`, `fade_remaining`,
/// and `wait_remaining`.
/// v4 adds `scale` on layers (default 1.0).
/// v5 routes persistence through `EngineLogicalState` and persists dissolve
/// phase/total. Writers emit v5; loaders retain v2-v4 compatibility.
pub let save_format_version : Int = 5

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
/// Format v5: adds dissolve phase/total and uses the shared logical-state
/// projection rather than independently copying live Engine fields.
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
  /// Stable choice identities (additive v5 field; legacy saves default empty).
  choice_ids : Array[String]
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
  /// Dual-phase dissolve state (0=none, 1=out, 2=in).
  dissolve_phase : Int
  /// Full dual-phase dissolve duration.
  dissolve_total : Double
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
  InvalidLogicalState(message~ : String)
} derive(Eq, Debug)

///|
pub impl Show for SaveError with fn output(self : SaveError, logger : &Logger) -> Unit {
  match self {
    UnsupportedVersion(version~) =>
      logger.write_string(
        "unsupported save format_version \{version} (expected 2, 3, 4, or 5)",
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
    InvalidLogicalState(message~) =>
      logger.write_string("invalid logical state: \{message}")
  }
}

///|
pub fn is_supported_save_version(version : Int) -> Bool {
  version == 2 || version == 3 || version == 4 || version == 5
}

///|
/// Snapshot engine state to a JSON string.
///
/// `slot` is reserved for host storage keys (localStorage / file path); Phase 1
/// does not embed it in the blob. Consumes `stage.save_hint` (clears it).
/// Always writes format v5.
pub fn Engine::save(self : Engine, slot? : Int = 0) -> String {
  ignore(slot)
  self.stage.save_hint = false
  let state = EngineLogicalState::capture(self)
  SaveGame::from_logical_state(state, saved_at="").to_json().stringify()
}

///|
/// Persistence adapter from the sole aggregate logical snapshot.
fn SaveGame::from_logical_state(
  state : EngineLogicalState,
  saved_at~ : String,
) -> SaveGame {
  let choices = match state.stage.choices {
    Some(choice) => Some(choice.options.copy())
    None => None
  }
  let choice_ids = match state.stage.choices {
    Some(choice) => {
      let ids : Array[String] = []
      for id in choice.option_ids {
        match id {
          Some(value) => ids.push(value)
          None => ()
        }
      }
      if ids.length() == choice.options.length() {
        ids
      } else {
        []
      }
    }
    None => []
  }
  {
    format_version: save_format_version,
    module_id: state.module_id,
    scene: state.vm.scene,
    ip: state.vm.ip,
    call_stack: [],
    vars: state.stage.vars,
    layers: copy_layer_states(state.stage.layers),
    text: state.stage.text,
    overlay_opacity: state.stage.overlay_opacity,
    audio: state.audio,
    wait: state.vm.wait,
    choices,
    choice_ids,
    choose_result_var: state.vm.choose_result_var,
    auto: state.auto,
    fade_to: state.stage.fade_to,
    fade_remaining: state.stage.fade_remaining,
    wait_remaining: state.stage.wait_remaining,
    dissolve_phase: state.stage.dissolve_phase,
    dissolve_total: state.stage.dissolve_total,
    saved_at,
  }
}

///|
/// Restore engine state from a JSON save blob.
///
/// Accepts `format_version` 2 through 5; rejects others. Reloads scene ops for
/// the saved scene name and applies `ip`, vars, layers, text, overlay, audio,
/// wait, choices, and v3 fade/wait remaining fields. v3 layers without `scale`
/// default to 1.0; v4 is the native scale-aware shape.
pub fn Engine::load(self : Engine, blob : String) -> Unit raise SaveError {
  let game = parse_save_game(blob)
  validate_save_call_stack(game)
  self.restore_logical_state(game.to_logical_state(self))
  // Spec: load returns to narrative play with no residual modal stack.
  self.clear_screens_to_playing()
  // Session backlog is not part of save; drop lines from the prior playthrough.
  self.backlog.clear()
  self.backlog_last_key = ""
  self.rollback.clear()
  self.rollback_unavailable_reason = ""
}

///|
/// Parse and validate a save against this engine without mutating runtime state.
///
/// Hosts should use this for slot classification so version, identity, scene,
/// instruction-position, and continuation rules remain runtime-authoritative.
pub fn Engine::validate_save(
  self : Engine,
  blob : String,
) -> Unit raise SaveError {
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
/// v3-v5 share the same decode path; missing additive fields are injected.
pub fn parse_save_game(blob : String) -> SaveGame raise SaveError {
  let json = @json.parse(blob) catch {
    err => raise SaveError::InvalidJson(message=err.to_string())
  }
  let version = reject_unsupported_version(json)
  if version == 2 {
    let v2 : SaveGameV2 = @json.from_json(json) catch {
      err => raise SaveError::DecodeFailed(message=err.to_string())
    }
    return clamp_save_game_text(save_game_from_v2(v2))
  }
  // Old v3 blobs omit `saved_at` and/or layer `scale`; inject defaults.
  let json = ensure_saved_at_default(json)
  let json = ensure_layer_scale_default(json)
  let json = ensure_dissolve_defaults(json)
  let json = ensure_choice_ids_default(json)
  let game : SaveGame = @json.from_json(json) catch {
    err => raise SaveError::DecodeFailed(message=err.to_string())
  }
  if !is_supported_save_version(game.format_version) {
    raise SaveError::UnsupportedVersion(version=game.format_version)
  }
  clamp_save_game_text(game)
}

///|
/// Floor `TextBlock.visible_chars` to a grapheme boundary after decode.
/// No format bump: illegal mid-cluster values clamp down rather than reject.
fn clamp_save_game_text(game : SaveGame) -> SaveGame {
  match game.text {
    None => game
    Some(t) => {
      let visible = clamp_to_grapheme_boundary(t.full_text, t.visible_chars)
      if visible == t.visible_chars {
        game
      } else {
        { ..game, text: Some({ ..t, visible_chars: visible }) }
      }
    }
  }
}

///|
fn ensure_choice_ids_default(json : Json) -> Json {
  match json {
    Object(map) => {
      if map.get("choice_ids") is None {
        map["choice_ids"] = Json::array([])
      }
      json
    }
    _ => json
  }
}

///|
/// Ensure pre-v5 blobs receive the non-dissolving defaults.
fn ensure_dissolve_defaults(json : Json) -> Json {
  match json {
    Object(map) => {
      if map.get("dissolve_phase") is None {
        map["dissolve_phase"] = Json::number(0.0)
      }
      if map.get("dissolve_total") is None {
        map["dissolve_total"] = Json::number(0.0)
      }
      json
    }
    _ => json
  }
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
        Some(Array(layers)) =>
          for layer in layers {
            match layer {
              Object(lm) =>
                if lm.get("scale") is None {
                  lm["scale"] = Json::number(1.0)
                }
              _ => ()
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
    choice_ids: [],
    choose_result_var: v2.choose_result_var,
    auto: v2.auto,
    fade_to: 0.0,
    fade_remaining: 0.0,
    wait_remaining: 0.0,
    dissolve_phase: 0,
    dissolve_total: 0.0,
    saved_at: "",
  }
}

///|
fn validate_save_game(
  eng : Engine,
  game : SaveGame,
) -> PreparedEngineLogicalState raise SaveError {
  validate_save_call_stack(game)
  eng.prepare_logical_state(game.to_logical_state(eng))
}

///|
fn validate_save_call_stack(game : SaveGame) -> Unit raise SaveError {
  if !game.call_stack.is_empty() {
    raise SaveError::UnsupportedCallStack(depth=game.call_stack.length())
  }
}

///|
/// Compatibility adapter from a decoded save projection to the aggregate
/// logical state. UI and backlog remain session-owned and are cleared by load.
fn SaveGame::to_logical_state(
  self : SaveGame,
  eng : Engine,
) -> EngineLogicalState {
  let base = EngineLogicalState::capture(eng)
  let choices = match self.choices {
    Some(options) => {
      let option_ids = if self.choice_ids.length() == options.length() {
        self.choice_ids.map(id => Some(id))
      } else {
        options.map(_ => None)
      }
      Some({ options: options.copy(), option_ids, selected: None })
    }
    None => None
  }
  let fade_out = self.audio.bgm_fade_stop is Some(true)
  {
    ..base,
    module_id: self.module_id,
    vm: {
      scene: self.scene,
      ip: self.ip,
      stack: [],
      halted: self.wait is Halted,
      wait: self.wait,
      choose_result_var: self.choose_result_var,
    },
    stage: {
      scene: self.scene,
      vars: self.vars,
      layers: copy_layer_states(self.layers),
      text: self.text,
      choices,
      overlay_opacity: self.overlay_opacity,
      fade_to: self.fade_to,
      fade_remaining: self.fade_remaining,
      wait_remaining: self.wait_remaining,
      dissolve_phase: self.dissolve_phase,
      dissolve_total: self.dissolve_total,
      bgm: if fade_out {
        None
      } else {
        self.audio.bgm
      },
      se: self.audio.se,
    },
    audio: self.audio,
    auto: self.auto,
  }
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
    bgm_fade_remaining: if fade_rem > 0.0 {
      Some(fade_rem)
    } else {
      None
    },
    bgm_fade_stop: if fade_stop {
      Some(true)
    } else {
      None
    },
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
        m.fade_bgm_to(target, rem, stop~)
      }
    _ => ()
  }
}
