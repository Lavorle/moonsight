///|
/// Player / system input intent for one frame (or resume step).
///
/// Host/input maps device events to intents; the engine applies them to
/// Yield/Choose wait states before continuing the VM.
pub(all) enum Intent {
  None_
  Advance
  Select(Int)
  SkipTyping
  OpenMenu
  ToggleAuto
} derive(Debug, Eq)
