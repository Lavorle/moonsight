///|
/// Logical canvas width (design resolution).
pub let logical_width : Int = 1920

///|
/// Logical canvas height (design resolution).
pub let logical_height : Int = 1080

///|
/// Layer category in the theater stack (bottom → top for rendering order
/// within the same z band is still controlled by `LayerState.z`).
pub(all) enum LayerKind {
  Background
  Character
  Effect
  UI
  Overlay
} derive(Debug, Eq, ToJson, FromJson)

///|
/// One visible (or hidden) layer node keyed by logical `id`.
///
/// `resource` is a logical asset id (not a GPU handle).
pub(all) struct LayerState {
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
/// Current dialogue typewriter block on stage.
pub(all) struct TextBlock {
  speaker : String?
  full_text : String
  visible_chars : Int
  complete : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Active choice UI: option labels and optional user selection index.
pub(all) struct ChoiceState {
  options : Array[String]
  selected : Int?
} derive(Debug)

///|
/// Authoritative theater state: layers, text, choices, variables, scene name.
///
/// Renderer must only read snapshots; play logic mutates Stage via Director/VM.
pub(all) struct Stage {
  mut layers : Array[LayerState]
  mut text : TextBlock?
  mut choices : ChoiceState?
  mut vars : Map[String, Value]
  mut scene : String
  mut overlay_opacity : Double
  /// Fade target; engine eases `overlay_opacity` toward this each tick.
  mut fade_to : Double
  /// Seconds per unit opacity range for the current fade (0 = snap).
  mut fade_duration : Double
  /// Current BGM resource id (logical; Task 13 wires audio backend).
  mut bgm : String?
  /// Last SE resource id (logical).
  mut se : String?
  /// Set by `sys.save_hint` until consumed by save flow (Task 9).
  mut save_hint : Bool
} derive(Debug)

///|
/// Empty stage at logical origin with no text/choices and zero overlay.
pub fn Stage::new() -> Stage {
  {
    layers: [],
    text: None,
    choices: None,
    vars: {},
    scene: "",
    overlay_opacity: 0.0,
    fade_to: 0.0,
    fade_duration: 0.0,
    bgm: None,
    se: None,
    save_hint: false,
  }
}

///|
/// Show or replace a layer by `id`. Defaults: `x=0`, `y=0`, `opacity=1`, visible.
pub fn Stage::show_layer(
  self : Stage,
  id~ : String,
  layer~ : LayerKind,
  resource~ : String,
  z~ : Int,
  x? : Double = 0.0,
  y? : Double = 0.0,
  opacity? : Double = 1.0,
) -> Unit {
  let state : LayerState = {
    id,
    kind: layer,
    resource,
    z,
    x,
    y,
    opacity,
    visible: true,
  }
  for i in 0..<self.layers.length() {
    if self.layers[i].id == id {
      self.layers[i] = state
      return
    }
  }
  self.layers.push(state)
}

///|
/// Remove a layer by logical id (no-op if missing).
pub fn Stage::hide_layer(self : Stage, id~ : String) -> Unit {
  let kept : Array[LayerState] = []
  for layer in self.layers {
    if layer.id != id {
      kept.push(layer)
    }
  }
  self.layers = kept
}

///|
/// Copy of layers sorted by ascending `z` for stable render order.
pub fn Stage::snapshot_layers(self : Stage) -> Array[LayerState] {
  let out = self.layers.copy()
  out.sort_by((a, b) => a.z.compare(b.z))
  out
}

///|
/// Set a script variable.
pub fn Stage::set_var(self : Stage, name : String, value : Value) -> Unit {
  self.vars[name] = value
}

///|
/// Get a script variable; missing keys yield `Value::None_`.
pub fn Stage::get_var(self : Stage, name : String) -> Value {
  match self.vars.get(name) {
    Some(v) => v
    None => None_
  }
}

///|
/// Start a new dialogue block (resets typewriter state).
pub fn Stage::begin_text(self : Stage, speaker? : String) -> Unit {
  self.text = Some({ speaker, full_text: "", visible_chars: 0, complete: false })
}

///|
/// Append script text to the current block without revealing typewriter chars.
///
/// No-op if no text block is active (call `begin_text` first).
pub fn Stage::type_more(self : Stage, chunk : String) -> Unit {
  match self.text {
    None => ()
    Some(t) =>
      self.text = Some({
        speaker: t.speaker,
        full_text: t.full_text + chunk,
        visible_chars: t.visible_chars,
        complete: false,
      })
  }
}

///|
/// Reveal all characters and mark the block complete.
pub fn Stage::complete_text(self : Stage) -> Unit {
  match self.text {
    None => ()
    Some(t) =>
      self.text = Some({
        speaker: t.speaker,
        full_text: t.full_text,
        visible_chars: t.full_text.length(),
        complete: true,
      })
  }
}

///|
/// Reveal up to `n` additional typewriter characters (clamped to full text).
///
/// Marks the block complete when all characters are visible. No-op if no text
/// is active or the block is already complete.
pub fn Stage::reveal_chars(self : Stage, n : Int) -> Unit {
  if n <= 0 {
    return
  }
  match self.text {
    None => ()
    Some(t) => {
      if t.complete {
        return
      }
      let len = t.full_text.length()
      let next = t.visible_chars + n
      let visible = if next >= len { len } else { next }
      self.text = Some({
        speaker: t.speaker,
        full_text: t.full_text,
        visible_chars: visible,
        complete: visible >= len,
      })
    }
  }
}

///|
/// Present choice options; selection starts as `None`.
pub fn Stage::set_choices(self : Stage, options : Array[String]) -> Unit {
  self.choices = Some({ options: options.copy(), selected: None })
}

///|
/// Record the selected option index (does not clear the choice UI).
pub fn Stage::select_choice(self : Stage, index : Int) -> Unit {
  match self.choices {
    None => ()
    Some(c) =>
      self.choices = Some({ options: c.options, selected: Some(index) })
  }
}

///|
/// Clear active choices.
pub fn Stage::clear_choices(self : Stage) -> Unit {
  self.choices = None
}
