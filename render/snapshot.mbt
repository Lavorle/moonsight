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
/// Full-screen semi-transparent dim under system menus.
pub let ui_menu_dim : String = "ui.menu_dim"

///|
/// UI button panel (unfocused).
pub let ui_button : String = "ui.button"

///|
/// UI button panel (focused — brighter host placeholder).
pub let ui_button_focus : String = "ui.button_focus"

///|
/// Convert a read-only stage snapshot into a GPU-agnostic draw list.
///
/// - Visible layers → `SpriteDraw` (full-canvas size Phase 1).
/// - Optional `ui_ops` → sprites + glyph expansion from `UiDrawOp` (modal/HUD).
/// - Dialogue / menus are **not** derived from `StageView.text` / choices —
///   only from `ui_ops` produced by `UiRuntime.paint_*`.
/// - Allocates a throwaway `GlyphAtlas` for UV packing (UVs are real shelf
///   coords, not zeros). Host frame loops must use `build_draw_list_with_atlas`
///   with a long-lived atlas so pending rasterization / `mark_ready` stay
///   coherent across frames.
pub fn build_draw_list(
  view : @runtime.StageView,
  layout : UiLayout,
  ui_ops? : Array[@runtime.UiDrawOp],
) -> DrawList {
  let atlas = GlyphAtlas::new()
  build_draw_list_with_atlas(view, layout, atlas, ui_ops?)
}

///|
/// Like `build_draw_list` but reuses a shared glyph atlas for UV bookkeeping.
///
/// When `measure` is omitted, each text run uses `approximate_measure(font_size)`
/// for that op's pixel size.
pub fn build_draw_list_with_atlas(
  view : @runtime.StageView,
  layout : UiLayout,
  atlas : GlyphAtlas,
  measure? : (Char) -> Float,
  ui_ops? : Array[@runtime.UiDrawOp],
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

  // UI widgets from runtime paint ops (dim, buttons, panels, text, choices…).
  let ops = match ui_ops {
    Some(a) => a
    None => ([] : Array[@runtime.UiDrawOp])
  }
  for op in ops {
    emit_ui_draw_op(op, sprites, glyphs, atlas, layout, measure?)
  }

  { sprites, glyphs, veil_opacity: Float::from_double(view.overlay_opacity) }
}

///|
/// Emit one `UiDrawOp` as sprite and/or glyphs.
///
/// - `kind == 1` (glyph-run marker): text only, no sprite.
/// - otherwise: textured quad when `resource` is non-empty; optional label text.
fn emit_ui_draw_op(
  op : @runtime.UiDrawOp,
  sprites : Array[SpriteDraw],
  glyphs : Array[GlyphDraw],
  atlas : GlyphAtlas,
  layout : UiLayout,
  measure? : (Char) -> Float,
) -> Unit {
  // kind 1 = pure text; skip empty resource sprites.
  if op.kind != 1 && op.resource.length() > 0 {
    sprites.push({
      resource: op.resource,
      x: op.x,
      y: op.y,
      w: op.w,
      h: op.h,
      opacity: op.opacity,
      z: op.z,
    })
  }
  match op.text {
    None => ()
    Some(label) => {
      if label.length() == 0 {
        return
      }
      let fs = if op.font_size > 0.0 { op.font_size } else { layout.font_size }
      let m = match measure {
        Some(fn_) => fn_
        None => approximate_measure(fs)
      }
      // Buttons/panels pad label inside the rect; bare text ops use op origin.
      let (origin_x, origin_y, max_width) = if op.kind == 1 {
        (op.x, op.y, op.w)
      } else {
        let pad : Float = 16.0
        let mw = if op.w > pad * 2.0 { op.w - pad * 2.0 } else { op.w }
        (op.x + pad, op.y + 10.0, mw)
      }
      emit_text_glyphs(
        glyphs,
        atlas,
        label,
        origin_x~,
        origin_y~,
        max_width~,
        font_size=fs,
        color=layout.text_color,
        measure=m,
      )
    }
  }
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
      // Cell / screen / pen MUST share the same width (avoid glyph overlap).
      let adv_i = adv.to_int()
      // +2px for left bearing; ~1.35em height so a shared baseline can fit
      // both capitals and descenders (g/y/p) without per-glyph vertical shifts.
      let cell_w = if adv_i < 1 { 3 } else { adv_i + 2 }
      // ~1.5em: room for f-like ascenders AND g/y descenders under one baseline
      let cell_h = size + size / 2 + 4
      let entry = atlas.get_or_queue(ch, size, cell_w=cell_w, cell_h=cell_h)
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
