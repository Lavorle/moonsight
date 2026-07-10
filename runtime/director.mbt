///|
/// Dispatches host ops to Stage (and later audio/plugins).
///
/// Task 7 registers a built-in mock minimum; Task 8 loads the full std_commands table.
pub(all) struct Director {
  handlers : Map[String, HostHandler]
} derive(Debug)

///|
/// Director with text/layer/var built-ins registered.
pub fn Director::with_builtins() -> Director {
  {
    handlers: {
      "text.begin": Builtin(TextBegin),
      "text.type": Builtin(TextType),
      "text.end": Builtin(TextEnd),
      "layer.show": Builtin(LayerShow),
      "layer.hide": Builtin(LayerHide),
      "layer.move": Builtin(LayerMove),
      "var.set": Builtin(VarSet),
    },
  }
}

///|
/// Empty director (no handlers); useful for tests that inject handlers later.
pub fn Director::new() -> Director {
  { handlers: {} }
}

///|
/// Register or replace a host handler by name.
pub fn Director::register(
  self : Director,
  name : String,
  handler : HostHandler,
) -> Unit {
  self.handlers[name] = handler
}

///|
/// Invoke a host op by name.
pub fn Director::call(
  self : Director,
  name : String,
  stage : Stage,
  args : Array[Value],
) -> HostResult {
  match self.handlers.get(name) {
    Some(Builtin(kind)) => dispatch_builtin_kind(kind, stage, args)
    None =>
      // Fall back to string dispatch so unregistered-but-known builtins still work.
      dispatch_builtin(name, stage, args)
  }
}
