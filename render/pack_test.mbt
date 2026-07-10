///|
test "resource table interns stable ids" {
  let t = ResourceTable::new()
  assert_eq(t.intern(""), 0)
  let a = t.intern("bg/school")
  let b = t.intern("ui.dialogue_box")
  assert_eq(t.intern("bg/school"), a)
  assert_true(a != b)
  assert_eq(t.name_of(a), "bg/school")
  assert_eq(t.name_of(b), "ui.dialogue_box")
  assert_eq(t.count(), 3)
}

///|
test "pack sprites and glyphs strides" {
  let resources = ResourceTable::new()
  let sprites : Array[SpriteDraw] = [
    {
      resource: "hero",
      x: 10.0,
      y: 20.0,
      w: 100.0,
      h: 200.0,
      opacity: 0.5,
      z: 3,
    },
  ]
  let packed = pack_sprites(sprites, resources)
  assert_eq(packed.length(), 1 + sprite_stride)
  assert_eq(packed[0].to_int(), 1)
  assert_eq(packed[1].to_double(), 10.0)
  assert_eq(packed[5].to_double(), 0.5)
  assert_eq(packed[6].to_int(), resources.intern("hero"))
  assert_eq(packed[7].to_int(), 3)

  let glyphs : Array[GlyphDraw] = [
    {
      atlas_x: 1,
      atlas_y: 2,
      atlas_w: 16,
      atlas_h: 16,
      x: 40.0,
      y: 50.0,
      w: 12.0,
      h: 16.0,
      color: { r: 1.0, g: 0.0, b: 0.0, a: 1.0 },
    },
  ]
  let gpack = pack_glyphs(glyphs)
  assert_eq(gpack.length(), 1 + glyph_stride)
  assert_eq(gpack[0].to_int(), 1)
  assert_eq(gpack[1].to_int(), 1)
  assert_eq(gpack[5].to_double(), 40.0)
  assert_eq(gpack[7].to_double(), 12.0)
  assert_eq(gpack[8].to_double(), 16.0)
}

///|
test "pack_draw_list combined header and trailer veil" {
  let resources = ResourceTable::new()
  let list : DrawList = {
    sprites: [
      {
        resource: "bg",
        x: 0.0,
        y: 0.0,
        w: 1920.0,
        h: 1080.0,
        opacity: 1.0,
        z: 0,
      },
    ],
    glyphs: [
      {
        atlas_x: 0,
        atlas_y: 0,
        atlas_w: 32,
        atlas_h: 32,
        x: 100.0,
        y: 200.0,
        w: 19.0,
        h: 32.0,
        color: Color::white(),
      },
    ],
    veil_opacity: 0.25,
  }
  let pack = pack_draw_list(list, resources)
  assert_eq(pack[0].to_double(), pack_version.to_double())
  assert_eq(pack_sprite_count(pack), 1)
  assert_eq(pack_glyph_count(pack), 1)
  assert_eq(pack_veil(pack).to_double(), 0.25)
  let expected_len = pack_header_len + sprite_stride + glyph_stride
  assert_eq(pack.length(), expected_len)
  // First sprite x at header end
  assert_eq(pack[pack_header_len].to_double(), 0.0)
  // First glyph x after sprites (atlas 4 floats, then x)
  let gx = pack_header_len + sprite_stride + 4
  assert_eq(pack[gx].to_double(), 100.0)
  assert_eq(pack[gx + 2].to_double(), 19.0)
}

///|
test "intent code mapping" {
  assert_eq(intent_to_code(intent_from_code(0)), 0)
  assert_eq(intent_to_code(intent_from_code(1)), 1)
  assert_eq(intent_to_code(intent_from_code(4)), 4)
  assert_eq(intent_to_code(intent_from_code(7)), 7)
  assert_eq(intent_to_code(intent_from_code(8)), 8)
  assert_eq(intent_to_code(intent_from_code(9)), 9)
  assert_eq(intent_to_code(intent_from_code(12)), 12)
  match intent_from_code(7) {
    MenuLeft => ()
    _ => fail("expected MenuLeft")
  }
  match intent_from_code(8) {
    MenuRight => ()
    _ => fail("expected MenuRight")
  }
  match intent_from_code(9) {
    OpenBacklog => ()
    _ => fail("expected OpenBacklog")
  }
  match intent_from_code(12) {
    Select(n) => assert_eq(n, 2)
    _ => fail("expected Select(2)")
  }
}

///|
test "build_draw_list then pack is non-empty for layer" {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="bg",
    layer=@runtime.LayerKind::Background,
    resource="bg/demo",
    z=0,
  )
  let view = @runtime.StageView::from_stage(
    st,
    wait=@runtime.WaitKind::Yield,
    auto=false,
  )
  let layout = UiLayout::default_fhd()
  let dl = build_draw_list(view, layout)
  let resources = ResourceTable::new()
  let pack = pack_draw_list(dl, resources)
  assert_true(pack_sprite_count(pack) >= 1)
  assert_true(resources.count() >= 2)
}
