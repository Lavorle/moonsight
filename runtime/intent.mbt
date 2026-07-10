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
  /// Move screen focus up (previous focusable).
  MenuUp
  /// Move screen focus down (next focusable).
  MenuDown
  /// Move screen focus / slider left (previous value).
  MenuLeft
  /// Move screen focus / slider right (next value).
  MenuRight
  /// Open the dialogue backlog modal while Playing.
  OpenBacklog
} derive(Debug, Eq)
