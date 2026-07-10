///|
/// Project UI overlay package linked into `host_web`.
///
/// Default stub is a no-op. When `moonsight.json` sets `ui_package`, moonsightc
/// overwrites `*.mbt` here from the project package for the wasm build, then
/// restores this stub afterward.

///|
/// Register project HUD / modal overrides on the shared `UiApp` (after `std_ui`).
pub fn register(_app : @runtime.UiApp) -> Unit {
  ()
}
