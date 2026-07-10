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
test "build_draw_list emits layer sprites and veil" {
  let view = test_view_with_layer()
  let layout = UiLayout::default_fhd()
  let dl = build_draw_list(view, layout)
  assert_eq(dl.veil_opacity, 0.25)
  // bg + hero + dialogue box + nameplate
  assert_true(dl.sprites.length() >= 4)
  assert_eq(dl.sprites[0].resource, "bg_room")
  assert_eq(dl.sprites[1].resource, "char_y")
  assert_eq(dl.sprites[1].x, 200.0)
  assert_eq(dl.sprites[1].opacity, 0.9)
  // dialogue chrome
  let mut has_box = false
  let mut has_plate = false
  for s in dl.sprites {
    if s.resource == ui_dialogue_box {
      has_box = true
      assert_eq(s.y, layout.dialogue_y)
      assert_eq(s.h, layout.dialogue_h)
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
test "dialogue box occupies bottom 30 percent of 1920x1080" {
  let layout = UiLayout::default_fhd()
  assert_eq(layout.canvas_w, 1920.0)
  assert_eq(layout.canvas_h, 1080.0)
  assert_eq(layout.dialogue_h, 324.0)
  assert_eq(layout.dialogue_y, 756.0)
  assert_true(layout.text_y >= layout.dialogue_y)
  assert_true(layout.text_w > 0.0)
}

///|
test "typewriter only lays out visible chars" {
  let st = @runtime.Stage::new()
  st.begin_text()
  st.type_more("ABCDEFGH")
  // leave incomplete with 3 visible
  match st.text {
    Some(t) =>
      st.text = Some({
        speaker: t.speaker,
        full_text: t.full_text,
        visible_chars: 3,
        complete: false,
      })
    None => fail("text")
  }
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Yield,
    auto=false,
  )
  let atlas = GlyphAtlas::new()
  let layout = UiLayout::default_fhd()
  let dl = build_draw_list_with_atlas(
    view,
    layout,
    atlas,
    measure=fixed_width_measure(10.0),
  )
  // Only "ABC" → 3 glyphs (no speaker)
  assert_eq(dl.glyphs.length(), 3)
}

///|
test "choices emit rows and glyphs" {
  let st = @runtime.Stage::new()
  st.set_choices(["Yes", "No"])
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Choose,
    auto=false,
  )
  let dl = build_draw_list(view, UiLayout::default_fhd())
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
test "glyph atlas oversized cell is zero placeholder" {
  let atlas = GlyphAtlas::new(width=32, height=32)
  let e = atlas.get_or_queue('X', 64)
  assert_eq(e.atlas_w, 0)
  assert_eq(e.atlas_h, 0)
  assert_true(e.pending)
  // Still tracked so re-queue does not allocate again.
  let e2 = atlas.get_or_queue('X', 64)
  assert_eq(e2.atlas_w, 0)
  assert_eq(atlas.pending_queue.length(), 1)
}

///|
fn two_button_def() -> @script.ScreenDef {
  {
    name: "test_menu",
    root: @script.SNode::VBox(
      x=None,
      y=None,
      children=[
        @script.SNode::Button(
          label="One",
          action=@script.ScreenAction::Noop,
        ),
        @script.SNode::Button(
          label="Two",
          action=@script.ScreenAction::Noop,
        ),
      ],
    ),
  }
}

///|
test "screen with two buttons emits quads and glyphs" {
  let st = @runtime.Stage::new()
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Halted,
    auto=false,
  )
  let defs : Map[String, @script.ScreenDef] = { "test_menu": two_button_def() }
  let ss = @runtime.ScreenState::new(defs)
  ss.show("test_menu")
  let layout = UiLayout::default_fhd()
  let dl = build_draw_list(view, layout, screens=ss)
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
test "menu mode dims and skips dialogue" {
  let st = @runtime.Stage::new()
  st.begin_text(speaker="Y")
  st.type_more("Hello hidden")
  st.complete_text()
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Yield,
    auto=false,
  )
  let defs : Map[String, @script.ScreenDef] = { "test_menu": two_button_def() }
  let ss = @runtime.ScreenState::new(defs)
  ss.mode = @runtime.UiMode::Playing
  ss.stack = []
  ss.show("test_menu")
  assert_true(ss.mode is @runtime.UiMode::Menu)
  let layout = UiLayout::default_fhd()
  let dl = build_draw_list(view, layout, screens=ss)
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
test "title mode skips dialogue without dim" {
  let st = @runtime.Stage::new()
  st.begin_text()
  st.type_more("No title dialogue")
  st.complete_text()
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Yield,
    auto=false,
  )
  let defs : Map[String, @script.ScreenDef] = { "test_menu": two_button_def() }
  let ss = @runtime.ScreenState::new(defs)
  // ScreenState::new starts Title; push title-like screen
  ss.show("test_menu")
  assert_true(ss.mode is @runtime.UiMode::Title)
  let dl = build_draw_list(view, UiLayout::default_fhd(), screens=ss)
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
test "nested title modal dims" {
  let st = @runtime.Stage::new()
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Running,
    auto=false,
  )
  let defs : Map[String, @script.ScreenDef] = {
    "title_like": two_button_def(),
    "nested": two_button_def(),
  }
  let ss = @runtime.ScreenState::new(defs)
  ss.show("title_like")
  ss.show("nested")
  assert_true(ss.mode is @runtime.UiMode::Title)
  assert_eq(ss.stack.length(), 2)
  let dl = build_draw_list(view, UiLayout::default_fhd(), screens=ss)
  let mut has_dim = false
  for s in dl.sprites {
    if s.resource == ui_menu_dim {
      has_dim = true
    }
  }
  assert_true(has_dim)
}
