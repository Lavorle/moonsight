/**
 * MoonSight WebGPU bridge — JS owns the device; MoonBit only packs floats.
 * API is stable for Phase 1 hosts (see docs/draw-list-pack.md).
 */

const SPRITE_STRIDE = 7;
/** atlas_x,y,w,h, x,y, screen_w,screen_h, r,g,b,a */
const GLYPH_STRIDE = 12;
/** Instance floats: rect4 + opacity + pad3 + uv4 + tint4 = 16 (64-byte aligned) */
const INSTANCE_FLOATS = 16;

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
  // Textures are straight (non-premultiplied) RGBA. Convert to premultiplied
  // for blend mode (one, one-minus-src-alpha) used with the swapchain.
  let c = textureSample(tex, samp, in.uv);
  let rgb = c.rgb * in.tint.rgb;
  let a = c.a * in.tint.a;
  return vec4f(rgb * a, a);
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
 * Human-readable WebGPU availability check (Linux Brave/Firefox often need flags).
 * @returns {{ ok: boolean, message: string }}
 */
export function diagnoseWebGpu() {
  const ua = typeof navigator !== "undefined" ? navigator.userAgent : "";
  const isBrave =
    typeof navigator !== "undefined" &&
    (!!navigator.brave || /Brave/i.test(ua));
  const isFirefox = /Firefox\//i.test(ua);
  const isChromium = /Chrome\//i.test(ua) || /Chromium\//i.test(ua);
  const isLinux = /Linux/i.test(ua) && !/Android/i.test(ua);
  const secure =
    typeof window === "undefined" ||
    window.isSecureContext === true ||
    location.protocol === "https:" ||
    location.hostname === "localhost" ||
    location.hostname === "127.0.0.1" ||
    location.hostname === "[::1]";

  if (!secure) {
    return {
      ok: false,
      message:
        "WebGPU requires a secure context. Serve over http://localhost (not file://) or https.",
    };
  }
  if (!navigator.gpu) {
    const lines = [
      "WebGPU not available (navigator.gpu is missing).",
      "",
      "Recommended for Phase 1: Chrome / Chromium / Edge (latest).",
    ];
    if (isBrave || (isChromium && isLinux)) {
      lines.push(
        "",
        "Brave / Chromium on Linux:",
        "  1. Open brave://flags  (or chrome://flags)",
        "  2. Enable: Unsafe WebGPU Support  (#enable-unsafe-webgpu)",
        "  3. Enable: Vulkan  (#enable-vulkan)  — often required on Linux",
        "  4. Optional: Ignore GPU blocklist  (#ignore-gpu-blocklist)",
        "  5. Relaunch the browser",
        "  6. Check brave://gpu  — WebGPU should not say Disabled",
        "",
        "CLI alternative:",
        "  brave-browser --enable-unsafe-webgpu --enable-features=Vulkan --use-angle=vulkan",
      );
    }
    if (isFirefox) {
      lines.push(
        "",
        "Firefox:",
        "  WebGPU on Linux is still experimental (Windows/macOS ship more broadly).",
        "  about:config → set to true:",
        "    dom.webgpu.enabled",
        "    gfx.webgpu.force-enabled   (or gfx.webgpu.ignore-blocklist)",
        "  Prefer Firefox Nightly/Beta if Stable still has no navigator.gpu.",
        "  Restart Firefox, then open about:support and search WebGPU.",
      );
    }
    if (!isBrave && !isFirefox && !isChromium) {
      lines.push(
        "",
        "Install a recent Chromium-based browser, or enable WebGPU flags if present.",
      );
    }
    lines.push("", `UA: ${ua.slice(0, 120)}`);
    return { ok: false, message: lines.join("\n") };
  }
  return { ok: true, message: "navigator.gpu present" };
}

/**
 * @param {HTMLCanvasElement} canvas
 */
export async function init(canvas) {
  const diag = diagnoseWebGpu();
  if (!diag.ok) {
    throw new Error(diag.message);
  }
  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    throw new Error(
      [
        "No WebGPU adapter (navigator.gpu exists but requestAdapter() returned null).",
        "GPU may be blocklisted or drivers missing.",
        "Chromium: enable #enable-unsafe-webgpu + #enable-vulkan, check chrome://gpu / brave://gpu.",
        "Firefox: gfx.webgpu.force-enabled / ignore-blocklist; try Nightly on Linux.",
      ].join("\n"),
    );
  }
  device = await adapter.requestDevice();
  context = canvas.getContext("webgpu");
  format = navigator.gpu.getPreferredCanvasFormat();
  canvasW = canvas.width || canvas.clientWidth || 1920;
  canvasH = canvas.height || canvas.clientHeight || 1080;
  context.configure({
    device,
    format,
    // Match premultiplied fragment output (see fs_main / glyph stamp).
    alphaMode: "premultiplied",
  });

  // Nearest keeps atlas glyphs crisp; linear bleeds across shelf cells.
  sampler = device.createSampler({
    magFilter: "nearest",
    minFilter: "nearest",
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
          // 16-byte aligned attributes (float32x4 @ 0/16/32/48)
          // layout: rect4 | uv4 | tint4 | opacity+pad3
          arrayStride: INSTANCE_FLOATS * 4,
          stepMode: "instance",
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x4" }, // rect
            { shaderLocation: 1, offset: 48, format: "float32" }, // opacity
            { shaderLocation: 2, offset: 16, format: "float32x4" }, // uv
            { shaderLocation: 3, offset: 32, format: "float32x4" }, // tint
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
              srcFactor: "one",
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

  // Group by texture for fewer bind-group switches.
  // NOTE (Phase 1): Map insertion order means same-texture batches are drawn
  // together, which can reorder interleaving across textures and ignore pack `z`.
  // Safe while draw-list layers are mostly texture-sorted; fix with z-aware
  // multi-draw or depth if overlapping cross-texture order matters.
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
    const inst = new Float32Array(indices.length * INSTANCE_FLOATS);
    for (let n = 0; n < indices.length; n++) {
      const i = indices[n];
      const o = i * SPRITE_STRIDE;
      const base = n * INSTANCE_FLOATS;
      // rect
      inst[base + 0] = data[o + 0];
      inst[base + 1] = data[o + 1];
      inst[base + 2] = data[o + 2];
      inst[base + 3] = data[o + 3];
      // uv full texture
      inst[base + 4] = 0;
      inst[base + 5] = 0;
      inst[base + 6] = 1;
      inst[base + 7] = 1;
      // straight-alpha tint (shader premultiplies)
      inst[base + 8] = 1;
      inst[base + 9] = 1;
      inst[base + 10] = 1;
      inst[base + 11] = 1;
      // opacity multiplies tint.a in the vertex shader
      inst[base + 12] = data[o + 4];
      inst[base + 13] = 0;
      inst[base + 14] = 0;
      inst[base + 15] = 0;
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
 * Glyph buffer:
 * [atlas_x,atlas_y,atlas_w,atlas_h, x,y, screen_w,screen_h, r,g,b,a] * N
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

  const inst = new Float32Array(count * INSTANCE_FLOATS);
  let live = 0;
  for (let i = 0; i < count; i++) {
    const o = i * GLYPH_STRIDE;
    const ax = data[o + 0];
    const ay = data[o + 1];
    const auw = data[o + 2];
    const auh = data[o + 3];
    if (auw <= 0 || auh <= 0) continue;
    let sw = data[o + 6];
    let sh = data[o + 7];
    // Backward-compatible fallback if host serves old 10-float packs.
    if (!(sw > 0) || !(sh > 0)) {
      sw = auw;
      sh = auh;
    }
    const r = data[o + 8];
    const g = data[o + 9];
    const b = data[o + 10];
    const a = data[o + 11];
    const base = live * INSTANCE_FLOATS;
    // rect: screen position + size (NOT atlas cell size)
    inst[base + 0] = data[o + 4];
    inst[base + 1] = data[o + 5];
    inst[base + 2] = sw;
    inst[base + 3] = sh;
    // uv from atlas shelf cell
    inst[base + 4] = ax / aw;
    inst[base + 5] = ay / ah;
    inst[base + 6] = (ax + auw) / aw;
    inst[base + 7] = (ay + auh) / ah;
    // straight-alpha tint (shader premultiplies with coverage)
    inst[base + 8] = r;
    inst[base + 9] = g;
    inst[base + 10] = b;
    inst[base + 11] = a;
    inst[base + 12] = 1;
    inst[base + 13] = 0;
    inst[base + 14] = 0;
    inst[base + 15] = 0;
    live++;
  }
  if (live <= 0) return;

  const bytes = live * INSTANCE_FLOATS * 4;
  const buf = device.createBuffer({
    size: bytes,
    usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    mappedAtCreation: true,
  });
  new Float32Array(buf.getMappedRange()).set(
    inst.subarray(0, live * INSTANCE_FLOATS),
  );
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
  if (!entry || entry.width < atlasSize || !entry.cpu) {
    // allocate blank atlas (transparent black)
    const pixels = new Uint8Array(atlasSize * atlasSize * 4);
    uploadRgbaTexture("atlas", atlasSize, atlasSize, pixels);
    entry = textures.get("atlas");
    entry.cpu = pixels;
  }
  if (atlasW <= 0 || atlasH <= 0) return;

  const canvas = document.createElement("canvas");
  canvas.width = atlasW;
  canvas.height = atlasH;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  ctx.clearRect(0, 0, atlasW, atlasH);
  // White ink; alpha from coverage. Scale font so glyphs fit the cell with
  // a small margin (avoids clipping descenders / wide CJK).
  // Fit glyph inside the shelf cell (square ≈ font size) with a small margin.
  const fontPx = Math.max(1, Math.floor(Math.min(size, atlasW, atlasH) * 0.78));
  ctx.font = `${fontPx}px "Segoe UI","Noto Sans CJK SC","Noto Sans","DejaVu Sans",sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = "#ffffff";
  ctx.fillText(ch, atlasW * 0.5, atlasH * 0.5);
  const img = ctx.getImageData(0, 0, atlasW, atlasH);

  // Stamp straight-alpha white coverage into the CPU mirror.
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
  // Upload only the stamped sub-rect (bytesPerRow must be 256-aligned for
  // some backends when using the full texture path; full upload is fine at 1024).
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
