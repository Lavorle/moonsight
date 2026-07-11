///|
/// Demo project UI overlay: branded title card after `@std_ui.register`.
///
/// Linked into `host_web/project_ui` when `moonsight.json` sets
/// `"ui_package": "ui"`. Leaves HUD and other modals from std_ui.

///|
/// Column X matches std_ui 400px system buttons centered on FHD.
let demo_col_x : Double = 760.0

///|
let demo_card_x : Double = 680.0

///|
let demo_card_w : Double = 560.0

///|
/// Override title only: MoonSight brand + Demo subtitle + Start/Load/Settings.
pub fn register(app : @runtime.UiApp) -> Unit {
  app.register_modal(
    "title",
    @runtime.UiNode::Fixed(
      x=0.0,
      y=0.0,
      w=Some(1920.0),
      h=Some(1080.0),
      children=[
        @runtime.UiNode::Panel(
          resource="ui.dialogue_box",
          x=demo_card_x,
          y=240.0,
          w=demo_card_w,
          h=560.0,
          visible=@runtime.VisiblePred::Always,
        ),
        @runtime.UiNode::VBox(
          x=Some(demo_col_x),
          y=Some(290.0),
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
              font_size=22.0,
              visible=@runtime.VisiblePred::Always,
            ),
            @runtime.UiNode::Spacer(w=400.0, h=16.0),
            app.button(
              "Start",
              fn(c : &@runtime.Capabilities) { c.start_game() },
            ),
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
      ],
    ),
  )
}
