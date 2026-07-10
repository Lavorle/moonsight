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
/// Canvas metrics and default glyph paint settings.
///
/// Dialogue / menu geometry lives in `UiDrawOp` trees (runtime `UiRuntime`),
/// not here. Hosts still pass this for layer full-canvas sizing and fallback
/// font advances when expanding draw-op text to glyphs.
pub(all) struct UiLayout {
  canvas_w : Float
  canvas_h : Float
  /// Fallback body font size when a draw op omits `font_size`.
  font_size : Float
  /// Advance used when no host measure is provided.
  default_char_advance : Float
  /// Default color for glyphs expanded from `UiDrawOp.text`.
  text_color : Color
} derive(Debug)

///|
/// Default layout metrics for a 1920×1080 logical canvas.
pub fn UiLayout::default_fhd() -> UiLayout {
  let canvas_w : Float = 1920.0
  let canvas_h : Float = 1080.0
  let font_size : Float = 32.0
  {
    canvas_w,
    canvas_h,
    font_size,
    // Hint for hosts; layout prefers approximate_measure(font_size).
    default_char_advance: font_size * 0.55,
    text_color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
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
