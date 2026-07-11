///|
/// Standard system modals: title, game_menu, save_load, settings, confirm, backlog.
///
/// Layout notes (Amber Soft):
/// - Modal cards use `ui.dialogue_box` as a chrome panel (absolute coords).
/// - Button column is 400px wide, centered on FHD: left ≈ (1920-400)/2 = 760.
/// - Capabilities handlers stay identical to prior behavior.

///|
/// Centered button column X for 400px-wide system buttons.
let modal_col_x : Double = 760.0

///|
/// Modal card (panel chrome) for single-column menus.
let modal_card_x : Double = 680.0

///|
let modal_card_w : Double = 560.0

///|
fn build_title(app : @runtime.UiApp) -> @runtime.UiNode {
  @runtime.UiNode::Fixed(
    x=0.0,
    y=0.0,
    w=Some(1920.0),
    h=Some(1080.0),
    children=[
      @runtime.UiNode::Panel(
        resource="ui.dialogue_box",
        x=modal_card_x,
        y=250.0,
        w=modal_card_w,
        h=520.0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::VBox(
        x=Some(modal_col_x),
        y=Some(300.0),
        children=[
          @runtime.UiNode::Text(
            src=@runtime.TextBindSrc::Literal("MoonSight"),
            x=0.0,
            y=0.0,
            font_size=42.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Spacer(w=400.0, h=12.0),
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
    ],
  )
}

///|
fn build_game_menu(app : @runtime.UiApp) -> @runtime.UiNode {
  @runtime.UiNode::Fixed(
    x=0.0,
    y=0.0,
    w=Some(1920.0),
    h=Some(1080.0),
    children=[
      @runtime.UiNode::Panel(
        resource="ui.dialogue_box",
        x=modal_card_x,
        y=160.0,
        w=modal_card_w,
        h=720.0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::VBox(
        x=Some(modal_col_x),
        y=Some(200.0),
        children=[
          @runtime.UiNode::Text(
            src=@runtime.TextBindSrc::Literal("Menu"),
            x=0.0,
            y=0.0,
            font_size=32.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Spacer(w=400.0, h=8.0),
          app.button(
            "Continue",
            fn(c : &@runtime.Capabilities) { c.return_modal() },
          ),
          app.button(
            "History",
            fn(c : &@runtime.Capabilities) {
              c.show_modal("backlog", mode=None)
            },
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
            fn(c : &@runtime.Capabilities) {
              c.show_modal("settings", mode=None)
            },
          ),
          app.button(
            "Title",
            fn(c : &@runtime.Capabilities) { c.request_quit_to_title() },
          ),
        ],
      ),
    ],
  )
}

///|
/// Backlog: wide card, 12 lines + Close.
fn build_backlog(app : @runtime.UiApp) -> @runtime.UiNode {
  let children : Array[@runtime.UiNode] = [
    @runtime.UiNode::Text(
      src=@runtime.TextBindSrc::Literal("History"),
      x=0.0,
      y=0.0,
      font_size=30.0,
      visible=@runtime.VisiblePred::Always,
    ),
    @runtime.UiNode::Spacer(w=800.0, h=8.0),
  ]
  for i in 0..<12 {
    children.push(
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::BacklogLine(i),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=@runtime.VisiblePred::Always,
      ),
    )
  }
  children.push(@runtime.UiNode::Spacer(w=400.0, h=8.0))
  children.push(
    app.button("Close", fn(c : &@runtime.Capabilities) { c.return_modal() }),
  )
  @runtime.UiNode::Fixed(
    x=0.0,
    y=0.0,
    w=Some(1920.0),
    h=Some(1080.0),
    children=[
      @runtime.UiNode::Panel(
        resource="ui.dialogue_box",
        x=280.0,
        y=48.0,
        w=1360.0,
        h=980.0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::VBox(x=Some(360.0), y=Some(72.0), children~),
    ],
  )
}

///|
/// Confirm: No registered first so default focus is safe-cancel.
fn build_confirm(app : @runtime.UiApp) -> @runtime.UiNode {
  @runtime.UiNode::Fixed(
    x=0.0,
    y=0.0,
    w=Some(1920.0),
    h=Some(1080.0),
    children=[
      @runtime.UiNode::Panel(
        resource="ui.dialogue_box",
        x=modal_card_x,
        y=320.0,
        w=modal_card_w,
        h=400.0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::VBox(
        x=Some(modal_col_x),
        y=Some(360.0),
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
          @runtime.UiNode::Spacer(w=400.0, h=12.0),
          app.button(
            "No",
            fn(c : &@runtime.Capabilities) { c.confirm_no() },
          ),
          app.button(
            "Yes",
            fn(c : &@runtime.Capabilities) { c.confirm_yes() },
          ),
        ],
      ),
    ],
  )
}

///|
/// Six slots: label + Save/Load action on one row (HBox), then Back.
fn build_save_load(app : @runtime.UiApp) -> @runtime.UiNode {
  let children : Array[@runtime.UiNode] = [
    @runtime.UiNode::Text(
      src=@runtime.TextBindSrc::Literal("Save / Load"),
      x=0.0,
      y=0.0,
      font_size=30.0,
      visible=@runtime.VisiblePred::Always,
    ),
    @runtime.UiNode::Spacer(w=800.0, h=12.0),
  ]
  for i in 0..<6 {
    let slot = i
    let save_id = app.alloc_action(fn(c : &@runtime.Capabilities) {
      c.save_slot(slot)
    })
    let load_id = app.alloc_action(fn(c : &@runtime.Capabilities) {
      c.load_slot(slot)
    })
    // Label row (slot timestamp / empty marker).
    children.push(
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::SlotLabel(slot),
        x=0.0,
        y=0.0,
        font_size=22.0,
        visible=@runtime.VisiblePred::Always,
      ),
    )
    // Action sits under label (VBox still 64px/line — clearer than cramped HBox
    // with two 400px buttons). Save and Load share the same visual row via mode.
    children.push(
      @runtime.UiNode::Button(
        label="Save",
        action_id=save_id,
        visible=@runtime.VisiblePred::ModeIs("save"),
      ),
    )
    children.push(
      @runtime.UiNode::Button(
        label="Load",
        action_id=load_id,
        visible=@runtime.VisiblePred::And(
          @runtime.VisiblePred::ModeIs("load"),
          @runtime.VisiblePred::SlotOccupied(slot),
        ),
      ),
    )
  }
  children.push(@runtime.UiNode::Spacer(w=400.0, h=8.0))
  children.push(
    app.button("Back", fn(c : &@runtime.Capabilities) { c.return_modal() }),
  )
  @runtime.UiNode::Fixed(
    x=0.0,
    y=0.0,
    w=Some(1920.0),
    h=Some(1080.0),
    children=[
      @runtime.UiNode::Panel(
        resource="ui.dialogue_box",
        x=480.0,
        y=40.0,
        w=960.0,
        h=1000.0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::VBox(x=Some(modal_col_x), y=Some(64.0), children~),
    ],
  )
}

///|
/// Settings: sectioned sliders + Auto toggle pair + Back.
fn build_settings(app : @runtime.UiApp) -> @runtime.UiNode {
  @runtime.UiNode::Fixed(
    x=0.0,
    y=0.0,
    w=Some(1920.0),
    h=Some(1080.0),
    children=[
      @runtime.UiNode::Panel(
        resource="ui.dialogue_box",
        x=560.0,
        y=48.0,
        w=800.0,
        h=980.0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::VBox(
        x=Some(modal_col_x),
        y=Some(72.0),
        children=[
          @runtime.UiNode::Text(
            src=@runtime.TextBindSrc::Literal("Settings"),
            x=0.0,
            y=0.0,
            font_size=32.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Spacer(w=400.0, h=8.0),
          @runtime.UiNode::Text(
            src=@runtime.TextBindSrc::Pref("text_speed"),
            x=0.0,
            y=0.0,
            font_size=22.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Slider(
            key="text_speed",
            x=0.0,
            y=0.0,
            w=400.0,
            h=36.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Text(
            src=@runtime.TextBindSrc::Pref("auto_mode"),
            x=0.0,
            y=0.0,
            font_size=22.0,
            visible=@runtime.VisiblePred::Always,
          ),
          app.button(
            "Auto on",
            fn(c : &@runtime.Capabilities) {
              c.set_pref_b("auto_mode", true)
            },
          ),
          app.button(
            "Auto off",
            fn(c : &@runtime.Capabilities) {
              c.set_pref_b("auto_mode", false)
            },
          ),
          @runtime.UiNode::Text(
            src=@runtime.TextBindSrc::Pref("master_volume"),
            x=0.0,
            y=0.0,
            font_size=22.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Slider(
            key="master_volume",
            x=0.0,
            y=0.0,
            w=400.0,
            h=36.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Text(
            src=@runtime.TextBindSrc::Pref("bgm_volume"),
            x=0.0,
            y=0.0,
            font_size=22.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Slider(
            key="bgm_volume",
            x=0.0,
            y=0.0,
            w=400.0,
            h=36.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Text(
            src=@runtime.TextBindSrc::Pref("se_volume"),
            x=0.0,
            y=0.0,
            font_size=22.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Slider(
            key="se_volume",
            x=0.0,
            y=0.0,
            w=400.0,
            h=36.0,
            visible=@runtime.VisiblePred::Always,
          ),
          @runtime.UiNode::Spacer(w=400.0, h=8.0),
          app.button(
            "Back",
            fn(c : &@runtime.Capabilities) { c.return_modal() },
          ),
        ],
      ),
    ],
  )
}
