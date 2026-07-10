# MoonSight

MoonBit + WebGPU visual novel engine.

## Phase 1

Runtime kernel: MoonYuki → IR/VM → Stage → WebGPU.

### WebGPU host smoke (Task 12)

JS owns WebGPU (`host_web/js_glue/webgpu_bridge.js`); MoonBit exports packed
draw-list floats (`export_frame` / `frame_at`). See `docs/draw-list-pack.md`.

```bash
# from repo root
moon build --target wasm-gc host_web
# artifact (debug default):
#   _build/wasm-gc/debug/build/host_web/host_web.wasm
# or release:
moon build --target wasm-gc --release host_web

# copy into js_glue for static serving
cp _build/wasm-gc/release/build/host_web/host_web.wasm host_web/js_glue/host_web.wasm
# serve (any static server; WebGPU needs a secure context / localhost)
cd host_web/js_glue && python3 -m http.server 8080
# open http://localhost:8080/
```

Expected: dark clear color, placeholder `bg/demo` + dialogue panel sprites,
no panic. Click / Enter advances the demo line.

