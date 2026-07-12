///|
/// Split flattened IR host args into positionals only, stripping `#:key` pairs
/// (same encoding as `@runtime.split_host_args` / `lower_args`).
fn split_ir_positionals(args : Array[@script.IrValue]) -> Array[@script.IrValue] {
  let pos : Array[@script.IrValue] = []
  let mut i = 0
  while i < args.length() {
    match args[i] {
      Str(s) =>
        if s.has_prefix("#:") && i + 1 < args.length() {
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
  pos
}

///|
/// Collect unique string-literal resource refs with kind from host op:
/// - `layer.show` → image — 2nd positional (skip empty `""`)
/// - `audio.bgm` / `audio.se` → audio — string positional args (skip empty)
/// Returns pairs `(kind, id)` where kind is `"image"` or `"audio"`.
fn collect_literal_resource_refs(
  ir : @script.IrModule,
) -> Array[(String, String)] {
  let seen : Map[String, Bool] = {}
  let out : Array[(String, String)] = []
  for _, scene in ir.scenes {
    for op in scene.ops {
      match op {
        Host(name~, args~) => {
          if name == "layer.show" {
            let pos = split_ir_positionals(args)
            if pos.length() >= 2 {
              match pos[1] {
                Str(id) => push_resource_ref("image", id, seen, out)
                _ => ()
              }
            }
          } else if name == "audio.bgm" || name == "audio.se" {
            let pos = split_ir_positionals(args)
            for v in pos {
              match v {
                Str(id) => push_resource_ref("audio", id, seen, out)
                _ => ()
              }
            }
          }
        }
        _ => ()
      }
    }
  }
  out
}

///|
fn push_resource_ref(
  kind : String,
  id : String,
  seen : Map[String, Bool],
  out : Array[(String, String)],
) -> Unit {
  if id == "" || seen.contains(id) {
    return
  }
  seen[id] = true
  out.push((kind, id))
}

///|
/// Ensure every script-referenced literal resource id exists in `resources` or
/// `audio` (from on-disk assets). Prints one error per missing id, distinguishing
/// audio vs image by the host op that referenced it.
/// Returns `true` when all refs resolve.
fn validate_literal_resources(
  ir : @script.IrModule,
  resources : Map[String, String],
  audio : Map[String, String],
) -> Bool {
  let mut ok = true
  for item in collect_literal_resource_refs(ir) {
    let (kind, id) = item
    if !resources.contains(id) && !audio.contains(id) {
      if kind == "audio" {
        println("error: missing audio `\{id}` referenced by script")
      } else {
        println("error: missing image `\{id}` referenced by script")
      }
      ok = false
    }
  }
  ok
}
