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
/// Animated layer property for in-flight linear tweens.
pub(all) enum TweenProp {
  X
  Y
  Opacity
} derive(Debug, Eq, ToJson, FromJson)

///|
/// One in-flight linear property animation (`from` is always current at start).
pub(all) struct LayerTween {
  prop : TweenProp
  to : Double
  remaining : Double
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
  tweens : Array[LayerTween]
  pending_hide : Bool
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
  /// Seconds left for timed @flow.wait; 0 means not in timed wait.
  mut wait_remaining : Double
  /// Wall-clock seconds left for overlay fade to `fade_to` (0 = done / snap).
  mut fade_remaining : Double
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
    wait_remaining: 0.0,
    fade_remaining: 0.0,
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
    tweens: [],
    pending_hide: false,
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
/// Render-order rank for `LayerKind` (Background bottom → Overlay top).
fn layer_kind_rank(kind : LayerKind) -> Int {
  match kind {
    Background => 0
    Character => 1
    Effect => 2
    UI => 3
    Overlay => 4
  }
}

///|
/// Return a copy of `layer` with one property set.
fn layer_with_prop(layer : LayerState, prop : TweenProp, value : Double) -> LayerState {
  match prop {
    X => {
      id: layer.id,
      kind: layer.kind,
      resource: layer.resource,
      z: layer.z,
      x: value,
      y: layer.y,
      opacity: layer.opacity,
      visible: layer.visible,
      tweens: layer.tweens,
      pending_hide: layer.pending_hide,
    }
    Y => {
      id: layer.id,
      kind: layer.kind,
      resource: layer.resource,
      z: layer.z,
      x: layer.x,
      y: value,
      opacity: layer.opacity,
      visible: layer.visible,
      tweens: layer.tweens,
      pending_hide: layer.pending_hide,
    }
    Opacity => {
      id: layer.id,
      kind: layer.kind,
      resource: layer.resource,
      z: layer.z,
      x: layer.x,
      y: layer.y,
      opacity: value,
      visible: layer.visible,
      tweens: layer.tweens,
      pending_hide: layer.pending_hide,
    }
  }
}

///|
/// Start (or replace) a linear property tween on a layer.
///
/// `duration <= 0` snaps the property immediately and clears any tween for that prop.
pub fn Stage::start_layer_tween(
  self : Stage,
  id~ : String,
  prop~ : TweenProp,
  to~ : Double,
  duration~ : Double,
) -> Unit {
  for i in 0..<self.layers.length() {
    if self.layers[i].id == id {
      let cur = self.layers[i]
      if duration <= 0.0 {
        let snapped = layer_with_prop(cur, prop, to)
        let kept : Array[LayerTween] = []
        for t in snapped.tweens {
          if t.prop != prop {
            kept.push(t)
          }
        }
        self.layers[i] = {
          id: snapped.id,
          kind: snapped.kind,
          resource: snapped.resource,
          z: snapped.z,
          x: snapped.x,
          y: snapped.y,
          opacity: snapped.opacity,
          visible: snapped.visible,
          tweens: kept,
          pending_hide: snapped.pending_hide,
        }
        return
      }
      let kept : Array[LayerTween] = []
      for t in cur.tweens {
        if t.prop != prop {
          kept.push(t)
        }
      }
      kept.push({ prop, to, remaining: duration })
      self.layers[i] = {
        id: cur.id,
        kind: cur.kind,
        resource: cur.resource,
        z: cur.z,
        x: cur.x,
        y: cur.y,
        opacity: cur.opacity,
        visible: cur.visible,
        tweens: kept,
        pending_hide: cur.pending_hide,
      }
      return
    }
  }
}

///|
/// Advance all layer tweens by `dt` seconds (linear toward `to`).
///
/// Removes layers with `pending_hide` once opacity has reached 0.
pub fn Stage::tick_layer_tweens(self : Stage, dt : Double) -> Unit {
  for i in 0..<self.layers.length() {
    let cur = self.layers[i]
    if cur.tweens.length() == 0 {
      continue
    }
    let mut x = cur.x
    let mut y = cur.y
    let mut opacity = cur.opacity
    let next_tweens : Array[LayerTween] = []
    for t in cur.tweens {
      let current = match t.prop {
        X => x
        Y => y
        Opacity => opacity
      }
      if t.remaining <= 0.0 || dt >= t.remaining {
        match t.prop {
          X => x = t.to
          Y => y = t.to
          Opacity => opacity = t.to
        }
      } else {
        let frac = dt / t.remaining
        let stepped = current + (t.to - current) * frac
        match t.prop {
          X => x = stepped
          Y => y = stepped
          Opacity => opacity = stepped
        }
        next_tweens.push({
          prop: t.prop,
          to: t.to,
          remaining: t.remaining - dt,
        })
      }
    }
    self.layers[i] = {
      id: cur.id,
      kind: cur.kind,
      resource: cur.resource,
      z: cur.z,
      x,
      y,
      opacity,
      visible: cur.visible,
      tweens: next_tweens,
      pending_hide: cur.pending_hide,
    }
  }
  let kept : Array[LayerState] = []
  for layer in self.layers {
    if layer.pending_hide && layer.opacity <= 0.0 {
      // Drop after fade-out completes.
    } else {
      kept.push(layer)
    }
  }
  self.layers = kept
}

///|
/// Hide a layer, optionally fading opacity to 0 over `duration` seconds.
///
/// `duration <= 0` removes immediately; otherwise sets `pending_hide` and
/// tweens opacity to 0 (removed when the tween finishes).
pub fn Stage::begin_hide_layer(
  self : Stage,
  id~ : String,
  duration~ : Double,
) -> Unit {
  if duration <= 0.0 {
    self.hide_layer(id~)
    return
  }
  for i in 0..<self.layers.length() {
    if self.layers[i].id == id {
      let cur = self.layers[i]
      self.layers[i] = {
        id: cur.id,
        kind: cur.kind,
        resource: cur.resource,
        z: cur.z,
        x: cur.x,
        y: cur.y,
        opacity: cur.opacity,
        visible: cur.visible,
        tweens: cur.tweens,
        pending_hide: true,
      }
      break
    }
  }
  self.start_layer_tween(id~, prop=Opacity, to=0.0, duration~)
}

///|
/// Copy of layers sorted by `(kind_rank, z, insert index)` for stable render order.
pub fn Stage::snapshot_layers(self : Stage) -> Array[LayerState] {
  let n = self.layers.length()
  let indexed : Array[(Int, LayerState)] = []
  for i in 0..<n {
    indexed.push((i, self.layers[i]))
  }
  indexed.sort_by((a, b) => {
    let (ia, la) = a
    let (ib, lb) = b
    let rk = layer_kind_rank(la.kind).compare(layer_kind_rank(lb.kind))
    if rk != 0 {
      rk
    } else {
      let rz = la.z.compare(lb.z)
      if rz != 0 {
        rz
      } else {
        ia.compare(ib)
      }
    }
  })
  let out : Array[LayerState] = []
  for pair in indexed {
    let (_, layer) = pair
    out.push(layer)
  }
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
