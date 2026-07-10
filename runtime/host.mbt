///|
/// Resolved host call: name plus flattened runtime values.
///
/// Named args are encoded as `Str("#:name")` followed by the value; use
/// `split_host_args` to separate positional and named maps.
pub(all) struct HostCall {
  name : String
  args : Array[Value]
} derive(Debug, Eq)

///|
/// Split flattened host args: positional values + named map from `#:key` markers.
pub fn split_host_args(
  args : Array[Value],
) -> (Array[Value], Map[String, Value]) {
  let pos : Array[Value] = []
  let named : Map[String, Value] = {}
  let mut i = 0
  while i < args.length() {
    match args[i] {
      Str(s) =>
        if s.has_prefix("#:") && i + 1 < args.length() {
          let key = s[2:].to_owned()
          named[key] = args[i + 1]
          i = i + 2
        } else {
          pos.push(args[i])
          i = i + 1
        }
      _ => {
        pos.push(args[i])
        i = i + 1
      }
    }
  }
  (pos, named)
}

///|
/// Result of a host call.
pub(all) enum HostResult {
  Ok
  /// Host requests VM yield (e.g. after a wait command).
  Yield
  /// Host requests a scene switch; VM calls `jump_scene`.
  JumpScene(String)
  Error(String)
} derive(Debug, Eq)

///|
/// Built-in host operations (Task 7 minimum; full table in std_commands / Task 8).
pub(all) enum BuiltinHost {
  TextBegin
  TextType
  TextEnd
  LayerShow
  LayerHide
  LayerMove
  LayerSet
  VarSet
} derive(Debug, Eq)

///|
/// Handler registration entry for Director dispatch.
///
/// `Handler` lets packages such as `std_commands` register function
/// implementations without expanding `BuiltinHost`.
pub(all) enum HostHandler {
  Builtin(BuiltinHost)
  Handler((Stage, Array[Value]) -> HostResult)
} derive(Debug)

///|
/// Dispatch a built-in host op by dotted name.
pub fn dispatch_builtin(
  op : String,
  stage : Stage,
  args : Array[Value],
) -> HostResult {
  match op {
    "text.begin" => builtin_text_begin(stage, args)
    "text.type" => builtin_text_type(stage, args)
    "text.end" => builtin_text_end(stage, args)
    "layer.show" => builtin_layer_show(stage, args)
    "layer.hide" => builtin_layer_hide(stage, args)
    "layer.move" => builtin_layer_move(stage, args)
    "layer.set" => builtin_layer_set(stage, args)
    "var.set" => builtin_var_set(stage, args)
    "var.eq" => builtin_var_eq(stage, args)
    _ => Error("unknown host op: \{op}")
  }
}

///|
/// Dispatch by typed built-in tag.
pub fn dispatch_builtin_kind(
  kind : BuiltinHost,
  stage : Stage,
  args : Array[Value],
) -> HostResult {
  match kind {
    TextBegin => builtin_text_begin(stage, args)
    TextType => builtin_text_type(stage, args)
    TextEnd => builtin_text_end(stage, args)
    LayerShow => builtin_layer_show(stage, args)
    LayerHide => builtin_layer_hide(stage, args)
    LayerMove => builtin_layer_move(stage, args)
    LayerSet => builtin_layer_set(stage, args)
    VarSet => builtin_var_set(stage, args)
  }
}

///|
fn builtin_text_begin(stage : Stage, args : Array[Value]) -> HostResult {
  match args {
    [] | [None_] => {
      stage.begin_text()
      Ok
    }
    [Str(s), ..] => {
      stage.begin_text(speaker=s)
      Ok
    }
    _ => Error("text.begin: expected speaker Str or None_")
  }
}

///|
fn builtin_text_type(stage : Stage, args : Array[Value]) -> HostResult {
  match args {
    [Str(chunk), ..] => {
      stage.type_more(chunk)
      Ok
    }
    _ => Error("text.type: expected Str chunk")
  }
}

///|
/// `text.end` — finish authoring the dialogue block without forcing typewriter complete.
///
/// Leaves `complete=false` so the engine can reveal characters via
/// `tick_typewriter` and Advance complete-first.
fn builtin_text_end(stage : Stage, args : Array[Value]) -> HostResult {
  ignore(stage)
  ignore(args)
  Ok
}

///|
/// `var.eq dest lhs rhs` — set `dest` to `Bool(lhs == rhs)` (used by JumpIf lower).
fn builtin_var_eq(stage : Stage, args : Array[Value]) -> HostResult {
  match args {
    [Str(dest), lhs, rhs, ..] => {
      stage.set_var(dest, Bool(lhs == rhs))
      Ok
    }
    _ => Error("var.eq: expected dest Str, lhs, rhs")
  }
}

///|
/// Coerce Int/Float host args to Double.
pub fn value_as_double(v : Value) -> Double? {
  match v {
    Float(f) => Some(f)
    Int(i) => Some(i.to_double())
    _ => None
  }
}

///|
/// Coerce Int/Float host args to Int (Float truncates toward zero).
pub fn value_as_int(v : Value) -> Int? {
  match v {
    Int(i) => Some(i)
    Float(f) => Some(f.to_int())
    _ => None
  }
}

///|
/// Parse `LayerKind` from host value (case-insensitive Str).
fn parse_kind(v : Value) -> LayerKind? {
  match v {
    Str(s) => {
      let k = s.to_lower()
      match k {
        "background" => Some(Background)
        "character" => Some(Character)
        "effect" => Some(Effect)
        "ui" => Some(UI)
        "overlay" => Some(Overlay)
        _ => None
      }
    }
    _ => None
  }
}

///|
fn named_double(named : Map[String, Value], key : String) -> Double? {
  match named.get(key) {
    Some(v) => value_as_double(v)
    None => None
  }
}

///|
fn named_int(named : Map[String, Value], key : String) -> Int? {
  match named.get(key) {
    Some(v) => value_as_int(v)
    None => None
  }
}

///|
fn find_layer_index(stage : Stage, id : String) -> Int? {
  for i in 0..<stage.layers.length() {
    if stage.layers[i].id == id {
      return Some(i)
    }
  }
  None
}

///|
/// `layer.show id resource [z] [x] [y] [opacity]` plus named kind/duration/etc.
/// Kind defaults to **Character**. New + duration>0: opacity starts at 0.
fn builtin_layer_show(stage : Stage, args : Array[Value]) -> HostResult {
  let (pos, named) = split_host_args(args)
  let id = match pos {
    [Str(s), ..] => s
    _ => return Error("layer.show: expected id Str and resource Str")
  }
  let resource = match pos {
    [_, Str(s), ..] => s
    [_, ..] => return Error("layer.show: expected id Str and resource Str")
    _ => ""
  }
  let kind = match named.get("kind") {
    Some(v) =>
      match parse_kind(v) {
        Some(k) => k
        None => return Error("layer.show: invalid kind")
      }
    None => Character
  }
  let z_opt : Int? = match named_int(named, "z") {
    Some(n) => Some(n)
    None =>
      match pos {
        [_, _, z0, ..] => value_as_int(z0)
        _ => None
      }
  }
  let x_opt : Double? = match named_double(named, "x") {
    Some(n) => Some(n)
    None =>
      match pos {
        [_, _, _, x0, ..] => value_as_double(x0)
        _ => None
      }
  }
  let y_opt : Double? = match named_double(named, "y") {
    Some(n) => Some(n)
    None =>
      match pos {
        [_, _, _, _, y0, ..] => value_as_double(y0)
        _ => None
      }
  }
  let opacity_opt : Double? = match named_double(named, "opacity") {
    Some(n) => Some(n)
    None =>
      match pos {
        [_, _, _, _, _, o, ..] => value_as_double(o)
        _ => None
      }
  }
  let duration = match named_double(named, "duration") {
    Some(d) => d
    None => 0.0
  }
  let z = match z_opt {
    Some(n) => n
    None => 0
  }
  let x = match x_opt {
    Some(n) => n
    None => 0.0
  }
  let y = match y_opt {
    Some(n) => n
    None => 0.0
  }
  let opacity_target = match opacity_opt {
    Some(n) => n
    None => 1.0
  }
  match find_layer_index(stage, id) {
    Some(i) => {
      let cur = stage.layers[i]
      let new_z = match z_opt {
        Some(n) => n
        None => cur.z
      }
      stage.layers[i] = {
        id: cur.id,
        kind,
        resource,
        z: new_z,
        x: cur.x,
        y: cur.y,
        opacity: cur.opacity,
        visible: true,
        tweens: cur.tweens,
        pending_hide: false,
      }
      match x_opt {
        Some(xv) => stage.start_layer_tween(id~, prop=X, to=xv, duration~)
        None => ()
      }
      match y_opt {
        Some(yv) => stage.start_layer_tween(id~, prop=Y, to=yv, duration~)
        None => ()
      }
      match opacity_opt {
        Some(ov) => stage.start_layer_tween(id~, prop=Opacity, to=ov, duration~)
        None => ()
      }
      Ok
    }
    None => {
      if duration > 0.0 {
        stage.show_layer(
          id~,
          layer=kind,
          resource~,
          z~,
          x~,
          y~,
          opacity=0.0,
        )
        stage.start_layer_tween(
          id~,
          prop=Opacity,
          to=opacity_target,
          duration~,
        )
      } else {
        stage.show_layer(
          id~,
          layer=kind,
          resource~,
          z~,
          x~,
          y~,
          opacity=opacity_target,
        )
      }
      Ok
    }
  }
}

///|
fn builtin_layer_hide(stage : Stage, args : Array[Value]) -> HostResult {
  let (pos, named) = split_host_args(args)
  match pos {
    [Str(id), ..] => {
      let duration = match named_double(named, "duration") {
        Some(d) => d
        None => 0.0
      }
      stage.begin_hide_layer(id~, duration~)
      Ok
    }
    _ => Error("layer.hide: expected id Str")
  }
}

///|
/// `layer.move id x y` — optional `#:duration` tweens position (no-op if missing).
fn builtin_layer_move(stage : Stage, args : Array[Value]) -> HostResult {
  let (pos, named) = split_host_args(args)
  let coords : (String, Double, Double)? = match pos {
    [Str(id), x, y, ..] =>
      match (value_as_double(x), value_as_double(y)) {
        (Some(xd), Some(yd)) => Some((id, xd, yd))
        _ => None
      }
    _ => None
  }
  match coords {
    None => Error("layer.move: expected id Str and x/y numbers")
    Some((id, x, y)) => {
      let duration = match named_double(named, "duration") {
        Some(d) => d
        None => 0.0
      }
      match find_layer_index(stage, id) {
        None => Ok
        Some(_) => {
          stage.start_layer_tween(id~, prop=X, to=x, duration~)
          stage.start_layer_tween(id~, prop=Y, to=y, duration~)
          Ok
        }
      }
    }
  }
}

///|
/// `layer.set id` with named x/y/opacity/duration. Missing id → Error.
fn builtin_layer_set(stage : Stage, args : Array[Value]) -> HostResult {
  let (pos, named) = split_host_args(args)
  let id = match pos {
    [Str(s), ..] => s
    _ => return Error("layer.set: expected id Str")
  }
  match find_layer_index(stage, id) {
    None => Error("layer.set: missing layer id '\{id}'")
    Some(_) => {
      let duration = match named_double(named, "duration") {
        Some(d) => d
        None => 0.0
      }
      match named_double(named, "x") {
        Some(xv) => stage.start_layer_tween(id~, prop=X, to=xv, duration~)
        None => ()
      }
      match named_double(named, "y") {
        Some(yv) => stage.start_layer_tween(id~, prop=Y, to=yv, duration~)
        None => ()
      }
      match named_double(named, "opacity") {
        Some(ov) => stage.start_layer_tween(id~, prop=Opacity, to=ov, duration~)
        None => ()
      }
      Ok
    }
  }
}

///|
fn builtin_var_set(stage : Stage, args : Array[Value]) -> HostResult {
  match args {
    [Str(name), value, ..] => {
      stage.set_var(name, value)
      Ok
    }
    _ => Error("var.set: expected name Str and value")
  }
}
