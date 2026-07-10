///|
/// RGBA color in linear/display space (0..1 per channel).
pub(all) struct Color {
  r : Float
  g : Float
  b : Float
  a : Float
} derive(Debug, Eq)

///|
/// One textured quad for backgrounds, characters, and UI panels.
///
/// Coordinates are logical canvas pixels (origin top-left, +y down).
pub(all) struct SpriteDraw {
  resource : String
  x : Float
  y : Float
  w : Float
  h : Float
  opacity : Float
  z : Int
} derive(Debug)

///|
/// One glyph quad; UV rect is in the shared atlas texture (pixels).
///
/// `w`/`h` are **screen** size in logical canvas pixels (pen advance × line
/// height). They are intentionally separate from `atlas_w`/`atlas_h` (shelf
/// cell size used for rasterization). Using the full atlas cell as the screen
/// quad made Latin text look wildly letter-spaced.
pub(all) struct GlyphDraw {
  atlas_x : Int
  atlas_y : Int
  atlas_w : Int
  atlas_h : Int
  x : Float
  y : Float
  /// Destination width on the canvas (usually the layout advance).
  w : Float
  /// Destination height on the canvas (usually the font size).
  h : Float
  color : Color
} derive(Debug)

///|
/// CPU-side draw list produced from a `StageView` (no GPU handles).
pub(all) struct DrawList {
  sprites : Array[SpriteDraw]
  glyphs : Array[GlyphDraw]
  veil_opacity : Float
} derive(Debug)

///|
/// Fixed UI geometry for dialogue/nameplate/choices on the logical canvas.
pub(all) struct UiLayout {
  canvas_w : Float
  canvas_h : Float
  /// Dialogue box panel.
  dialogue_x : Float
  dialogue_y : Float
  dialogue_w : Float
  dialogue_h : Float
  /// Speaker nameplate rect (above text area).
  nameplate_x : Float
  nameplate_y : Float
  nameplate_w : Float
  nameplate_h : Float
  /// Dialogue body text origin and wrap width.
  text_x : Float
  text_y : Float
  text_w : Float
  text_h : Float
  /// Choice list origin (above dialogue box).
  choice_x : Float
  choice_y : Float
  choice_w : Float
  choice_line_h : Float
  font_size : Float
  name_font_size : Float
  choice_font_size : Float
  /// Advance used when no host measure is provided.
  default_char_advance : Float
  text_color : Color
  name_color : Color
  choice_color : Color
} derive(Debug)

///|
/// Default layout for 1920×1080: dialogue box occupies the bottom 30%.
pub fn UiLayout::default_fhd() -> UiLayout {
  let canvas_w : Float = 1920.0
  let canvas_h : Float = 1080.0
  let dialogue_h : Float = canvas_h * 0.3
  let dialogue_y : Float = canvas_h - dialogue_h
  let margin : Float = 48.0
  let pad : Float = 32.0
  let nameplate_h : Float = 48.0
  let font_size : Float = 32.0
  {
    canvas_w,
    canvas_h,
    dialogue_x: margin,
    dialogue_y,
    dialogue_w: canvas_w - margin * 2.0,
    dialogue_h,
    nameplate_x: margin + pad,
    nameplate_y: dialogue_y + pad,
    nameplate_w: 360.0,
    nameplate_h,
    text_x: margin + pad,
    text_y: dialogue_y + pad + nameplate_h + 12.0,
    text_w: canvas_w - margin * 2.0 - pad * 2.0,
    text_h: dialogue_h - pad * 2.0 - nameplate_h - 12.0,
    choice_x: margin + pad,
    choice_y: dialogue_y - 200.0,
    choice_w: canvas_w - margin * 2.0 - pad * 2.0,
    choice_line_h: 48.0,
    font_size,
    name_font_size: 28.0,
    choice_font_size: 30.0,
    // Hint for hosts; layout prefers approximate_measure(font_size).
    default_char_advance: font_size * 0.55,
    text_color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
    name_color: { r: 1.0, g: 0.92, b: 0.7, a: 1.0 },
    choice_color: { r: 0.85, g: 0.95, b: 1.0, a: 1.0 },
  }
}

///|
/// White opaque color helper.
pub fn Color::white() -> Color {
  { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }
}

///|
/// Black with given alpha (veil helper).
pub fn Color::black_a(a : Float) -> Color {
  { r: 0.0, g: 0.0, b: 0.0, a }
}
