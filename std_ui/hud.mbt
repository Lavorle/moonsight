///|
/// Default HUD geometry constants (port of old `UiLayout::default_fhd` dialogue chrome).
/// Canvas is 1920×1080 logical pixels.

///|
let hud_dialogue_x : Double = 48.0

///|
let hud_dialogue_y : Double = 756.0

///|
let hud_dialogue_w : Double = 1824.0

///|
let hud_dialogue_h : Double = 324.0

///|
let hud_nameplate_x : Double = 80.0

///|
let hud_nameplate_y : Double = 788.0

///|
let hud_nameplate_w : Double = 360.0

///|
let hud_nameplate_h : Double = 48.0

///|
let hud_text_x : Double = 80.0

///|
let hud_text_y : Double = 848.0

///|
let hud_body_font : Double = 32.0

///|
let hud_name_font : Double = 28.0

///|
let hud_choice_x : Double = 80.0

///|
let hud_choice_y : Double = 556.0

///|
let hud_choice_w : Double = 1760.0

///|
let hud_choice_line_h : Double = 48.0

///|
/// Build the default dialogue + choice HUD tree.
///
/// Geometry mirrors the former hard-coded FHD dialogue chrome; visibility is
/// gated by `HasText` / `HasChoices` so chrome only paints during narrative.
fn build_hud(_app : @runtime.UiApp) -> @runtime.UiNode {
  @runtime.UiNode::Fixed(
    x=0.0,
    y=0.0,
    w=Some(1920.0),
    h=Some(1080.0),
    children=[
      @runtime.UiNode::Panel(
        resource="ui.dialogue_box",
        x=hud_dialogue_x,
        y=hud_dialogue_y,
        w=hud_dialogue_w,
        h=hud_dialogue_h,
        visible=@runtime.VisiblePred::HasText,
      ),
      @runtime.UiNode::Panel(
        resource="ui.nameplate",
        x=hud_nameplate_x,
        y=hud_nameplate_y,
        w=hud_nameplate_w,
        h=hud_nameplate_h,
        visible=@runtime.VisiblePred::HasText,
      ),
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::DialogueName,
        x=hud_nameplate_x,
        y=hud_nameplate_y,
        font_size=hud_name_font,
        visible=@runtime.VisiblePred::HasText,
      ),
      @runtime.UiNode::Text(
        src=@runtime.TextBindSrc::DialogueBody,
        x=hud_text_x,
        y=hud_text_y,
        font_size=hud_body_font,
        visible=@runtime.VisiblePred::HasText,
      ),
      @runtime.UiNode::ChoiceList(
        x=hud_choice_x,
        y=hud_choice_y,
        w=hud_choice_w,
        line_h=hud_choice_line_h,
        visible=@runtime.VisiblePred::HasChoices,
      ),
    ],
  )
}
