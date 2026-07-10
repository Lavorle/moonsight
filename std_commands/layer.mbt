///|
/// `layer.show id resource [z] [x] [y] [opacity]`
///
/// Kind defaults to Background. Numeric args accept Int or Float.
pub fn cmd_layer_show(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [Str(id), Str(resource), .. rest] => {
      let z = match rest {
        [z0, ..] =>
          match @runtime.value_as_int(z0) {
            Some(n) => n
            None => 0
          }
        _ => 0
      }
      let x = match rest {
        [_, x0, ..] =>
          match @runtime.value_as_double(x0) {
            Some(n) => n
            None => 0.0
          }
        _ => 0.0
      }
      let y = match rest {
        [_, _, y0, ..] =>
          match @runtime.value_as_double(y0) {
            Some(n) => n
            None => 0.0
          }
        _ => 0.0
      }
      let opacity = match rest {
        [_, _, _, o, ..] =>
          match @runtime.value_as_double(o) {
            Some(n) => n
            None => 1.0
          }
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
/// `layer.hide id`
pub fn cmd_layer_hide(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  match args {
    [Str(id), ..] => {
      stage.hide_layer(id~)
      Ok
    }
    _ => Error("layer.hide: expected id Str")
  }
}

///|
/// `layer.move id x y` — Int/Float coords; no-op if layer missing.
pub fn cmd_layer_move(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let coords : (String, Double, Double)? = match args {
    [Str(id), x, y, ..] =>
      match (@runtime.value_as_double(x), @runtime.value_as_double(y)) {
        (Some(xd), Some(yd)) => Some((id, xd, yd))
        _ => None
      }
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
