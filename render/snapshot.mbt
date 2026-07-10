///|
/// Logical resource id for the dialogue panel sprite.
pub let ui_dialogue_box : String = "ui.dialogue_box"

///|
/// Logical resource id for the speaker nameplate panel.
pub let ui_nameplate : String = "ui.nameplate"

///|
/// Logical resource id for a choice row highlight/panel.
pub let ui_choice_row : String = "ui.choice_row"

///|
/// Convert a read-only stage snapshot into a GPU-agnostic draw list.
///
/// - Visible layers → `SpriteDraw` (full-canvas size Phase 1).
/// - Dialogue box bottom 30% (via `UiLayout`) + optional nameplate.
/// - Visible typewriter text + choices laid out with fixed advances.
/// - Allocates a throwaway `GlyphAtlas` for UV packing (UVs are real shelf
///   coords, not zeros). Host frame loops must use `build_draw_list_with_atlas`
///   with a long-lived atlas so pending rasterization / `mark_ready` stay
///   coherent across frames.
pub fn build_draw_list(
  view : @runtime.StageView,
  layout : UiLayout,
) -> DrawList {
  let atlas = GlyphAtlas::new()
  build_draw_list_with_atlas(
    view,
    layout,
    atlas,
    measure=approximate_measure(layout.font_size),
  )
}

///|
/// Like `build_draw_list` but reuses a shared glyph atlas for UV bookkeeping.
///
/// When `measure` is omitted, each run uses `approximate_measure(font_size)`
/// for that run's pixel size (name / body / choice sizes stay consistent).
pub fn build_draw_list_with_atlas(
  view : @runtime.StageView,
  layout : UiLayout,
  atlas : GlyphAtlas,
  measure? : (Char) -> Float,
) -> DrawList {
  let sprites : Array[SpriteDraw] = []
  let glyphs : Array[GlyphDraw] = []

  // Layers (already sorted by z in StageView).
  for layer in view.layers {
    if !layer.visible {
      continue
    }
    sprites.push({
      resource: layer.resource,
      x: Float::from_double(layer.x),
      y: Float::from_double(layer.y),
      w: layout.canvas_w,
      h: layout.canvas_h,
      opacity: Float::from_double(layer.opacity),
      z: layer.z,
    })
  }

  // Dialogue chrome when text is active.
  match view.text {
    None => ()
    Some(block) => {
      let ui_z = 1000
      sprites.push({
        resource: ui_dialogue_box,
        x: layout.dialogue_x,
        y: layout.dialogue_y,
        w: layout.dialogue_w,
        h: layout.dialogue_h,
        opacity: 1.0,
        z: ui_z,
      })
      match block.speaker {
        None => ()
        Some(name) => {
          sprites.push({
            resource: ui_nameplate,
            x: layout.nameplate_x,
            y: layout.nameplate_y,
            w: layout.nameplate_w,
            h: layout.nameplate_h,
            opacity: 1.0,
            z: ui_z + 1,
          })
          let m_name = match measure {
            Some(m) => m
            None => approximate_measure(layout.name_font_size)
          }
          emit_text_glyphs(
            glyphs,
            atlas,
            name,
            origin_x=layout.nameplate_x + 12.0,
            origin_y=layout.nameplate_y + 8.0,
            max_width=layout.nameplate_w - 24.0,
            font_size=layout.name_font_size,
            color=layout.name_color,
            measure=m_name,
          )
        }
      }
      let body = visible_prefix(block.full_text, block.visible_chars)
      let m_body = match measure {
        Some(m) => m
        None => approximate_measure(layout.font_size)
      }
      emit_text_glyphs(
        glyphs,
        atlas,
        body,
        origin_x=layout.text_x,
        origin_y=layout.text_y,
        max_width=layout.text_w,
        font_size=layout.font_size,
        color=layout.text_color,
        measure=m_body,
      )
    }
  }

  // Choices (above dialogue box).
  match view.choices {
    None => ()
    Some(ch) => {
      let ui_z = 1100
      let mut i = 0
      while i < ch.options.length() {
        let label = ch.options[i]
        let row_y = layout.choice_y + Float::from_int(i) * layout.choice_line_h
        sprites.push({
          resource: ui_choice_row,
          x: layout.choice_x,
          y: row_y,
          w: layout.choice_w,
          h: layout.choice_line_h - 8.0,
          opacity: 0.85,
          z: ui_z,
        })
        let m_choice = match measure {
          Some(m) => m
          None => approximate_measure(layout.choice_font_size)
        }
        emit_text_glyphs(
          glyphs,
          atlas,
          label,
          origin_x=layout.choice_x + 16.0,
          origin_y=row_y + 8.0,
          max_width=layout.choice_w - 32.0,
          font_size=layout.choice_font_size,
          color=layout.choice_color,
          measure=m_choice,
        )
        i = i + 1
      }
    }
  }

  { sprites, glyphs, veil_opacity: Float::from_double(view.overlay_opacity) }
}

///|
/// Layout `text` and push non-whitespace glyph quads into `glyphs`.
///
/// Atlas cells are proportional rectangles: width ≈ advance + pad, height =
/// font size. Screen quads use the same advance × font size so pitch matches
/// the pen. Host stamps outlines (Slug-style) or bitmaps into each cell.
fn emit_text_glyphs(
  glyphs : Array[GlyphDraw],
  atlas : GlyphAtlas,
  text : String,
  origin_x~ : Float,
  origin_y~ : Float,
  max_width~ : Float,
  font_size~ : Float,
  color~ : Color,
  measure~ : (Char) -> Float,
) -> Unit {
  if text.length() == 0 {
    return
  }
  let size_px = font_size.to_int()
  let size = if size_px < 1 { 1 } else { size_px }
  let runs = layout_text(text, max_width~, font_size~, measure~)
  for run in runs {
    let mut pen_x = origin_x + run.x
    let pen_y = origin_y + run.y
    for ch in run.text {
      let adv = measure(ch)
      if ch == ' ' || ch == '\t' {
        pen_x = pen_x + adv
        continue
      }
      // Cell / screen / pen MUST share the same width. If screen_w > pen advance,
      // glyphs overlap and middle letters vanish (was: "Talk" → "T l").
      let adv_i = adv.to_int()
      let cell_w = if adv_i < 1 { 2 } else { adv_i + 1 }
      let entry = atlas.get_or_queue(ch, size, cell_w=cell_w)
      let sw = Float::from_int(entry.atlas_w)
      let sh = Float::from_int(entry.atlas_h)
      glyphs.push({
        atlas_x: entry.atlas_x,
        atlas_y: entry.atlas_y,
        atlas_w: entry.atlas_w,
        atlas_h: entry.atlas_h,
        x: pen_x,
        y: pen_y,
        w: sw,
        h: sh,
        color,
      })
      pen_x = pen_x + sw
    }
  }
}
