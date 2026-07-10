///|
/// Dispatches host ops to Stage (and later audio/plugins).
///
/// `with_builtins` is the Task 7 minimum set. Full Phase 1 table is
/// `@std_commands.standard_registry()` (no runtime→std_commands import).
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
      "layer.set": Builtin(LayerSet),
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
/// Register a function handler by name (used by `std_commands`).
pub fn Director::register_fn(
  self : Director,
  name : String,
  handler : (Stage, Array[Value]) -> HostResult,
) -> Unit {
  self.handlers[name] = Handler(handler)
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
    Some(Handler(f)) => f(stage, args)
    None =>
      // Fall back to string dispatch so unregistered-but-known builtins still work.
      dispatch_builtin(name, stage, args)
  }
}

///|
/// Sorted list of currently registered host names (for alignment tests).
pub fn Director::registered_names(self : Director) -> Array[String] {
  let names : Array[String] = []
  for k, _ in self.handlers {
    names.push(k)
  }
  names.sort()
  names
}
