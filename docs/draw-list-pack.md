# Draw-list pack format (Phase 1–4 + Q1)

MoonBit owns the CPU draw list (`DrawList`) and packs it into a dense
`FixedArray[Float]` for the browser host. **JS owns WebGPU** via
`globalThis.MoonSightGpu` (`apps/host-web/src/adapters/webgpu_bridge.js`).

Player intent codes, `skip_held`, and wait gating: [`play-input.md`](./play-input.md).

## Ownership

| Concern | Owner |
|--------|--------|
| Stage / Engine / intents / UiRuntime | MoonBit (`runtime`) |
| HUD + modals (`std_ui` / project UI) | MoonBit (linked into `host_web` wasm) |
| `DrawList`, glyph atlas UV bookkeeping | MoonBit (`render`) |
| Texture upload, pipelines, submit | JS (`MoonSightGpu`) |
| Save JSON storage keys | JS (`localStorage` `moonsight/save/{slot}`) |
| Prefs storage | JS (`localStorage` `moonsight/prefs`) |

## Combined frame pack (version 1)

Returned conceptually by `export_frame` (stored in host state; JS reads via
`frame_len` / `frame_at` because Wasm-GC arrays are opaque to JS).

```
index 0: version          = 1.0
index 1: sprite_count     (Int as Float)
index 2: glyph_count      (Int as Float)
index 3: veil_opacity     (0..1)
then sprites: sprite_count × 7 floats
then glyphs:  glyph_count  × 12 floats
```

Stride constants: `sprite_stride = 7`, `glyph_stride = 12` (`render/gpu.mbt`).

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

HUD and modal widgets (buttons, dim veil placeholders) use the same sprite
records with resources such as `ui.button`, `ui.button_focus`, `ui.menu_dim`.

### Glyph record (stride 12)

| offset | field |
|-------:|-------|
| 0 | atlas_x (px) |
| 1 | atlas_y (px) |
| 2 | atlas_w (px, UV shelf cell) |
| 3 | atlas_h (px, UV shelf cell) |
| 4 | x (canvas) |
| 5 | y (canvas) |
| 6 | screen_w (canvas dest width, layout advance) |
| 7 | screen_h (canvas dest height, font size) |
| 8 | r |
| 9 | g |
| 10 | b |
| 11 | a |

**Important:** `screen_w`/`screen_h` are the on-canvas quad size. They are
**not** the same as `atlas_w`/`atlas_h` (rasterization shelf cell). Using the
cell as the screen size made Latin text look massively letter-spaced.

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

UI placeholder ids used by the host: `ui.menu_dim`, `ui.button`,
`ui.button_focus` (plus dialogue/choice chrome from earlier phases).

## Intent codes

Passed as `Int` into `export_frame(intent_code, dt_ms, skip_held)`:

| code | intent |
|-----:|--------|
| 0 | None |
| 1 | Advance |
| 2 | SkipTyping (one-shot; host prefers Ctrl **hold** via `skip_held`) |
| 3 | OpenMenu (**Esc** → open `game_menu` / pop modal) |
| 4 | ToggleAuto |
| 5 | **MenuUp** (↑ / W) |
| 6 | **MenuDown** (↓ / S) |
| 7 | **MenuLeft** (← — slider step down) |
| 8 | **MenuRight** (→ — slider step up) |
| 9 | **OpenBacklog** (**H** — Playing, empty stack) |
| 10+n | Select(n) |

`dt_ms` is frame delta in **milliseconds** (converted to seconds inside the host).
`skip_held` is non-zero while **Control** is held (burst skip; does not skip
timed waits or auto-select choices — full rules in
[`play-input.md`](./play-input.md)).

## Host wasm exports (`host_web`)

| export | meaning |
|--------|---------|
| `init_demo()` | Boot demo IR + `standard_registry` director + `std_ui` / project UI |
| `load_source(src)` | Compile MoonYuki source and replace engine |
| `load_msb(raw)` | Load `MSB1` bytecode and replace engine |
| `boot_title()` | Cold start Title + show `title` modal (`std_ui`) |
| `export_frame(intent, dt_ms, skip_held)` | Tick + pack; returns pack length (`skip_held` ≠ 0 while Ctrl held) |
| `frame_len()` | Last pack length |
| `frame_at(i)` | Pack float at index |
| `resource_count()` / `resource_name(id)` | Resource table |
| `save_json(slot)` / `load_json(json)` | Engine save blob (storage is JS) |
| `prefs_json()` / `set_prefs_json(json)` | Prefs bridge |
| `save_slot_count()` / `set_save_slots` / `get_slot_json` / `set_slot_json` | Multi-slot hydrate |
| `pending_glyph_*` / `mark_glyph_ready` | Atlas rasterization bridge |

UI trees are linked into the host wasm (`std_ui` + optional project
`ui_package`). There is **no** `screens.json` / `load_screens_json` path.

## JS render loop (sketch)

```js
const n = exports.export_frame(intent, dtMs, skipHeld ? 1 : 0);
const pack = new Float32Array(n);
for (let i = 0; i < n; i++) pack[i] = exports.frame_at(i);
const sc = pack[1] | 0;
const gc = pack[2] | 0;
const veil = pack[3];
const SPRITE_STRIDE = 7;
const GLYPH_STRIDE = 12;
const sprites = pack.subarray(4, 4 + sc * SPRITE_STRIDE);
const glyphs = pack.subarray(4 + sc * SPRITE_STRIDE, 4 + sc * SPRITE_STRIDE + gc * GLYPH_STRIDE);
MoonSightGpu.beginFrame();
MoonSightGpu.drawSprites(sprites);
MoonSightGpu.drawGlyphs(glyphs, "atlas");
MoonSightGpu.drawVeil(veil);
MoonSightGpu.endFrame();
```

## Render order (Phase 4)

Bottom → top (conceptual):

1. Narrative layers (kind + z) — retained as backdrop under menus  
2. Optional menu dim (`ui.menu_dim`) from modal stack paint  
3. HUD + active modal widgets (`UiDrawOp` from `UiRuntime`) + focus highlight  
4. Dialogue / choices paint via HUD tree (not a separate hard-coded path)  
5. `trans.fade` fullscreen veil (`veil_opacity`)  
