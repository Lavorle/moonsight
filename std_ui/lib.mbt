///|
/// Standard MoonSight UI package: default HUD + system modals.
///
/// Hosts build a `UiApp`, call `register`, then pass the app into
/// `Engine::from_ir(..., app~)`. Runtime never imports this package.

///|
/// Install default HUD and title / game_menu / save_load / settings / confirm / backlog modals.
pub fn register(app : @runtime.UiApp, save_slots~ : Int = 6) -> Unit {
  app.set_hud(build_hud(app))
  app.register_modal("title", build_title(app))
  app.register_modal("game_menu", build_game_menu(app))
  app.register_modal("save_load", build_save_load(app, save_slots))
  app.register_modal("settings", build_settings(app))
  app.register_modal("confirm", build_confirm(app))
  app.register_modal("backlog", build_backlog(app))
}
