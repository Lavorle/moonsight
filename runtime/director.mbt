///|
/// Dispatches host ops to Stage (and later audio/plugins).
///
/// `with_builtins` is the Task 7 minimum set. Full Phase 1 table is
/// `@std_commands.standard_registry()` (no runtime→std_commands import).
pub(all) struct Director {
  handlers : Map[String, HostHandler]
  effects : Map[String, CommandEffect]
} derive(Debug)

///|
/// Rollback policy attached to every Director registration.
pub(all) enum CommandEffect {
  /// Pure logical state change captured by the checkpoint kernel.
  Checkpointed
  /// External audio state that has an idempotent logical reconciliation path.
  CompensatableAudio
  /// Irreversible/unknown effect; successful execution clears older reachability.
  Barrier(String)
} derive(Debug, Eq)

///|
let unknown_command_barrier : CommandEffect = Barrier(
  "rollback.barrier.unknown-command",
)

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
    effects: {
      "text.begin": Checkpointed,
      "text.type": Checkpointed,
      "text.end": Checkpointed,
      "layer.show": Checkpointed,
      "layer.hide": Checkpointed,
      "layer.move": Checkpointed,
      "layer.set": Checkpointed,
      "var.set": Checkpointed,
    },
  }
}

///|
/// Empty director (no handlers); useful for tests that inject handlers later.
pub fn Director::new() -> Director {
  { handlers: {}, effects: {} }
}

///|
/// Register or replace a host handler by name.
pub fn Director::register(
  self : Director,
  name : String,
  handler : HostHandler,
) -> Unit {
  self.handlers[name] = handler
  self.effects[name] = unknown_command_barrier
}

///|
/// Register or replace a typed handler with an explicit effect policy.
pub fn Director::register_with_effect(
  self : Director,
  name : String,
  handler : HostHandler,
  effect : CommandEffect,
) -> Unit {
  self.handlers[name] = handler
  self.effects[name] = effect
}

///|
/// Register a function handler by name (used by `std_commands`).
pub fn Director::register_fn(
  self : Director,
  name : String,
  handler : (Stage, Array[Value]) -> HostResult,
) -> Unit {
  self.handlers[name] = Handler(handler)
  self.effects[name] = unknown_command_barrier
}

///|
/// Register a function handler with its frozen rollback effect policy.
pub fn Director::register_fn_with_effect(
  self : Director,
  name : String,
  handler : (Stage, Array[Value]) -> HostResult,
  effect : CommandEffect,
) -> Unit {
  self.handlers[name] = Handler(handler)
  self.effects[name] = effect
}

///|
/// Return the registered effect policy. Unknown commands are barriers.
pub fn Director::effect_for(self : Director, name : String) -> CommandEffect {
  match self.effects.get(name) {
    Some(effect) => effect
    None => unknown_command_barrier
  }
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
