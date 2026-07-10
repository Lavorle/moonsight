///|
/// Standard system modals: title, game_menu, save_load, settings, confirm.
///
/// Labels and actions for system modals on `UiApp` + `Capabilities`.

///|
fn build_title(app : @runtime.UiApp) -> @runtime.UiNode {
  @runtime.UiNode::VBox(
    x=Some(760.0),
    y=Some(360.0),
    children=[
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Literal("MoonSight"),
        x=0.0,
        y=0.0,
        font_size=36.0,
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
        fn(c : &@runtime.Capabilities) { c.show_modal("settings", mode=None) },
      ),
    ],
  )
}

///|
fn build_game_menu(app : @runtime.UiApp) -> @runtime.UiNode {
  @runtime.UiNode::VBox(
    x=Some(760.0),
    y=Some(300.0),
    children=[
      app.button(
        "Continue",
        fn(c : &@runtime.Capabilities) { c.return_modal() },
      ),
      app.button(
        "Save",
        fn(c : &@runtime.Capabilities) {
          c.show_modal("save_load", mode=Some("save"))
        },
      ),
      app.button(
        "Load",
        fn(c : &@runtime.Capabilities) {
          c.show_modal("save_load", mode=Some("load"))
        },
      ),
      app.button(
        "Settings",
        fn(c : &@runtime.Capabilities) { c.show_modal("settings", mode=None) },
      ),
      app.button(
        "Title",
        fn(c : &@runtime.Capabilities) { c.request_quit_to_title() },
      ),
    ],
  )
}

///|
/// Confirm modal: default focus is No (registered first).
fn build_confirm(app : @runtime.UiApp) -> @runtime.UiNode {
  @runtime.UiNode::VBox(
    x=Some(760.0),
    y=Some(400.0),
    children=[
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Literal("Confirm"),
        x=0.0,
        y=0.0,
        font_size=30.0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Literal("Are you sure?"),
        x=0.0,
        y=0.0,
        font_size=24.0,
        visible=@runtime.VisiblePred::Always,
      ),
      app.button(
        "No",
        fn(c : &@runtime.Capabilities) { c.confirm_no() },
      ),
      app.button(
        "Yes",
        fn(c : &@runtime.Capabilities) { c.confirm_yes() },
      ),
    ],
  )
}

///|
/// Six fixed slots (default `save_slots`). Two button sets per slot:
/// - save mode: ModeIs("save") → save_slot(i) (empty slots remain focusable)
/// - load mode: ModeIs("load") ∧ SlotOccupied(i) → load_slot(i)
fn build_save_load(app : @runtime.UiApp) -> @runtime.UiNode {
  let children : Array[@runtime.UiNode] = [
    @runtime.UiNode::Text(
      src=@runtime.TextBindSrc::Literal("Save / Load"),
      x=0.0,
      y=0.0,
      font_size=30.0,
      visible=@runtime.VisiblePred::Always,
    ),
  ]
  for i in 0..<6 {
    let slot = i
    let save_id = app.alloc_action(fn(c : &@runtime.Capabilities) {
      c.save_slot(slot)
    })
    let load_id = app.alloc_action(fn(c : &@runtime.Capabilities) {
      c.load_slot(slot)
    })
    children.push(
      @runtime.UiNode::Button(
        label="Slot \{slot}",
        action_id=save_id,
        visible=@runtime.VisiblePred::ModeIs("save"),
      ),
    )
    children.push(
      @runtime.UiNode::Button(
        label="Slot \{slot}",
        action_id=load_id,
        visible=@runtime.VisiblePred::And(
          @runtime.VisiblePred::ModeIs("load"),
          @runtime.VisiblePred::SlotOccupied(slot),
        ),
      ),
    )
  }
  children.push(
    app.button("Back", fn(c : &@runtime.Capabilities) { c.return_modal() }),
  )
  @runtime.UiNode::VBox(x=Some(600.0), y=Some(120.0), children~)
}

///|
fn build_settings(app : @runtime.UiApp) -> @runtime.UiNode {
  @runtime.UiNode::VBox(
    x=Some(700.0),
    y=Some(180.0),
    children=[
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Literal("Settings"),
        x=0.0,
        y=0.0,
        font_size=30.0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Pref("text_speed"),
        x=0.0,
        y=0.0,
        font_size=24.0,
        visible=@runtime.VisiblePred::Always,
      ),
      app.button(
        "Text +",
        fn(c : &@runtime.Capabilities) { c.adjust_pref("text_speed", 0.25) },
      ),
      app.button(
        "Text -",
        fn(c : &@runtime.Capabilities) { c.adjust_pref("text_speed", -0.25) },
      ),
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Pref("auto_mode"),
        x=0.0,
        y=0.0,
        font_size=24.0,
        visible=@runtime.VisiblePred::Always,
      ),
      app.button(
        "Auto on",
        fn(c : &@runtime.Capabilities) { c.set_pref_b("auto_mode", true) },
      ),
      app.button(
        "Auto off",
        fn(c : &@runtime.Capabilities) { c.set_pref_b("auto_mode", false) },
      ),
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Pref("master_volume"),
        x=0.0,
        y=0.0,
        font_size=24.0,
        visible=@runtime.VisiblePred::Always,
      ),
      app.button(
        "Master +",
        fn(c : &@runtime.Capabilities) {
          c.adjust_pref("master_volume", 0.1)
        },
      ),
      app.button(
        "Master -",
        fn(c : &@runtime.Capabilities) {
          c.adjust_pref("master_volume", -0.1)
        },
      ),
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Pref("bgm_volume"),
        x=0.0,
        y=0.0,
        font_size=24.0,
        visible=@runtime.VisiblePred::Always,
      ),
      app.button(
        "BGM +",
        fn(c : &@runtime.Capabilities) { c.adjust_pref("bgm_volume", 0.1) },
      ),
      app.button(
        "BGM -",
        fn(c : &@runtime.Capabilities) { c.adjust_pref("bgm_volume", -0.1) },
      ),
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::Pref("se_volume"),
        x=0.0,
        y=0.0,
        font_size=24.0,
        visible=@runtime.VisiblePred::Always,
      ),
      app.button(
        "SE +",
        fn(c : &@runtime.Capabilities) { c.adjust_pref("se_volume", 0.1) },
      ),
      app.button(
        "SE -",
        fn(c : &@runtime.Capabilities) { c.adjust_pref("se_volume", -0.1) },
      ),
      app.button(
        "Back",
        fn(c : &@runtime.Capabilities) { c.return_modal() },
      ),
    ],
  )
}
