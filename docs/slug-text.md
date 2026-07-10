# Outline text (Slug-inspired)

MoonSight Phase 1 stamps glyphs into a shared atlas, then draws textured
quads. The host no longer relies on `canvas.fillText` alone for the demo
font path.

## Pipeline

1. **MoonBit** (`render`) lays out dialogue / choices with proportional
   advances (`approximate_measure`) and shelf-packs **rectangular** atlas
   cells (`advance+pad` × `font_size`).
2. **JS host** loads `fonts/NotoSans-Regular.ttf`, parses TrueType `glyf`
   outlines, and rasterizes each pending glyph with a multi-sample
   **winding / coverage** pass over quadratic Béziers.
3. Coverage is uploaded into the atlas; draw-list UVs sample those cells.
   Screen size is the layout advance × font size (not the shelf cell).

## Slug algorithm credit

The outline coverage approach is inspired by the **Slug** algorithm by
Eric Lengyel:

- Paper: [GPU-Centered Font Rendering Directly from Glyph Outlines](https://jcgt.org/published/0006/02/02/)
- Reference shaders (MIT / Apache-2.0): [github.com/EricLengyel/Slug](https://github.com/EricLengyel/Slug)
- Local copy: `third_party/slug/` (+ `NOTICE`)

Phase 1 uses a **CPU** winding raster for atlas stamps (simpler FFI than a
full band-texture GPU path). A future revision can port the reference
pixel shader to WGSL and evaluate curves directly on the GPU.

## Letterboxing

The canvas backbuffer stays **1920×1080**. CSS **letterboxes** to the
window (uniform scale). Stretching with `width:100vw; height:100vh` made
glyphs look unnaturally wide on non-16:9 windows.

## Fallback

If the TTF fails to load, the host falls back to `canvas.fillText` with
left-aligned placement in the proportional cell.
