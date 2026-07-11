///|
/// Demo project UI overlay: re-register the title modal with a custom label.
///
/// Linked into `host_web/project_ui` when `moonsight.json` sets
/// `"ui_package": "ui"`. Runs after `@std_ui.register`.

///|
/// Override title only; leave HUD and other modals from std_ui.
pub fn register(app : @runtime.UiApp) -> Unit {
  app.register_modal(
    "title",
    @runtime.UiNode::VBox(
      x=Some(760.0),
      y=Some(340.0),
      children=[
        @runtime.UiNode::Text(
          src=@runtime.TextBindSrc::Literal("MoonSight"),
          x=0.0,
          y=0.0,
          font_size=48.0,
          visible=@runtime.VisiblePred::Always,
        ),
        @runtime.UiNode::Text(
          src=@runtime.TextBindSrc::Literal("Demo"),
          x=0.0,
          y=0.0,
          font_size=24.0,
          visible=@runtime.VisiblePred::Always,
        ),
        app.button("Start", fn(c : &@runtime.Capabilities) { c.start_game() }),
        app.button(
          "Load",
          fn(c : &@runtime.Capabilities) {
            c.show_modal("save_load", mode=Some("load"))
          },
        ),
        app.button(
          "Settings",
          fn(c : &@runtime.Capabilities) {
            c.show_modal("settings", mode=None)
          },
        ),
      ],
    ),
  )
}
