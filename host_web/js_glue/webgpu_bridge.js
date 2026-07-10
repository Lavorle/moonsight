/**
 * MoonSight WebGPU bridge — JS owns the device; MoonBit only packs floats.
 * API is stable for Phase 1 hosts (see docs/draw-list-pack.md).
 */

const SPRITE_STRIDE = 7;
const GLYPH_STRIDE = 10;

const QUAD_WGSL = /* wgsl */ `
struct Uniforms {
  canvas : vec2f,
  _pad : vec2f,
};
@group(0) @binding(0) var<uniform> u : Uniforms;
@group(0) @binding(1) var samp : sampler;
@group(0) @binding(2) var tex : texture_2d<f32>;

struct VSOut {
  @builtin(position) pos : vec4f,
  @location(0) uv : vec2f,
  @location(1) tint : vec4f,
};

struct Sprite {
  // x,y,w,h, opacity, unused, z  — z ignored in shader
  rect : vec4f,
  opacity : f32,
  _pad0 : f32,
  _pad1 : f32,
  _pad2 : f32,
};

// Per-instance attributes packed as vertex buffer of quads
@vertex
fn vs_main(
  @builtin(vertex_index) vi : u32,
  @location(0) rect : vec4f,      // x,y,w,h
  @location(1) opacity : f32,
  @location(2) uv_rect : vec4f,   // u0,v0,u1,v1
  @location(3) tint : vec4f,
) -> VSOut {
  // 0..5 triangle list for a unit quad
  var corners = array<vec2f, 6>(
    vec2f(0.0, 0.0), vec2f(1.0, 0.0), vec2f(0.0, 1.0),
    vec2f(0.0, 1.0), vec2f(1.0, 0.0), vec2f(1.0, 1.0),
  );
  let c = corners[vi];
  let px = rect.x + c.x * rect.z;
  let py = rect.y + c.y * rect.w;
  // NDC: top-left origin canvas → clip space
  let ndc_x = (px / u.canvas.x) * 2.0 - 1.0;
  let ndc_y = 1.0 - (py / u.canvas.y) * 2.0;
  var out : VSOut;
  out.pos = vec4f(ndc_x, ndc_y, 0.0, 1.0);
  out.uv = vec2f(
    mix(uv_rect.x, uv_rect.z, c.x),
    mix(uv_rect.y, uv_rect.w, c.y),
  );
  out.tint = vec4f(tint.rgb, tint.a * opacity);
  return out;
}

@fragment
fn fs_main(in : VSOut) -> @location(0) vec4f {
  let c = textureSample(tex, samp, in.uv);
  return c * in.tint;
}
`;

const VEIL_WGSL = /* wgsl */ `
struct Uniforms {
  canvas : vec2f,
  opacity : f32,
  _pad : f32,
};
@group(0) @binding(0) var<uniform> u : Uniforms;

@vertex
fn vs_main(@builtin(vertex_index) vi : u32) -> @builtin(position) vec4f {
  var pos = array<vec2f, 3>(
    vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0),
  );
  return vec4f(pos[vi], 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4f {
  return vec4f(0.0, 0.0, 0.0, u.opacity);
}
`;

/** @type {GPUDevice | null} */
let device = null;
/** @type {GPUCanvasContext | null} */
let context = null;
/** @type {GPUTextureFormat} */
let format = "bgra8unorm";
/** @type {GPURenderPipeline | null} */
let spritePipeline = null;
/** @type {GPURenderPipeline | null} */
let veilPipeline = null;
/** @type {GPUSampler | null} */
let sampler = null;
/** @type {GPUBuffer | null} */
let uniformBuf = null;
/** @type {GPUBuffer | null} */
let veilUniformBuf = null;
/** @type {Map<string|number, {texture: GPUTexture, view: GPUTextureView, width: number, height: number}>} */
const textures = new Map();
/** @type {GPUTextureView | null} */
let whiteView = null;

let canvasW = 1920;
let canvasH = 1080;

/** @type {GPUCommandEncoder | null} */
let encoder = null;
/** @type {GPURenderPassEncoder | null} */
let pass = null;

function ensureGpu() {
  if (!device) throw new Error("MoonSightGpu.init() not called");
}

function makeWhiteTexture() {
  const tex = device.createTexture({
    size: [1, 1],
    format: "rgba8unorm",
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  });
  device.queue.writeTexture(
    { texture: tex },
    new Uint8Array([255, 255, 255, 255]),
    { bytesPerRow: 4 },
    [1, 1],
  );
  const view = tex.createView();
  textures.set(0, { texture: tex, view, width: 1, height: 1 });
  textures.set("", { texture: tex, view, width: 1, height: 1 });
  whiteView = view;
  return view;
}

function makePlaceholderSolid(id, rgba) {
  const tex = device.createTexture({
    size: [1, 1],
    format: "rgba8unorm",
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  });
  device.queue.writeTexture(
    { texture: tex },
    new Uint8Array(rgba),
    { bytesPerRow: 4 },
    [1, 1],
  );
  const view = tex.createView();
  const entry = { texture: tex, view, width: 1, height: 1 };
  textures.set(id, entry);
  return entry;
}

function bindGroupFor(view) {
  return device.createBindGroup({
    layout: spritePipeline.getBindGroupLayout(0),
    entries: [
      { binding: 0, resource: { buffer: uniformBuf } },
      { binding: 1, resource: sampler },
      { binding: 2, resource: view },
    ],
  });
}

/**
 * @param {HTMLCanvasElement} canvas
 */
export async function init(canvas) {
  if (!navigator.gpu) {
    throw new Error("WebGPU not available in this browser");
  }
  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) throw new Error("No WebGPU adapter");
  device = await adapter.requestDevice();
  context = canvas.getContext("webgpu");
  format = navigator.gpu.getPreferredCanvasFormat();
  canvasW = canvas.width || canvas.clientWidth || 1920;
  canvasH = canvas.height || canvas.clientHeight || 1080;
  context.configure({
    device,
    format,
    alphaMode: "premultiplied",
  });

  sampler = device.createSampler({
    magFilter: "linear",
    minFilter: "linear",
  });

  uniformBuf = device.createBuffer({
    size: 16,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  veilUniformBuf = device.createBuffer({
    size: 16,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });

  const spriteModule = device.createShaderModule({ code: QUAD_WGSL });
  spritePipeline = device.createRenderPipeline({
    layout: "auto",
    vertex: {
      module: spriteModule,
      entryPoint: "vs_main",
      buffers: [
        {
          arrayStride: 13 * 4, // rect4 + opacity + pad3? we pack tightly:
          // rect(4) + opacity(1) + uv(4) + tint(4) = 13 floats
          stepMode: "instance",
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x4" },
            { shaderLocation: 1, offset: 16, format: "float32" },
            { shaderLocation: 2, offset: 20, format: "float32x4" },
            { shaderLocation: 3, offset: 36, format: "float32x4" },
          ],
        },
      ],
    },
    fragment: {
      module: spriteModule,
      entryPoint: "fs_main",
      targets: [
        {
          format,
          blend: {
            color: {
              srcFactor: "src-alpha",
              dstFactor: "one-minus-src-alpha",
              operation: "add",
            },
            alpha: {
              srcFactor: "one",
              dstFactor: "one-minus-src-alpha",
              operation: "add",
            },
          },
        },
      ],
    },
    primitive: { topology: "triangle-list" },
  });

  const veilModule = device.createShaderModule({ code: VEIL_WGSL });
  veilPipeline = device.createRenderPipeline({
    layout: "auto",
    vertex: { module: veilModule, entryPoint: "vs_main" },
    fragment: {
      module: veilModule,
      entryPoint: "fs_main",
      targets: [
        {
          format,
          blend: {
            color: {
              srcFactor: "src-alpha",
              dstFactor: "one-minus-src-alpha",
              operation: "add",
            },
            alpha: {
              srcFactor: "one",
              dstFactor: "one-minus-src-alpha",
              operation: "add",
            },
          },
        },
      ],
    },
    primitive: { topology: "triangle-list" },
  });

  makeWhiteTexture();
  // UI placeholders (semi-transparent panels)
  makePlaceholderSolid("ui.dialogue_box", [20, 24, 40, 200]);
  makePlaceholderSolid("ui.nameplate", [40, 48, 80, 220]);
  makePlaceholderSolid("ui.choice_row", [30, 60, 90, 180]);
  makePlaceholderSolid("bg/demo", [60, 90, 140, 255]);
  // Empty atlas placeholder (1x1) until glyphs upload
  makePlaceholderSolid("atlas", [255, 255, 255, 0]);

  writeUniforms();
  return { device, format };
}

function writeUniforms() {
  ensureGpu();
  const data = new Float32Array([canvasW, canvasH, 0, 0]);
  device.queue.writeBuffer(uniformBuf, 0, data);
}

/**
 * @param {number} w
 * @param {number} h
 */
export function resize(w, h) {
  ensureGpu();
  canvasW = Math.max(1, w | 0);
  canvasH = Math.max(1, h | 0);
  if (context && device) {
    const canvas = context.canvas;
    canvas.width = canvasW;
    canvas.height = canvasH;
    context.configure({
      device,
      format,
      alphaMode: "premultiplied",
    });
  }
  writeUniforms();
}

/**
 * @param {string|number} id
 * @param {number} width
 * @param {number} height
 * @param {Uint8Array|ArrayBuffer} rgbaUint8
 */
export function uploadRgbaTexture(id, width, height, rgbaUint8) {
  ensureGpu();
  const bytes =
    rgbaUint8 instanceof Uint8Array ? rgbaUint8 : new Uint8Array(rgbaUint8);
  const prev = textures.get(id);
  if (prev) prev.texture.destroy();
  const tex = device.createTexture({
    size: [width, height],
    format: "rgba8unorm",
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  });
  device.queue.writeTexture(
    { texture: tex },
    bytes,
    { bytesPerRow: width * 4 },
    [width, height],
  );
  const view = tex.createView();
  textures.set(id, { texture: tex, view, width, height });
  return id;
}

/**
 * @param {string|number} id
 * @param {string} url
 */
export async function uploadPngUrl(id, url) {
  ensureGpu();
  const res = await fetch(url);
  if (!res.ok) throw new Error(`uploadPngUrl failed: ${url} (${res.status})`);
  const blob = await res.blob();
  const bitmap = await createImageBitmap(blob);
  const prev = textures.get(id);
  if (prev) prev.texture.destroy();
  const tex = device.createTexture({
    size: [bitmap.width, bitmap.height],
    format: "rgba8unorm",
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  });
  device.queue.copyExternalImageToTexture(
    { source: bitmap },
    { texture: tex },
    [bitmap.width, bitmap.height],
  );
  const view = tex.createView();
  textures.set(id, {
    texture: tex,
    view,
    width: bitmap.width,
    height: bitmap.height,
  });
  bitmap.close();
  return id;
}

export function beginFrame() {
  ensureGpu();
  writeUniforms();
  encoder = device.createCommandEncoder();
  const view = context.getCurrentTexture().createView();
  pass = encoder.beginRenderPass({
    colorAttachments: [
      {
        view,
        clearValue: { r: 0.08, g: 0.09, b: 0.12, a: 1 },
        loadOp: "clear",
        storeOp: "store",
      },
    ],
  });
  pass.setPipeline(spritePipeline);
}

/**
 * Resolve texture view by numeric resId or string key.
 * @param {string|number} id
 */
function viewFor(id) {
  const e = textures.get(id);
  if (e) return e.view;
  // try string form of number
  const e2 = textures.get(String(id));
  if (e2) return e2.view;
  return whiteView;
}

/**
 * Interleaved sprite floats: either combined-pack slice or standalone
 * [x,y,w,h,opacity,resId,z] * N (no count header).
 *
 * @param {Float32Array|ArrayLike<number>} spriteBuffer
 * @param {(id: number) => string|number|null} [resolveRes]
 */
export function drawSprites(spriteBuffer, resolveRes) {
  ensureGpu();
  if (!pass) throw new Error("drawSprites outside beginFrame/endFrame");
  const data =
    spriteBuffer instanceof Float32Array
      ? spriteBuffer
      : Float32Array.from(spriteBuffer);
  const count = Math.floor(data.length / SPRITE_STRIDE);
  if (count <= 0) return;

  // Group by texture for fewer bind-group switches
  /** @type {Map<GPUTextureView, number[]>} */
  const groups = new Map();
  for (let i = 0; i < count; i++) {
    const o = i * SPRITE_STRIDE;
    const resId = data[o + 5] | 0;
    let key = resId;
    if (typeof resolveRes === "function") {
      const name = resolveRes(resId);
      if (name != null && textures.has(name)) key = name;
    } else if (textures.has(resId)) {
      key = resId;
    }
    const view = viewFor(key);
    let list = groups.get(view);
    if (!list) {
      list = [];
      groups.set(view, list);
    }
    list.push(i);
  }

  for (const [view, indices] of groups) {
    const inst = new Float32Array(indices.length * 13);
    for (let n = 0; n < indices.length; n++) {
      const i = indices[n];
      const o = i * SPRITE_STRIDE;
      const base = n * 13;
      inst[base + 0] = data[o + 0];
      inst[base + 1] = data[o + 1];
      inst[base + 2] = data[o + 2];
      inst[base + 3] = data[o + 3];
      inst[base + 4] = data[o + 4];
      // full UV
      inst[base + 5] = 0;
      inst[base + 6] = 0;
      inst[base + 7] = 1;
      inst[base + 8] = 1;
      // white tint
      inst[base + 9] = 1;
      inst[base + 10] = 1;
      inst[base + 11] = 1;
      inst[base + 12] = 1;
    }
    const buf = device.createBuffer({
      size: inst.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
      mappedAtCreation: true,
    });
    new Float32Array(buf.getMappedRange()).set(inst);
    buf.unmap();
    pass.setBindGroup(0, bindGroupFor(view));
    pass.setVertexBuffer(0, buf);
    pass.draw(6, indices.length);
  }
}

/**
 * Glyph buffer: [atlas_x,atlas_y,atlas_w,atlas_h,x,y,r,g,b,a] * N
 * @param {Float32Array|ArrayLike<number>} glyphBuffer
 * @param {string|number} atlasTextureId
 */
export function drawGlyphs(glyphBuffer, atlasTextureId = "atlas") {
  ensureGpu();
  if (!pass) throw new Error("drawGlyphs outside beginFrame/endFrame");
  const data =
    glyphBuffer instanceof Float32Array
      ? glyphBuffer
      : Float32Array.from(glyphBuffer);
  const count = Math.floor(data.length / GLYPH_STRIDE);
  if (count <= 0) return;

  const atlas = textures.get(atlasTextureId) || textures.get("atlas");
  const aw = atlas ? atlas.width : 1;
  const ah = atlas ? atlas.height : 1;
  const view = atlas ? atlas.view : whiteView;

  const inst = new Float32Array(count * 13);
  let live = 0;
  for (let i = 0; i < count; i++) {
    const o = i * GLYPH_STRIDE;
    const ax = data[o + 0];
    const ay = data[o + 1];
    const gw = data[o + 2];
    const gh = data[o + 3];
    if (gw <= 0 || gh <= 0) continue;
    const base = live * 13;
    inst[base + 0] = data[o + 4];
    inst[base + 1] = data[o + 5];
    inst[base + 2] = gw;
    inst[base + 3] = gh;
    inst[base + 4] = 1; // opacity
    inst[base + 5] = ax / aw;
    inst[base + 6] = ay / ah;
    inst[base + 7] = (ax + gw) / aw;
    inst[base + 8] = (ay + gh) / ah;
    inst[base + 9] = data[o + 6];
    inst[base + 10] = data[o + 7];
    inst[base + 11] = data[o + 8];
    inst[base + 12] = data[o + 9];
    live++;
  }
  if (live <= 0) return;

  const bytes = live * 13 * 4;
  const buf = device.createBuffer({
    size: bytes,
    usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    mappedAtCreation: true,
  });
  new Float32Array(buf.getMappedRange()).set(inst.subarray(0, live * 13));
  buf.unmap();
  pass.setBindGroup(0, bindGroupFor(view));
  pass.setVertexBuffer(0, buf);
  pass.draw(6, live);
}

/**
 * @param {number} opacity
 */
export function drawVeil(opacity) {
  ensureGpu();
  if (!pass) throw new Error("drawVeil outside beginFrame/endFrame");
  const a = Math.min(1, Math.max(0, +opacity || 0));
  if (a <= 0.001) return;
  device.queue.writeBuffer(
    veilUniformBuf,
    0,
    new Float32Array([canvasW, canvasH, a, 0]),
  );
  const bg = device.createBindGroup({
    layout: veilPipeline.getBindGroupLayout(0),
    entries: [{ binding: 0, resource: { buffer: veilUniformBuf } }],
  });
  pass.setPipeline(veilPipeline);
  pass.setBindGroup(0, bg);
  pass.draw(3);
  // restore sprite pipeline for any later draws
  pass.setPipeline(spritePipeline);
}

export function endFrame() {
  ensureGpu();
  if (pass) {
    pass.end();
    pass = null;
  }
  if (encoder) {
    device.queue.submit([encoder.finish()]);
    encoder = null;
  }
}

/**
 * Rasterize a single glyph into the atlas texture at pixel rect.
 * Phase 1 helper used by boot.js (canvas 2d → rgba upload region).
 * Full atlas re-upload is acceptable for smoke.
 *
 * @param {string} ch
 * @param {number} size
 * @param {number} atlasX
 * @param {number} atlasY
 * @param {number} atlasW
 * @param {number} atlasH
 * @param {number} atlasSize
 */
export function rasterizeGlyphToAtlas(
  ch,
  size,
  atlasX,
  atlasY,
  atlasW,
  atlasH,
  atlasSize = 1024,
) {
  ensureGpu();
  let entry = textures.get("atlas");
  if (!entry || entry.width < atlasSize) {
    // allocate blank atlas
    const pixels = new Uint8Array(atlasSize * atlasSize * 4);
    uploadRgbaTexture("atlas", atlasSize, atlasSize, pixels);
    entry = textures.get("atlas");
  }
  const canvas = document.createElement("canvas");
  canvas.width = atlasW;
  canvas.height = atlasH;
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, atlasW, atlasH);
  ctx.fillStyle = "#ffffff";
  ctx.font = `${size}px sans-serif`;
  ctx.textBaseline = "top";
  ctx.fillText(ch, 0, 0);
  const img = ctx.getImageData(0, 0, atlasW, atlasH);

  // Read full atlas, stamp glyph, re-upload (simple Phase 1 path)
  // Keep a CPU mirror on the texture entry.
  if (!entry.cpu) {
    entry.cpu = new Uint8Array(entry.width * entry.height * 4);
  }
  const cpu = entry.cpu;
  for (let y = 0; y < atlasH; y++) {
    for (let x = 0; x < atlasW; x++) {
      const si = (y * atlasW + x) * 4;
      const di = ((atlasY + y) * entry.width + (atlasX + x)) * 4;
      cpu[di] = img.data[si];
      cpu[di + 1] = img.data[si + 1];
      cpu[di + 2] = img.data[si + 2];
      cpu[di + 3] = img.data[si + 3];
    }
  }
  device.queue.writeTexture(
    { texture: entry.texture },
    cpu,
    { bytesPerRow: entry.width * 4 },
    [entry.width, entry.height],
  );
}

/** Install on globalThis for non-module hosts and MoonBit docs. */
const api = {
  init,
  resize,
  uploadRgbaTexture,
  uploadPngUrl,
  beginFrame,
  drawSprites,
  drawGlyphs,
  drawVeil,
  endFrame,
  rasterizeGlyphToAtlas,
  /** @private test aid */
  _textures: textures,
};

globalThis.MoonSightGpu = api;

export default api;
