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
/// Screen DSL button panel (unfocused).
pub let ui_button : String = "ui.button"

///|
/// Screen DSL button panel (focused — brighter host placeholder).
pub let ui_button_focus : String = "ui.button_focus"

///|
/// Convert a read-only stage snapshot into a GPU-agnostic draw list.
///
/// - Visible layers → `SpriteDraw` (full-canvas size Phase 1).
/// - Dialogue box bottom 30% (via `UiLayout`) + optional nameplate.
/// - Visible typewriter text + choices laid out with fixed advances.
/// - Optional `screens` → menu dim + top screen widgets (skip dialogue when
///   Title or stack non-empty).
/// - Allocates a throwaway `GlyphAtlas` for UV packing (UVs are real shelf
///   coords, not zeros). Host frame loops must use `build_draw_list_with_atlas`
///   with a long-lived atlas so pending rasterization / `mark_ready` stay
///   coherent across frames.
pub fn build_draw_list(
  view : @runtime.StageView,
  layout : UiLayout,
  screens? : @runtime.ScreenState,
) -> DrawList {
  let atlas = GlyphAtlas::new()
  build_draw_list_with_atlas(
    view,
    layout,
    atlas,
    measure=approximate_measure(layout.font_size),
    screens?,
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
  screens? : @runtime.ScreenState,
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

  // Dialogue / choices only while Playing with an empty screen stack.
  let show_dialogue = match screens {
    None => true
    Some(ss) =>
      match ss.mode {
        @runtime.UiMode::Title => false
        @runtime.UiMode::Menu => false
        @runtime.UiMode::Playing => ss.stack.is_empty()
      }
  }

  if show_dialogue {
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
  }

  // Active screen stack (top only): dim under Menu + widget tree.
  match screens {
    None => ()
    Some(ss) => {
      if !ss.stack.is_empty() {
        if ss.mode is @runtime.UiMode::Menu {
          sprites.push({
            resource: ui_menu_dim,
            x: 0.0,
            y: 0.0,
            w: layout.canvas_w,
            h: layout.canvas_h,
            opacity: layout.screen_dim_opacity,
            z: 2000,
          })
        }
        let top = ss.stack[ss.stack.length() - 1]
        match ss.defs.get(top.name) {
          None => ()
          Some(def) => {
            let m_screen = match measure {
              Some(m) => m
              None => approximate_measure(layout.screen_font_size)
            }
            let btn_counter : Array[Int] = [0]
            ignore(
              emit_screen_node(
                def.root,
                layout.screen_origin_x,
                layout.screen_origin_y,
                sprites,
                glyphs,
                atlas,
                layout,
                ss.prefs,
                top.focus,
                btn_counter,
                measure=m_screen,
              ),
            )
          }
        }
      }
    }
  }

  { sprites, glyphs, veil_opacity: Float::from_double(view.overlay_opacity) }
}

///|
/// Mutable button walk index (length-1 array) shared across the tree walk.
///
/// Returns `(advance_w, advance_h)` consumed for the parent vbox/hbox step.
fn emit_screen_node(
  node : @script.SNode,
  origin_x : Float,
  origin_y : Float,
  sprites : Array[SpriteDraw],
  glyphs : Array[GlyphDraw],
  atlas : GlyphAtlas,
  layout : UiLayout,
  prefs : @runtime.Prefs,
  focus : Int,
  btn_counter : Array[Int],
  measure~ : (Char) -> Float,
) -> (Float, Float) {
  match node {
    @script.SNode::VBox(x~, y~, children~) => {
      let ox = opt_xy(x, origin_x)
      let oy = opt_xy(y, origin_y)
      let mut cy = oy
      let mut max_w : Float = 0.0
      for c in children {
        let (w, h) = emit_screen_node(
          c,
          ox,
          cy,
          sprites,
          glyphs,
          atlas,
          layout,
          prefs,
          focus,
          btn_counter,
          measure~,
        )
        if w > max_w {
          max_w = w
        }
        cy = cy + h
      }
      let total_h = cy - oy
      let zero : Float = 0.0
      (max_w, if total_h > zero { total_h } else { layout.screen_line_h })
    }
    @script.SNode::HBox(x~, y~, children~) => {
      let ox = opt_xy(x, origin_x)
      let oy = opt_xy(y, origin_y)
      let mut cx = ox
      let mut max_h : Float = 0.0
      for c in children {
        let (w, h) = emit_screen_node(
          c,
          cx,
          oy,
          sprites,
          glyphs,
          atlas,
          layout,
          prefs,
          focus,
          btn_counter,
          measure~,
        )
        if h > max_h {
          max_h = h
        }
        cx = cx + w
      }
      let total_w = cx - ox
      let zero : Float = 0.0
      (if total_w > zero { total_w } else { layout.screen_button_w }, max_h)
    }
    @script.SNode::Fixed(x~, y~, children~, ..) => {
      let ox = Float::from_double(x)
      let oy = Float::from_double(y)
      let mut cy = oy
      for c in children {
        let (_w, h) = emit_screen_node(
          c,
          ox,
          cy,
          sprites,
          glyphs,
          atlas,
          layout,
          prefs,
          focus,
          btn_counter,
          measure~,
        )
        cy = cy + h
      }
      // Fixed does not advance the parent cursor (absolute overlay).
      let zero : Float = 0.0
      (zero, zero)
    }
    @script.SNode::Text(src) => {
      let label = resolve_screen_text(src, prefs)
      emit_text_glyphs(
        glyphs,
        atlas,
        label,
        origin_x=origin_x + 8.0,
        origin_y=origin_y + 8.0,
        max_width=layout.screen_button_w - 16.0,
        font_size=layout.screen_font_size,
        color=layout.screen_text_color,
        measure~,
      )
      (layout.screen_button_w, layout.screen_line_h)
    }
    @script.SNode::Button(label~, ..) => {
      let idx = btn_counter[0]
      btn_counter[0] = idx + 1
      let focused = idx == focus
      let res = if focused { ui_button_focus } else { ui_button }
      let opacity : Float = if focused { 1.0 } else { 0.75 }
      sprites.push({
        resource: res,
        x: origin_x,
        y: origin_y,
        w: layout.screen_button_w,
        h: layout.screen_button_h,
        opacity,
        z: 2100,
      })
      emit_text_glyphs(
        glyphs,
        atlas,
        label,
        origin_x=origin_x + 16.0,
        origin_y=origin_y + 10.0,
        max_width=layout.screen_button_w - 32.0,
        font_size=layout.screen_font_size,
        color=layout.screen_text_color,
        measure~,
      )
      (layout.screen_button_w, layout.screen_line_h)
    }
  }
}

///|
fn opt_xy(v : Double?, fallback : Float) -> Float {
  match v {
    Some(d) => Float::from_double(d)
    None => fallback
  }
}

///|
/// Resolve screen text bindings for draw (slot labels are placeholders without
/// save blobs; prefs format current values).
fn resolve_screen_text(src : @script.ScreenText, prefs : @runtime.Prefs) -> String {
  match src {
    @script.ScreenText::Literal(s) => s
    @script.ScreenText::SlotLabel(i) => "Slot \{i}"
    @script.ScreenText::Pref(key) => format_pref(prefs, key)
  }
}

///|
fn format_pref(prefs : @runtime.Prefs, key : String) -> String {
  match key {
    "text_speed" => "\{prefs.text_speed}"
    "auto_mode" => if prefs.auto_mode { "on" } else { "off" }
    "master_volume" => "\{prefs.master_volume}"
    "bgm_volume" => "\{prefs.bgm_volume}"
    "se_volume" => "\{prefs.se_volume}"
    _ => key
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
