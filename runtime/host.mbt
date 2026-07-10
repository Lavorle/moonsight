///|
/// Resolved host call: name plus runtime values (named arg labels already dropped).
pub(all) struct HostCall {
  name : String
  args : Array[Value]
} derive(Debug, Eq)

///|
/// Result of a host call.
pub(all) enum HostResult {
  Ok
  /// Host requests VM yield (e.g. after a wait command).
  Yield
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
  VarSet
} derive(Debug, Eq)

///|
/// Handler registration entry for Director dispatch.
pub(all) enum HostHandler {
  Builtin(BuiltinHost)
} derive(Debug, Eq)

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
    "var.set" => builtin_var_set(stage, args)
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
fn builtin_text_end(stage : Stage, args : Array[Value]) -> HostResult {
  ignore(args)
  stage.complete_text()
  Ok
}

///|
/// `layer.show id resource [z] [x] [y] [opacity]`
/// Kind defaults to Background; z defaults to 0.
fn builtin_layer_show(stage : Stage, args : Array[Value]) -> HostResult {
  match args {
    [Str(id), Str(resource), .. rest] => {
      let z = match rest {
        [Int(z0), ..] => z0
        _ => 0
      }
      let x = match rest {
        [_, Float(x0), ..] => x0
        _ => 0.0
      }
      let y = match rest {
        [_, _, Float(y0), ..] => y0
        _ => 0.0
      }
      let opacity = match rest {
        [_, _, _, Float(o), ..] => o
        _ => 1.0
      }
      stage.show_layer(id~, layer=Background, resource~, z~, x~, y~, opacity~)
      Ok
    }
    [Str(id)] => {
      stage.show_layer(id~, layer=Background, resource="", z=0)
      Ok
    }
    _ => Error("layer.show: expected id Str and resource Str")
  }
}

///|
fn builtin_layer_hide(stage : Stage, args : Array[Value]) -> HostResult {
  match args {
    [Str(id), ..] => {
      stage.hide_layer(id~)
      Ok
    }
    _ => Error("layer.hide: expected id Str")
  }
}

///|
/// `layer.move id x y` — update position of an existing layer (no-op if missing).
fn builtin_layer_move(stage : Stage, args : Array[Value]) -> HostResult {
  let coords : (String, Double, Double)? = match args {
    [Str(id), Float(x), Float(y), ..] => Some((id, x, y))
    [Str(id), Int(xi), Int(yi), ..] =>
      Some((id, xi.to_double(), yi.to_double()))
    [Str(id), Float(x), Int(yi), ..] => Some((id, x, yi.to_double()))
    [Str(id), Int(xi), Float(y), ..] => Some((id, xi.to_double(), y))
    _ => None
  }
  match coords {
    None => Error("layer.move: expected id Str and x/y numbers")
    Some((id, x, y)) => {
      for i in 0..<stage.layers.length() {
        if stage.layers[i].id == id {
          let cur = stage.layers[i]
          stage.layers[i] = {
            id: cur.id,
            kind: cur.kind,
            resource: cur.resource,
            z: cur.z,
            x,
            y,
            opacity: cur.opacity,
            visible: cur.visible,
          }
          break
        }
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
