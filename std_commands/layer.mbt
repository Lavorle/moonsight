///|
/// Parse `LayerKind` from a host value (case-insensitive string).
///
/// Accepts quoted forms (`kind="background"` → `Str`) and bare keywords that
/// survived as strings. Unknown values yield `None`.
fn parse_kind(v : @runtime.Value) -> @runtime.LayerKind? {
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
/// Read optional double from named map key.
fn named_double(
  named : Map[String, @runtime.Value],
  key : String,
) -> Double? {
  match named.get(key) {
    Some(v) => @runtime.value_as_double(v)
    None => None
  }
}

///|
/// Read optional int from named map key.
fn named_int(named : Map[String, @runtime.Value], key : String) -> Int? {
  match named.get(key) {
    Some(v) => @runtime.value_as_int(v)
    None => None
  }
}

///|
/// Find layer index by id.
fn find_layer_index(stage : @runtime.Stage, id : String) -> Int? {
  for i in 0..<stage.layers.length() {
    if stage.layers[i].id == id {
      return Some(i)
    }
  }
  None
}

///|
/// Apply or tween a property when it was specified by the caller.
fn apply_or_tween(
  stage : @runtime.Stage,
  id~ : String,
  prop~ : @runtime.TweenProp,
  to~ : Double,
  duration~ : Double,
) -> Unit {
  stage.start_layer_tween(id~, prop~, to~, duration~)
}

///|
/// `layer.show id resource [z] [x] [y] [opacity]` plus named `kind` / `duration` / etc.
///
/// Default kind is **Character**. New layers with `duration > 0` start opacity at 0
/// and tween to the target (default 1.0). Existing layers tween only specified x/y/opacity.
pub fn cmd_layer_show(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let (pos, named) = @runtime.split_host_args(args)
  let id = match pos {
    [Str(s), ..] => s
    _ => return Error("layer.show: expected id Str and resource Str")
  }
  // Two-arg+: resource is Str at pos[1]. Single-arg form: empty resource.
  // Note: `[_, ..]` would also match `[Str(id)]`, so single-arg must be first.
  let resource = match pos {
    [_, Str(s), ..] => s
    [_] => ""
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

  // Prefer named keys when present; else legacy positional z,x,y,opacity.
  let z_opt : Int? = match named_int(named, "z") {
    Some(n) => Some(n)
    None =>
      match pos {
        [_, _, z0, ..] =>
          match @runtime.value_as_int(z0) {
            Some(n) => Some(n)
            None => None
          }
        _ => None
      }
  }
  let x_opt : Double? = match named_double(named, "x") {
    Some(n) => Some(n)
    None =>
      match pos {
        [_, _, _, x0, ..] => @runtime.value_as_double(x0)
        _ => None
      }
  }
  let y_opt : Double? = match named_double(named, "y") {
    Some(n) => Some(n)
    None =>
      match pos {
        [_, _, _, _, y0, ..] => @runtime.value_as_double(y0)
        _ => None
      }
  }
  let opacity_opt : Double? = match named_double(named, "opacity") {
    Some(n) => Some(n)
    None =>
      match pos {
        [_, _, _, _, _, o, ..] => @runtime.value_as_double(o)
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
      // Existing layer: z/kind/resource immediate; specified x/y/opacity tween or snap.
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
        Some(xv) => apply_or_tween(stage, id~, prop=X, to=xv, duration~)
        None => ()
      }
      match y_opt {
        Some(yv) => apply_or_tween(stage, id~, prop=Y, to=yv, duration~)
        None => ()
      }
      match opacity_opt {
        Some(ov) => apply_or_tween(stage, id~, prop=Opacity, to=ov, duration~)
        None => ()
      }
      Ok
    }
    None => {
      // New layer.
      if duration > 0.0 {
        // x/y/z/kind/resource immediate; opacity starts at 0 and tweens to target.
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
/// `layer.hide id` — optional `#:duration` fades out then removes.
pub fn cmd_layer_hide(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let (pos, named) = @runtime.split_host_args(args)
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
/// `layer.move id x y` — optional `#:duration` tweens position.
pub fn cmd_layer_move(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let (pos, named) = @runtime.split_host_args(args)
  let coords : (String, Double, Double)? = match pos {
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
      let duration = match named_double(named, "duration") {
        Some(d) => d
        None => 0.0
      }
      // No-op if missing (Phase 1 compatibility).
      match find_layer_index(stage, id) {
        None => Ok
        Some(_) => {
          apply_or_tween(stage, id~, prop=X, to=x, duration~)
          apply_or_tween(stage, id~, prop=Y, to=y, duration~)
          Ok
        }
      }
    }
  }
}

///|
/// `layer.set id` with named `x` / `y` / `opacity` / `duration`.
///
/// Errors if the layer id is missing (soft-halt, not silent no-op).
pub fn cmd_layer_set(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let (pos, named) = @runtime.split_host_args(args)
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
        Some(xv) => apply_or_tween(stage, id~, prop=X, to=xv, duration~)
        None => ()
      }
      match named_double(named, "y") {
        Some(yv) => apply_or_tween(stage, id~, prop=Y, to=yv, duration~)
        None => ()
      }
      match named_double(named, "opacity") {
        Some(ov) => apply_or_tween(stage, id~, prop=Opacity, to=ov, duration~)
        None => ()
      }
      Ok
    }
  }
}
