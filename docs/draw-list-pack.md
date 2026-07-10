# Draw-list pack format (Phase 1)

MoonBit owns the CPU draw list (`DrawList`) and packs it into a dense
`FixedArray[Float]` for the browser host. **JS owns WebGPU** via
`globalThis.MoonSightGpu` (`host_web/js_glue/webgpu_bridge.js`).

## Ownership

| Concern | Owner |
|--------|--------|
| Stage / Engine / intents | MoonBit (`runtime`) |
| `DrawList`, glyph atlas UV bookkeeping | MoonBit (`render`) |
| Texture upload, pipelines, submit | JS (`MoonSightGpu`) |
| Save JSON storage keys | JS (`localStorage` `moonsight/save/{slot}`) |

## Combined frame pack (version 1)

Returned conceptually by `export_frame` (stored in host state; JS reads via
`frame_len` / `frame_at` because Wasm-GC arrays are opaque to JS).

```
index 0: version          = 1.0
index 1: sprite_count     (Int as Float)
index 2: glyph_count      (Int as Float)
index 3: veil_opacity     (0..1)
then sprites: sprite_count × 7 floats
then glyphs:  glyph_count  × 10 floats
```

### Sprite record (stride 7)

| offset | field |
|-------:|-------|
| 0 | x |
| 1 | y |
| 2 | w |
| 3 | h |
| 4 | opacity |
| 5 | resId (see resource table) |
| 6 | z |

Coordinates are logical canvas pixels (origin top-left, +y down), default
1920×1080.

### Glyph record (stride 10)

| offset | field |
|-------:|-------|
| 0 | atlas_x (px) |
| 1 | atlas_y (px) |
| 2 | atlas_w (px) |
| 3 | atlas_h (px) |
| 4 | x (canvas) |
| 5 | y (canvas) |
| 6 | r |
| 7 | g |
| 8 | b |
| 9 | a |

Atlas texture id is fixed on the JS side (`atlas` / texture id reserved for
glyphs). MoonBit only emits UV rects; JS rasterizes pending glyphs into the
atlas (see `GlyphAtlas::take_pending` / `mark_ready`).

### Standalone packs

Helpers also exist for tests:

- Sprites: `[count, ...records]`
- Glyphs: `[count, ...records]`

## Resource ids

`ResourceTable` maps resource string keys (e.g. `bg/school`, `ui.dialogue_box`)
to dense positive integers. Id `0` is the empty / missing placeholder
(solid white or clear tint on the JS side).

JS should call `resource_name(id)` after each frame (or when `resource_count`
grows) to resolve paths from `manifest.json`.

## Intent codes

Passed as `Int` into `export_frame(intent_code, dt_ms)`:

| code | intent |
|-----:|--------|
| 0 | None |
| 1 | Advance |
| 2 | SkipTyping |
| 3 | OpenMenu |
| 4 | ToggleAuto |
| 10+n | Select(n) |

`dt_ms` is frame delta in **milliseconds** (converted to seconds inside the host).

## Host wasm exports (`host_web`)

| export | meaning |
|--------|---------|
| `init_demo()` | Boot demo IR + `standard_registry` director |
| `load_source(src)` | Compile MoonYuki source and replace engine |
| `export_frame(intent, dt_ms)` | Tick + pack; returns pack length |
| `frame_len()` | Last pack length |
| `frame_at(i)` | Pack float at index |
| `resource_count()` / `resource_name(id)` | Resource table |
| `save_json(slot)` / `load_json(json)` | Engine save blob (storage is JS) |
| `pending_glyph_*` / `mark_glyph_ready` | Atlas rasterization bridge |

## JS render loop (sketch)

```js
const n = exports.export_frame(intent, dtMs);
const pack = new Float32Array(n);
for (let i = 0; i < n; i++) pack[i] = exports.frame_at(i);
const sc = pack[1] | 0;
const gc = pack[2] | 0;
const veil = pack[3];
const sprites = pack.subarray(4, 4 + sc * 7);
const glyphs = pack.subarray(4 + sc * 7, 4 + sc * 7 + gc * 10);
MoonSightGpu.beginFrame();
MoonSightGpu.drawSprites(sprites);
MoonSightGpu.drawGlyphs(glyphs, "atlas");
MoonSightGpu.drawVeil(veil);
MoonSightGpu.endFrame();
```
