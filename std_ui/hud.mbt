///|
/// Default HUD geometry for FHD (1920×1080). Amber Soft: bottom dialogue band
/// with nameplate on the top edge, choices stacked above the box.

///|
let hud_dialogue_x : Double = 64.0

///|
/// Slightly higher so choices have room without overlapping the box.
let hud_dialogue_y : Double = 772.0

///|
let hud_dialogue_w : Double = 1792.0

///|
/// Shorter band — less visual weight, more stage room.
let hud_dialogue_h : Double = 276.0

///|
let hud_nameplate_x : Double = 96.0

///|
/// Sits on the dialogue box top rim.
let hud_nameplate_y : Double = 748.0

///|
let hud_nameplate_w : Double = 400.0

///|
let hud_nameplate_h : Double = 44.0

///|
let hud_text_x : Double = 96.0

///|
let hud_text_y : Double = 828.0

///|
let hud_body_font : Double = 30.0

///|
let hud_name_font : Double = 26.0

///|
/// Choice stack sits above the dialogue band, full width with side margin.
let hud_choice_x : Double = 160.0

///|
let hud_choice_y : Double = 480.0

///|
let hud_choice_w : Double = 1600.0

///|
/// Comfortable click target (~52px painted height with 8px gap).
let hud_choice_line_h : Double = 56.0

///|
/// Build the default dialogue + choice HUD tree.
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
        x=hud_nameplate_x + 20.0,
        y=hud_nameplate_y + 6.0,
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
