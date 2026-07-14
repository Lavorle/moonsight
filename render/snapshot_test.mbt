///|
fn test_view_with_layer() -> @runtime.StageView {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="bg",
    layer=@runtime.LayerKind::Background,
    resource="bg_room",
    z=0,
  )
  st.show_layer(
    id="hero",
    layer=@runtime.LayerKind::Character,
    resource="char_y",
    z=10,
    x=200.0,
    y=0.0,
    opacity=0.9,
  )
  st.begin_text(speaker="Y")
  st.type_more("Hello world from MoonSight")
  st.complete_text()
  st.overlay_opacity = 0.25
  @runtime.StageView::from_stage(st, wait=@runtime.WaitKind::Yield, auto=false)
}

///|
/// Sample dialogue chrome ops (geometry formerly hard-coded in UiLayout).
fn dialogue_ops(
  layout : UiLayout,
  speaker : String?,
  body : String,
) -> Array[@runtime.UiDrawOp] {
  let margin : Float = 48.0
  let pad : Float = 32.0
  let dialogue_h = layout.canvas_h * 0.3
  let dialogue_y = layout.canvas_h - dialogue_h
  let dialogue_x = margin
  let dialogue_w = layout.canvas_w - margin * 2.0
  let nameplate_h : Float = 48.0
  let ops : Array[@runtime.UiDrawOp] = []
  ops.push({
    kind: 0,
    resource: ui_dialogue_box,
    x: dialogue_x,
    y: dialogue_y,
    w: dialogue_w,
    h: dialogue_h,
    opacity: 1.0,
    z: 1000,
    text: None,
    font_size: 0.0,
    focused: false,
    hovered: false,
  })
  match speaker {
    None => ()
    Some(name) =>
      ops.push({
        kind: 0,
        resource: ui_nameplate,
        x: margin + pad,
        y: dialogue_y + pad,
        w: 360.0,
        h: nameplate_h,
        opacity: 1.0,
        z: 1001,
        text: Some(name),
        font_size: 28.0,
        focused: false,
        hovered: false,
      })
  }
  ops.push({
    kind: 1,
    resource: "",
    x: margin + pad,
    y: dialogue_y + pad + nameplate_h + 12.0,
    w: layout.canvas_w - margin * 2.0 - pad * 2.0,
    h: dialogue_h - pad * 2.0 - nameplate_h - 12.0,
    opacity: 1.0,
    z: 1002,
    text: Some(body),
    font_size: layout.font_size,
    focused: false,
    hovered: false,
  })
  ops
}

///|
test "build_draw_list emits layer sprites and veil" {
  let view = test_view_with_layer()
  let layout = UiLayout::default_fhd()
  let ops = dialogue_ops(layout, Some("Y"), "Hello world from MoonSight")
  let dl = build_draw_list(view, layout, ui_ops=ops)
  assert_eq(dl.veil_opacity, 0.25)
  // bg + hero + dialogue box + nameplate
  assert_true(dl.sprites.length() >= 4)
  assert_eq(dl.sprites[0].resource, "bg_room")
  assert_eq(dl.sprites[1].resource, "char_y")
  assert_eq(dl.sprites[1].x, 200.0)
  assert_eq(dl.sprites[1].opacity, 0.9)
  // dialogue chrome from ui ops
  let mut has_box = false
  let mut has_plate = false
  for s in dl.sprites {
    if s.resource == ui_dialogue_box {
      has_box = true
      assert_eq(s.y, layout.canvas_h * 0.7)
      assert_eq(s.h, layout.canvas_h * 0.3)
    }
    if s.resource == ui_nameplate {
      has_plate = true
    }
  }
  assert_true(has_box)
  assert_true(has_plate)
  // glyphs for speaker + body
  assert_true(dl.glyphs.length() > 0)
}

///|
test "dialogue box not emitted without ui draw ops" {
  let st = @runtime.Stage::new()
  st.begin_text(speaker="Hero")
  st.type_more("Hello")
  st.complete_text()
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Yield,
    auto=false,
  )
  let dl = build_draw_list(view, UiLayout::default_fhd(), ui_ops=[])
  let mut has_dialogue = false
  for s in dl.sprites {
    if s.resource == ui_dialogue_box {
      has_dialogue = true
    }
  }
  assert_false(has_dialogue)
  // Stage text alone must not produce glyphs either.
  assert_eq(dl.glyphs.length(), 0)
}

///|
test "ui draw ops emit button sprite and glyphs" {
  let st = @runtime.Stage::new()
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Halted,
    auto=false,
  )
  let layout = UiLayout::default_fhd()
  let ops : Array[@runtime.UiDrawOp] = [
    {
      kind: 0,
      resource: ui_button,
      x: 10.0,
      y: 20.0,
      w: 400.0,
      h: 52.0,
      opacity: 1.0,
      z: 3000,
      text: Some("Start"),
      font_size: 30.0,
      focused: false,
      hovered: false,
    },
  ]
  let dl = build_draw_list(view, layout, ui_ops=ops)
  assert_true(dl.sprites.length() >= 1)
  assert_eq(dl.sprites[0].resource, ui_button)
  assert_eq(dl.sprites[0].x, 10.0)
  assert_eq(dl.sprites[0].y, 20.0)
  // "Start" → 5 glyphs
  assert_eq(dl.glyphs.length(), 5)
}

///|
test "canvas metrics default_fhd" {
  let layout = UiLayout::default_fhd()
  assert_eq(layout.canvas_w, 1920.0)
  assert_eq(layout.canvas_h, 1080.0)
  assert_eq(layout.font_size, 32.0)
  assert_true(layout.default_char_advance > 0.0)
}

///|
test "typewriter only lays out visible chars via ui ops" {
  let st = @runtime.Stage::new()
  st.begin_text()
  st.type_more("ABCDEFGH")
  // leave incomplete with 3 visible
  match st.text {
    Some(t) => st.text = Some({ ..t, visible_chars: 3, complete: false })
    None => fail("text")
  }
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Yield,
    auto=false,
  )
  let atlas = GlyphAtlas::new()
  let layout = UiLayout::default_fhd()
  // Only the visible prefix is placed into the draw op (HUD responsibility).
  let ops = dialogue_ops(layout, None, "ABC")
  let dl = build_draw_list_with_atlas(
    view,
    layout,
    atlas,
    measure=fixed_width_measure(10.0),
    ui_ops=ops,
  )
  // Only "ABC" → 3 glyphs (no speaker) + dialogue panel sprite
  assert_eq(dl.glyphs.length(), 3)
}

///|
test "choices emit rows and glyphs from ui ops" {
  let st = @runtime.Stage::new()
  st.set_choices(["Yes", "No"])
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Choose,
    auto=false,
  )
  let layout = UiLayout::default_fhd()
  let ops : Array[@runtime.UiDrawOp] = []
  ops.push({
    kind: 0,
    resource: ui_choice_row,
    x: 100.0,
    y: 400.0,
    w: 500.0,
    h: 40.0,
    opacity: 1.0,
    z: 1100,
    text: Some("Yes"),
    font_size: 30.0,
    focused: true,
    hovered: false,
  })
  ops.push({
    kind: 0,
    resource: ui_choice_row,
    x: 100.0,
    y: 448.0,
    w: 500.0,
    h: 40.0,
    opacity: 0.65,
    z: 1100,
    text: Some("No"),
    font_size: 30.0,
    focused: false,
    hovered: false,
  })
  let dl = build_draw_list(view, layout, ui_ops=ops)
  let mut rows = 0
  for s in dl.sprites {
    if s.resource == ui_choice_row {
      rows = rows + 1
    }
  }
  assert_eq(rows, 2)
  assert_true(dl.glyphs.length() >= 5) // Yes + No
}

///|
test "hidden layers are skipped" {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="bg",
    layer=@runtime.LayerKind::Background,
    resource="bg",
    z=0,
  )
  st.layers[0] = {
    id: "bg",
    kind: @runtime.LayerKind::Background,
    resource: "bg",
    z: 0,
    x: 0.0,
    y: 0.0,
    opacity: 1.0,
    scale: 1.0,
    visible: false,
    tweens: [],
    pending_hide: false,
  }
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Halted,
    auto=false,
  )
  let dl = build_draw_list(view, UiLayout::default_fhd())
  assert_eq(dl.sprites.length(), 0)
}

///|
test "build_draw_list multiplies layer size by scale" {
  // StageView layer scale=0.5 → sprite w,h == layout.canvas_* * 0.5
  let st = @runtime.Stage::new()
  st.show_layer(
    id="hero",
    layer=@runtime.LayerKind::Character,
    resource="char_y",
    z=10,
    x=100.0,
    y=50.0,
  )
  st.layers[0] = {
    id: "hero",
    kind: @runtime.LayerKind::Character,
    resource: "char_y",
    z: 10,
    x: 100.0,
    y: 50.0,
    opacity: 1.0,
    scale: 0.5,
    visible: true,
    tweens: [],
    pending_hide: false,
  }
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Halted,
    auto=false,
  )
  let layout = UiLayout::default_fhd()
  let dl = build_draw_list(view, layout)
  assert_eq(dl.sprites.length(), 1)
  assert_eq(dl.sprites[0].resource, "char_y")
  assert_eq(dl.sprites[0].x, 100.0)
  assert_eq(dl.sprites[0].y, 50.0)
  assert_eq(dl.sprites[0].w, layout.canvas_w * 0.5)
  assert_eq(dl.sprites[0].h, layout.canvas_h * 0.5)
}

///|
test "glyph atlas queues missing and reuses entries" {
  let atlas = GlyphAtlas::new(width=64, height=64)
  let a1 = atlas.get_or_queue('A', 16)
  let a2 = atlas.get_or_queue('A', 16)
  assert_eq(a1.atlas_x, a2.atlas_x)
  assert_eq(a1.atlas_y, a2.atlas_y)
  assert_true(a1.pending)
  assert_eq(atlas.pending_queue.length(), 1)
  let b = atlas.get_or_queue('B', 16)
  assert_true(b.atlas_x != a1.atlas_x || b.atlas_y != a1.atlas_y)
  atlas.mark_ready(
    'A',
    16,
    atlas_x=a1.atlas_x,
    atlas_y=a1.atlas_y,
    atlas_w=16,
    atlas_h=16,
  )
  assert_true(atlas.contains('A', 16))
  assert_true(!atlas.contains('B', 16))
  let pending = atlas.take_pending()
  // 'A' removed by mark_ready; 'B' remains until take
  assert_eq(pending.length(), 1)
  let (ch, sz) = pending[0]
  assert_eq(ch, 'B')
  assert_eq(sz, 16)
}

///|
/// Nested keys must keep CJK codepoints distinct from ASCII and from each
/// other at different sizes (old packed Int key overflowed for cp ≥ 0x8000).
test "glyph atlas CJK keys are distinct from ASCII and by size" {
  let atlas = GlyphAtlas::new(width=256, height=256)
  let cjk16 = atlas.get_or_queue('这', 16)
  let cjk32 = atlas.get_or_queue('这', 32)
  let ascii16 = atlas.get_or_queue('A', 16)
  // Distinct slots for (这,16), (这,32), (A,16).
  assert_eq(cjk16.atlas_w, 16)
  assert_eq(cjk16.atlas_h, 16)
  assert_eq(cjk32.atlas_w, 32)
  assert_eq(cjk32.atlas_h, 32)
  assert_eq(ascii16.atlas_w, 16)
  assert_true(cjk16.atlas_x != cjk32.atlas_x || cjk16.atlas_y != cjk32.atlas_y)
  assert_true(
    cjk16.atlas_x != ascii16.atlas_x || cjk16.atlas_y != ascii16.atlas_y,
  )
  // Reuse must hit the same entry (no wrap collision with ASCII).
  let cjk16b = atlas.get_or_queue('这', 16)
  assert_eq(cjk16b.atlas_x, cjk16.atlas_x)
  assert_eq(cjk16b.atlas_y, cjk16.atlas_y)
  assert_eq(atlas.pending_queue.length(), 3)
  atlas.mark_ready(
    '这',
    16,
    atlas_x=cjk16.atlas_x,
    atlas_y=cjk16.atlas_y,
    atlas_w=16,
    atlas_h=16,
  )
  assert_true(atlas.contains('这', 16))
  assert_true(!atlas.contains('这', 32))
  assert_true(!atlas.contains('A', 16))
}

///|
/// Cell larger than current atlas but ≤ MAX grows the square atlas (H4).
test "glyph atlas oversized cell grows when under MAX" {
  let atlas = GlyphAtlas::new(width=32, height=32)
  let g0 = atlas.generation
  let e = atlas.get_or_queue('X', 64)
  assert_eq(e.atlas_w, 64)
  assert_eq(e.atlas_h, 64)
  assert_true(e.pending)
  assert_true(atlas.width >= 64)
  assert_true(atlas.height >= 64)
  assert_true(atlas.generation > g0)
  let e2 = atlas.get_or_queue('X', 64)
  assert_eq(e2.atlas_x, e.atlas_x)
  assert_eq(e2.atlas_y, e.atlas_y)
}

///|
test "H4 shelf overflow grows atlas and bumps generation" {
  let atlas = GlyphAtlas::new(width=64, height=64)
  let g0 = atlas.generation
  // Fill with many 32x32 cells until shelf would overflow old size.
  for i in 0..<8 {
    let ch = (0x41 + i).unsafe_to_char() // 'A'..
    let _ = atlas.get_or_queue(ch, 32, cell_w=32, cell_h=32)
  }
  assert_true(atlas.width >= 128 || atlas.height >= 128)
  assert_true(atlas.generation > g0)
}

///|
/// After grow/repack, early glyphs must keep positive cells within atlas bounds
/// so the host can re-upload valid UVs (not zeroed / out-of-bounds slots).
test "H4 grow repacks early glyphs with valid UVs" {
  let atlas = GlyphAtlas::new(width=64, height=64)
  for i in 0..<8 {
    let ch = (0x41 + i).unsafe_to_char()
    let _ = atlas.get_or_queue(ch, 32, cell_w=32, cell_h=32)
  }
  assert_true(atlas.width >= 128)
  for i in 0..<8 {
    let ch = (0x41 + i).unsafe_to_char()
    let e = atlas.get_or_queue(ch, 32, cell_w=32, cell_h=32)
    assert_true(e.atlas_w > 0)
    assert_true(e.atlas_h > 0)
    assert_true(e.atlas_x >= 0)
    assert_true(e.atlas_y >= 0)
    assert_true(e.atlas_x + e.atlas_w <= atlas.width)
    assert_true(e.atlas_y + e.atlas_h <= atlas.height)
  }
}

///|
test "H4 cell larger than MAX is terminal non-pending" {
  let atlas = GlyphAtlas::new(width=64, height=64)
  let e = atlas.get_or_queue('Z', 64, cell_w=5000, cell_h=5000)
  assert_eq(e.atlas_w, 0)
  assert_eq(e.atlas_h, 0)
  assert_true(!e.pending)
  let e2 = atlas.get_or_queue('Z', 64, cell_w=5000, cell_h=5000)
  assert_true(!e2.pending)
  // Terminal must not sit on pending_queue at all
  assert_eq(atlas.pending_queue.length(), 0)
}

///|
test "paint_modal ops emit buttons and glyphs" {
  let app = @runtime.UiApp::new()
  app.register_modal(
    "test_menu",
    @runtime.UiNode::VBox(x=Some(100.0), y=Some(200.0), children=[
      @runtime.UiNode::Button(
        label="One",
        action_id=0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::Button(
        label="Two",
        action_id=1,
        visible=@runtime.VisiblePred::Always,
      ),
    ]),
  )
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("test_menu")
  let ops = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=@runtime.UiBindCtx::empty(),
  )
  let st = @runtime.Stage::new()
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Halted,
    auto=false,
  )
  let dl = build_draw_list(view, UiLayout::default_fhd(), ui_ops=ops)
  let mut buttons = 0
  let mut focus_buttons = 0
  for s in dl.sprites {
    if s.resource == ui_button || s.resource == ui_button_focus {
      buttons = buttons + 1
    }
    if s.resource == ui_button_focus {
      focus_buttons = focus_buttons + 1
    }
  }
  assert_true(buttons >= 2)
  assert_eq(focus_buttons, 1)
  // "One" + "Two" → at least 2 glyph quads
  assert_true(dl.glyphs.length() >= 2)
}

///|
test "menu mode paint_modal dims without dialogue from stage" {
  let st = @runtime.Stage::new()
  st.begin_text(speaker="Y")
  st.type_more("Hello hidden")
  st.complete_text()
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Yield,
    auto=false,
  )
  let app = @runtime.UiApp::new()
  app.register_modal(
    "game_menu",
    @runtime.UiNode::Button(
      label="Back",
      action_id=0,
      visible=@runtime.VisiblePred::Always,
    ),
  )
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.mode = @runtime.UiMode::Playing
  rt.show_modal("game_menu")
  assert_true(rt.mode is @runtime.UiMode::Menu)
  let ops = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=@runtime.UiBindCtx::empty(),
  )
  // Host paints modal ops only (no HUD dialogue while menu open).
  let layout = UiLayout::default_fhd()
  let dl = build_draw_list(view, layout, ui_ops=ops)
  let mut has_dim = false
  let mut has_dialogue = false
  for s in dl.sprites {
    if s.resource == ui_menu_dim {
      has_dim = true
      assert_eq(s.w, layout.canvas_w)
      assert_eq(s.h, layout.canvas_h)
    }
    if s.resource == ui_dialogue_box {
      has_dialogue = true
    }
  }
  assert_true(has_dim)
  assert_true(!has_dialogue)
}

///|
test "title root modal has no dim" {
  let st = @runtime.Stage::new()
  st.begin_text()
  st.type_more("No title dialogue")
  st.complete_text()
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Yield,
    auto=false,
  )
  let app = @runtime.UiApp::new()
  app.register_modal(
    "title",
    @runtime.UiNode::VBox(x=Some(0.0), y=Some(0.0), children=[
      @runtime.UiNode::Button(
        label="One",
        action_id=0,
        visible=@runtime.VisiblePred::Always,
      ),
      @runtime.UiNode::Button(
        label="Two",
        action_id=1,
        visible=@runtime.VisiblePred::Always,
      ),
    ]),
  )
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("title")
  assert_true(rt.mode is @runtime.UiMode::Title)
  let ops = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=@runtime.UiBindCtx::empty(),
  )
  let dl = build_draw_list(view, UiLayout::default_fhd(), ui_ops=ops)
  let mut has_dim = false
  let mut has_dialogue = false
  let mut buttons = 0
  for s in dl.sprites {
    if s.resource == ui_menu_dim {
      has_dim = true
    }
    if s.resource == ui_dialogue_box {
      has_dialogue = true
    }
    if s.resource == ui_button || s.resource == ui_button_focus {
      buttons = buttons + 1
    }
  }
  assert_true(!has_dim)
  assert_true(!has_dialogue)
  assert_true(buttons >= 2)
}

///|
test "nested title modal dims via paint_modal" {
  let st = @runtime.Stage::new()
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Running,
    auto=false,
  )
  let app = @runtime.UiApp::new()
  app.register_modal(
    "title_like",
    @runtime.UiNode::Button(
      label="One",
      action_id=0,
      visible=@runtime.VisiblePred::Always,
    ),
  )
  app.register_modal(
    "nested",
    @runtime.UiNode::Button(
      label="Two",
      action_id=1,
      visible=@runtime.VisiblePred::Always,
    ),
  )
  let rt = @runtime.UiRuntime::from_app(app, save_slots=6)
  rt.show_modal("title_like")
  rt.show_modal("nested")
  assert_true(rt.mode is @runtime.UiMode::Title)
  assert_eq(rt.stack_depth(), 2)
  let ops = rt.paint_modal(
    canvas_w=1920.0,
    canvas_h=1080.0,
    bind=@runtime.UiBindCtx::empty(),
  )
  let dl = build_draw_list(view, UiLayout::default_fhd(), ui_ops=ops)
  let mut has_dim = false
  for s in dl.sprites {
    if s.resource == ui_menu_dim {
      has_dim = true
    }
  }
  assert_true(has_dim)
}
