# Outline text (Slug / WebGPU)

MoonSight stamps dialogue glyphs into a shared atlas, then draws textured
quads. Glyph **stamping** can use three modes (query `?glyph=`):

| Mode | Description |
|------|-------------|
| **`slug`** (default) | GPU Slug algorithm — banded quadratic Béziers in WGSL |
| `canvas` | Canvas2D `fillText` (reliable fallback) |
| `cpu-outline` | CPU multi-sample winding (experimental) |

## Slug GPU path

Based on:

1. **Eric Lengyel** — Slug algorithm ([paper](https://jcgt.org/published/0006/02/02/),
   [reference HLSL](https://github.com/EricLengyel/Slug), patent public domain)
2. **diffusionstudio/slug-webgpu** — WebGPU/WGSL port and band packing
   ([github.com/diffusionstudio/slug-webgpu](https://github.com/diffusionstudio/slug-webgpu), MIT)

### Host files

```
host_web/js_glue/slug/
  SlugVertexShader.wgsl   # from slug-webgpu
  SlugPixelShader.wgsl    # from slug-webgpu
  slug_pack.js            # curves + bands (adapted from slug-webgpu/src/slug.ts)
  slug_gpu.js             # pipeline + stamp into atlas sub-rect
  ttf.js                  # minimal TrueType glyf loader
  …
third_party/slug/         # Lengyel reference HLSL + NOTICE
```

### Pipeline

1. MoonBit lays out runs with **Noto advance metrics** (`noto_advance_em`) and
   shelf-packs rectangular atlas cells.
2. JS loads `fonts/NotoSans-Regular.ttf`.
3. For each pending glyph, **Slug GPU** renders coverage into the atlas cell
   (viewport/scissor on the atlas texture).
4. Existing textured-quad path draws the atlas.

## Letterboxing

Canvas backbuffer is always **1920×1080**; CSS letterboxes the element so
non-16:9 windows do not stretch glyphs.

## Credits

- Eric Lengyel — Slug algorithm  
- Konstantin Paulus / diffusionstudio — slug-webgpu WGSL port  
- Noto Sans — Google (OFL; font file under `host_web/js_glue/fonts/`)
