/**
 * GPU Slug stamp: rasterize outline glyphs into the atlas using the
 * diffusionstudio/slug-webgpu WGSL port of Eric Lengyel's Slug algorithm.
 *
 * Sources:
 *   https://github.com/diffusionstudio/slug-webgpu (MIT)
 *   https://github.com/EricLengyel/Slug (MIT / Apache-2.0)
 */

import { parseTrueType } from "./ttf.js";
import {
  contoursToSlugCurves,
  buildBands,
  packGlyphData,
  TEX_WIDTH,
} from "./slug_pack.js";

const _u32 = new Uint32Array(1);
const _f32 = new Float32Array(_u32.buffer);
function packU32AsF32(value) {
  _u32[0] = value >>> 0;
  return _f32[0];
}

/** @type {GPUDevice | null} */
let device = null;
/** @type {GPURenderPipeline | null} */
let pipeline = null;
/** @type {GPUBindGroupLayout | null} */
let bgl = null;
/** @type {GPUBuffer | null} */
let uniformBuf = null;
/** @type {ReturnType<typeof parseTrueType> | null} */
let font = null;
/** @type {string} */
let atlasFormat = "rgba8unorm";

/**
 * @param {GPUDevice} dev
 * @param {string} [format]
 */
export async function initSlugGpu(dev, format = "rgba8unorm") {
  device = dev;
  atlasFormat = format;
  // Direct new URL(..., import.meta.url) so Vite emits .wgsl as assets
  // (intermediate `new URL(".", import.meta.url)` is not statically rewritten).
  const [vsSrc, fsSrc] = await Promise.all([
    fetch(new URL("./SlugVertexShader.wgsl", import.meta.url)).then((r) =>
      r.text(),
    ),
    fetch(new URL("./SlugPixelShader.wgsl", import.meta.url)).then((r) =>
      r.text(),
    ),
  ]);

  bgl = device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX,
        buffer: { type: "uniform" },
      },
      {
        binding: 1,
        visibility: GPUShaderStage.FRAGMENT,
        texture: { sampleType: "unfilterable-float" },
      },
      {
        binding: 2,
        visibility: GPUShaderStage.FRAGMENT,
        texture: { sampleType: "uint" },
      },
    ],
  });

  const vs = device.createShaderModule({ code: vsSrc });
  const fs = device.createShaderModule({ code: fsSrc });

  pipeline = device.createRenderPipeline({
    layout: device.createPipelineLayout({ bindGroupLayouts: [bgl] }),
    vertex: {
      module: vs,
      entryPoint: "main",
      buffers: [
        {
          arrayStride: 80,
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x4" },
            { shaderLocation: 1, offset: 16, format: "float32x4" },
            { shaderLocation: 2, offset: 32, format: "float32x4" },
            { shaderLocation: 3, offset: 48, format: "float32x4" },
            { shaderLocation: 4, offset: 64, format: "float32x4" },
          ],
        },
      ],
    },
    fragment: {
      module: fs,
      entryPoint: "main",
      targets: [
        {
          format: atlasFormat,
          blend: {
            color: {
              srcFactor: "src-alpha",
              dstFactor: "one-minus-src-alpha",
            },
            alpha: {
              srcFactor: "one",
              dstFactor: "one-minus-src-alpha",
            },
          },
        },
      ],
    },
    primitive: { topology: "triangle-list" },
  });

  uniformBuf = device.createBuffer({
    size: 80,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
}

/**
 * @param {ArrayBuffer} fontBuf
 */
export function loadFontBuffer(fontBuf) {
  font = parseTrueType(fontBuf);
  return font;
}

export function hasFont() {
  return !!font && !!pipeline;
}

/**
 * Stamp one codepoint into an atlas sub-rect using Slug GPU rasterization.
 *
 * @param {object} opts
 * @param {GPUTexture} opts.atlasTexture
 * @param {number} opts.codepoint
 * @param {number} opts.atlasX
 * @param {number} opts.atlasY
 * @param {number} opts.atlasW
 * @param {number} opts.atlasH
 * @param {number} opts.fontSize  logical pixel size (≈ cell height)
 * @returns {boolean} true if stamped
 */
export function stampGlyphToAtlas(opts) {
  if (!device || !pipeline || !font || !bgl || !uniformBuf) return false;
  const {
    atlasTexture,
    codepoint,
    atlasX,
    atlasY,
    atlasW,
    atlasH,
    fontSize,
  } = opts;
  if (atlasW <= 0 || atlasH <= 0) return false;

  const g = font.glyphForCodepoint(codepoint);
  if (!g || !g.contours.length) {
    // empty / space — leave transparent
    return true;
  }

  const extracted = contoursToSlugCurves(g.contours);
  if (!extracted || !extracted.curves.length) return true;

  const bands = buildBands(extracted.curves, extracted.bounds, 8);
  const glyph = {
    curves: extracted.curves,
    bounds: extracted.bounds,
    bands,
  };
  const packed = packGlyphData([glyph]);
  const { glyphLocX, glyphLocY } = packed.glyphBandInfo[0];

  // Upload curve + band textures for this glyph
  const curveTex = device.createTexture({
    size: { width: TEX_WIDTH, height: packed.curveTexHeight },
    format: "rgba32float",
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
  });
  device.queue.writeTexture(
    { texture: curveTex },
    packed.curveTexData,
    { bytesPerRow: TEX_WIDTH * 16 },
    { width: TEX_WIDTH, height: packed.curveTexHeight },
  );

  const bandTex = device.createTexture({
    size: { width: TEX_WIDTH, height: packed.bandTexHeight },
    format: "rgba32uint",
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
  });
  device.queue.writeTexture(
    { texture: bandTex },
    packed.bandTexData,
    { bytesPerRow: TEX_WIDTH * 16 },
    { width: TEX_WIDTH, height: packed.bandTexHeight },
  );

  const { xMin, yMin, xMax, yMax } = glyph.bounds;
  const bw = xMax - xMin;
  const bh = yMax - yMin;
  // Fit em bounds into cell with padding (font y-up → atlas y-down via matrix)
  const pad = 1;
  const cellW = atlasW;
  const cellH = atlasH;
  const sx = bw > 0 ? (cellW - pad * 2) / bw : 1;
  const sy = bh > 0 ? (cellH - pad * 2) / bh : 1;
  const scale = Math.min(sx, sy);

  // Object space: Y-up, origin bottom-left of cell local coords
  // Map em (xMin..xMax, yMin..yMax) into (pad..pad+bw*scale, pad..pad+bh*scale)
  // Then flip Y for atlas (top-left origin) via the projection matrix.
  const x0 = pad;
  const y0 = pad;
  const x1 = pad + bw * scale;
  const y1 = pad + bh * scale;

  // em-space corners
  const emX0 = xMin;
  const emY0 = yMin;
  const emX1 = xMax;
  const emY1 = yMax;

  const invScale = bw > 0 ? bw / (x1 - x0) : 1; // d(em)/d(obj) for x
  const invScaleY = bh > 0 ? bh / (y1 - y0) : 1;

  const bandScaleX = bw > 0 ? glyph.bands.vBandCount / bw : 0;
  const bandScaleY = bh > 0 ? glyph.bands.hBandCount / bh : 0;
  const bandOffsetX = -xMin * bandScaleX;
  const bandOffsetY = -yMin * bandScaleY;

  const glyphLocPacked = packU32AsF32((glyphLocY << 16) | glyphLocX);
  const bandMaxX = glyph.bands.vBandCount - 1;
  const bandMaxY = glyph.bands.hBandCount - 1;
  const bandMaxPacked = packU32AsF32((bandMaxY << 16) | bandMaxX);

  // Object-space: Y-up, (0,0)=bottom-left of cell
  // Corners in object space for the fitted bounds rect
  const corners = [
    [x0, y0, -1, -1, emX0, emY0],
    [x1, y0, 1, -1, emX1, emY0],
    [x1, y1, 1, 1, emX1, emY1],
    [x0, y1, -1, 1, emX0, emY1],
  ];

  const verts = new Float32Array(4 * 20);
  for (let i = 0; i < 4; i++) {
    const [px, py, nx, ny, ex, ey] = corners[i];
    const o = i * 20;
    verts[o + 0] = px;
    verts[o + 1] = py;
    verts[o + 2] = nx;
    verts[o + 3] = ny;
    verts[o + 4] = ex;
    verts[o + 5] = ey;
    verts[o + 6] = glyphLocPacked;
    verts[o + 7] = bandMaxPacked;
    verts[o + 8] = invScale;
    verts[o + 9] = 0;
    verts[o + 10] = 0;
    verts[o + 11] = invScaleY;
    verts[o + 12] = bandScaleX;
    verts[o + 13] = bandScaleY;
    verts[o + 14] = bandOffsetX;
    verts[o + 15] = bandOffsetY;
    verts[o + 16] = 1;
    verts[o + 17] = 1;
    verts[o + 18] = 1;
    verts[o + 19] = 1;
  }
  const indices = new Uint32Array([0, 1, 2, 0, 2, 3]);

  const vbo = device.createBuffer({
    size: verts.byteLength,
    usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
  });
  device.queue.writeBuffer(vbo, 0, verts);
  const ibo = device.createBuffer({
    size: indices.byteLength,
    usage: GPUBufferUsage.INDEX | GPUBufferUsage.COPY_DST,
  });
  device.queue.writeBuffer(ibo, 0, indices);

  // Ortho: object Y-up cell → clip. Bake atlas placement via scissor + viewport.
  // Local cell (0..W, 0..H) Y-up → NDC for a W×H target (we'll use scissor on full atlas).
  const uniformData = new Float32Array(20);
  // Map local Y-up pixel coords to clip for a cell-sized target, then we
  // offset via viewport to (atlasX, atlasY) on the atlas.
  uniformData.set(
    [
      2 / cellW,
      0,
      0,
      -1,
      0,
      2 / cellH,
      0,
      -1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
    ],
    0,
  );
  uniformData.set([cellW, cellH, 0, 0], 16);
  device.queue.writeBuffer(uniformBuf, 0, uniformData);

  const bg = device.createBindGroup({
    layout: bgl,
    entries: [
      { binding: 0, resource: { buffer: uniformBuf } },
      { binding: 1, resource: curveTex.createView() },
      { binding: 2, resource: bandTex.createView() },
    ],
  });

  const encoder = device.createCommandEncoder();
  // Clear the target cell to transparent first via a load+scissor clear isn't
  // direct; use loadOp clear only on first atlas create. For stamps we clear
  // the subrect by drawing with loadOp "load" after CPU zeroed the region, or
  // clear full atlas only once. We clear subrect by queue write of zeros on CPU
  // path; here loadOp "load" preserves neighbors.
  const pass = encoder.beginRenderPass({
    colorAttachments: [
      {
        view: atlasTexture.createView(),
        loadOp: "load",
        storeOp: "store",
      },
    ],
  });
  // Viewport: atlas Y grows down; WebGPU viewport origin is top-left.
  // Our local Y-up maps to clip with y=-1 at bottom; viewport y is top of rect.
  pass.setViewport(atlasX, atlasY, cellW, cellH, 0, 1);
  pass.setScissorRect(atlasX, atlasY, cellW, cellH);
  pass.setPipeline(pipeline);
  pass.setBindGroup(0, bg);
  pass.setVertexBuffer(0, vbo);
  pass.setIndexBuffer(ibo, "uint32");
  pass.drawIndexed(6);
  pass.end();
  device.queue.submit([encoder.finish()]);

  curveTex.destroy();
  bandTex.destroy();
  vbo.destroy();
  ibo.destroy();
  return true;
}
