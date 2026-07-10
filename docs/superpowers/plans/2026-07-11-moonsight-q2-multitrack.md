# MoonSight Q2 — 演出 + Svelte Host + Fumadocs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Advance toward product gate **0.8** with Engine 主交付（`trans.dissolve`、layer `scale`、中长 demo 骨架、演出与 skip/wait 文档一致）+ Host 次交付（Svelte+TS 默认可玩骨架）+ Docs 次交付（Fumadocs 中英脚手架与核心页）。

**Architecture:** Stage 继续是叙事权威。Dissolve 用 **双阶段全屏 veil**（0→1→0）扩展现有 fade 时钟，不引入时间轴 DSL。Scale 进 `LayerState` 与 `TweenProp`，绘制时乘 canvas 四边形。Host 新建 `apps/host-web`（Vite+Svelte+TS），第三方 `webgpu_bridge` / `slug` 进 `adapters/`；`moonsightc build` 优先复制新 dist。文档站 `apps/docs-site`（Fumadocs）作者优先中英。

**Tech Stack:** MoonBit (`moon test` / `moon check` / `moon build --target wasm-gc`)、Vite 6 + Svelte 5 + TypeScript、Fumadocs（Next.js）、现有 WebGPU JS adapter、Tauri 2（仅改 dist 源）。

**Spec:** `docs/superpowers/specs/2026-07-11-moonsight-roadmap-v2-design.md`（Q2 行）  
**Roadmap:** 同上（多轨总图 v2）  
**前序：** Q1/0.5 已交付

**Pinned defaults（本 plan 锁定，等同 Q2 design 决议）:**

| Item | Choice |
|------|--------|
| Dissolve | `@trans.dissolve duration`：veil 线性 0→1→0，两半各 `duration/2`；`fade_remaining` 仍为总剩余；**不**阻塞 VM（与 fade 同，靠 `@flow.wait`） |
| Fade 兼容 | 现有 `@trans.fade` 不变；dissolve 用 `Stage.dissolve_phase`：`None` / `Out` / `In` |
| Scale | `LayerState.scale` 默认 `1.0`；`TweenProp::Scale`；`@layer.show` / `@layer.set` 支持 `scale=`；缩放原点 **左上 (x,y)**；**不做** rotate/anchor |
| 绘制 | `SpriteDraw` w/h = `canvas * scale`（今日层满画布；scale 乘宽高） |
| 存档 | **v4**：layer 含 `scale`；加载 v3 时 `scale=1.0` |
| Voice | **Q2 不做** voice 轨；SE 维持现状（roadmap「或」选 SE 侧不做大改） |
| Host 壳 | **Vite + Svelte 5 + TS**（非 SvelteKit）；静态 build 产物可整目录拷贝 |
| Host 默认 | Q2 结束：`moonsightc build` **默认**从 `apps/host-web/dist` 取壳；`host_web/js_glue` 保留作回退至 Q4 |
| Adapter | `webgpu_bridge.js` + `slug/**` 原样放入 `adapters/`，TS 仅 `// @ts-check` 或薄 `declare`；不重写 Slug |
| Docs | Fumadocs 在 `apps/docs-site`；`content/zh` + `content/en`；核心页：Getting Started、MoonYuki subset、Play input |
| 双语 | 三页中英均有正文；其余导航可占位 |
| Demo | 加长 intro：dissolve + scale 示例；≥1 额外短场景段落 |

**非目标（Q2）：** ScrollView、主题系统、槽缩略图、桌面原生存档、`moonsight new`、编辑器、Live2D、DOM 游戏 UI、rotate/anchor、voice 轨、删除 vanilla `js_glue`。

---

## File map

| Path | Role |
|------|------|
| `runtime/stage.mbt` | `scale` on `LayerState`；`TweenProp::Scale`；dissolve phase fields；tween/tick |
| `runtime/stage_test.mbt` | scale tween + dissolve phase tests |
| `runtime/engine.mbt` | tick dissolve phases with overlay |
| `runtime/engine_test.mbt` | dissolve + skip/wait interaction smoke |
| `runtime/save.mbt` | SaveGame **v4** + v3 load scale default |
| `runtime/save_test.mbt` | v3→v4 load scale=1 |
| `runtime/engine.mbt` (`StageView`) | expose `scale` on layer view |
| `std_commands/trans.mbt` | `cmd_trans_dissolve` |
| `std_commands/layer.mbt` | parse `scale=` on show/set |
| `std_commands/registry.mbt` | register `trans.dissolve` |
| `std_commands/registry_test.mbt` | dissolve + scale command tests |
| `script/resolve.mbt` | `builtin_externs` + `trans.dissolve` |
| `script/resolve_test.mbt` | builtin list includes dissolve |
| `render/snapshot.mbt` | apply scale to sprite w/h |
| `render/snapshot_test.mbt` | scale halves dimensions |
| `docs/host-commands.md` | dissolve + scale |
| `docs/play-input.md` | dissolve vs skip/wait note |
| `demo/game/main.yuki` + scenes | longer demo using dissolve/scale |
| `apps/host-web/*` | **Create** Vite+Svelte+TS host |
| `apps/host-web/src/adapters/*` | copy/adapt webgpu + slug + wasm boot |
| `cmd/moonsightc/build.mbt` | prefer `apps/host-web/dist` |
| `host_desktop/README.md` | point to new dist source |
| `apps/docs-site/*` | **Create** Fumadocs site |
| `apps/docs-site/content/zh|en/**` | core pages |
| `README.md` | Q2 scope + host/docs pointers |

---

## Track A — Engine presentation

### Task 1: Layer scale field + TweenProp (TDD)

**Files:**
- Modify: `runtime/stage.mbt`
- Modify: `runtime/stage_test.mbt` (or create if missing — prefer extend existing tests in `runtime/*_test.mbt`)
- Modify: `runtime/engine.mbt` (`StageView` layer copy)

- [ ] **Step 1: Write failing tests**

Add to `runtime/stage_test.mbt` (create file if absent):

```mbt
///|
test "layer scale snaps and tweens" {
  let st = @runtime.Stage::new()
  st.show_layer(
    id="y",
    layer=@runtime.LayerKind::Character,
    resource="char_y",
    z=0,
  )
  assert_eq(st.layers[0].scale, 1.0)
  st.start_layer_tween(id="y", prop=@runtime.TweenProp::Scale, to=0.5, duration=0.0)
  assert_eq(st.layers[0].scale, 0.5)
  st.start_layer_tween(id="y", prop=@runtime.TweenProp::Scale, to=1.0, duration=1.0)
  st.tick_layer_tweens(0.5)
  let s = st.layers[0].scale
  assert_true(s > 0.74 && s < 0.76)
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd /mnt/nvme1n1p2/moonsight && export CC=gcc && moon test -p runtime -v 2>&1 | tail -50
```

Expected: FAIL — `scale` / `Scale` missing.

- [ ] **Step 3: Implement scale**

In `runtime/stage.mbt`:

1. Extend `TweenProp`:

```mbt
pub(all) enum TweenProp {
  X
  Y
  Opacity
  Scale
} derive(Debug, Eq, ToJson, FromJson)
```

2. Add `scale : Double` to `LayerState` (default `1.0` everywhere layers are constructed).

3. Extend `layer_with_prop` / `start_layer_tween` / `tick_layer_tweens` to handle `Scale` exactly like `Opacity` (linear).

4. In `StageView::from_stage` (engine.mbt), copy `scale` onto the view layer struct (add field there too).

Search all `LayerState {` literals in the repo and add `scale: 1.0` (or preserve).

- [ ] **Step 4: Run tests — PASS**

```bash
export CC=gcc && moon test -p runtime -v 2>&1 | tail -40
```

- [ ] **Step 5: Commit**

```bash
git add runtime/stage.mbt runtime/stage_test.mbt runtime/engine.mbt
git commit -m "feat(runtime): layer scale field and Scale tween"
```

---

### Task 2: Save v4 with scale; v3 load default

**Files:**
- Modify: `runtime/save.mbt`
- Modify: `runtime/save_test.mbt`

- [ ] **Step 1: Failing tests**

Update existing `"save blob is format_version 3"` → expect **4**.

Append:

```mbt
///|
test "save roundtrip preserves layer scale" {
  let eng = load_min_demo_engine()
  eng.tick(Intent::Advance)
  eng.stage.start_layer_tween(
    id="bg",
    prop=@runtime.TweenProp::Scale,
    to=0.5,
    duration=0.0,
  )
  let blob = eng.save(slot=0)
  let eng2 = load_min_demo_engine()
  eng2.load(blob)
  assert_eq(eng2.stage.layers[0].scale, 0.5)
  let game = @runtime.parse_save_game(blob)
  assert_eq(game.format_version, 4)
}

///|
test "save rejects unsupported format_version message lists 2-4" {
  let eng = load_min_demo_engine()
  let bad =
    #|{"format_version":99,"module_id":"","scene":"s","ip":0,"call_stack":[],"vars":{},"layers":[],"overlay_opacity":0,"audio":{},"wait":{"$tag":"Running"},"auto":false}
  try eng.load(bad) catch {
    err =>
      // Message must mention supported versions including 4
      assert_true(err.to_string().contains("4"))
  } noraise {
    _ => fail("expected UnsupportedVersion")
  }
}
```

Also keep a fixture that loads an **on-disk v3 blob** (or construct v3 JSON without `scale` fields) and asserts `scale == 1.0` after load — mirror any existing v2 load test style in `save_test.mbt`.

- [ ] **Step 2: Run — FAIL** (version still 3 or scale missing)

- [ ] **Step 3: Implement**

- Document in `save.mbt` header: v4 adds `scale` on layers.
- Writer: `format_version = 4`.
- Loader: `match version { 4 => …; 3 => map layers scale=1.0; 2 => existing path }`.
- Update error string in unsupported-version path to `expected 2, 3, or 4`.

- [ ] **Step 4: `moon test -p runtime` PASS**

- [ ] **Step 5: Commit**

```bash
git add runtime/save.mbt runtime/save_test.mbt
git commit -m "feat(runtime): save format v4 with layer scale"
```

---

### Task 3: Render applies scale

**Files:**
- Modify: `render/snapshot.mbt`
- Modify: `render/snapshot_test.mbt`

- [ ] **Step 1: Failing test**

```mbt
///|
test "build_draw_list multiplies layer size by scale" {
  // StageView layer scale=0.5 → sprite w,h == layout.canvas_* * 0.5
}
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement** in `build_draw_list_with_atlas` layer loop:

```mbt
let sc = Float::from_double(layer.scale)
sprites.push({
  resource: layer.resource,
  x: Float::from_double(layer.x),
  y: Float::from_double(layer.y),
  w: layout.canvas_w * sc,
  h: layout.canvas_h * sc,
  opacity: Float::from_double(layer.opacity),
  z: layer.z,
})
```

Clamp `scale` at draw time to `>= 0` if desired.

- [ ] **Step 4: `moon test -p render` PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(render): apply layer scale to sprite quads"
```

---

### Task 4: Host commands layer scale + registry

**Files:**
- Modify: `std_commands/layer.mbt`
- Modify: `std_commands/registry_test.mbt`

- [ ] **Step 1: Failing test**

```mbt
///|
test "layer.show and layer.set accept scale" {
  let reg = standard_registry()
  let stage = @runtime.Stage::new()
  ignore(
    reg.call(
      "layer.show",
      stage,
      [
        Str("y"),
        Str("char_y"),
        Str("#:kind"),
        Str("character"),
        Str("#:scale"),
        Float(0.5),
      ],
    ),
  )
  assert_eq(stage.layers[0].scale, 0.5)
  ignore(
    reg.call(
      "layer.set",
      stage,
      [Str("y"), Str("#:scale"), Float(1.0), Str("#:duration"), Float(0.0)],
    ),
  )
  assert_eq(stage.layers[0].scale, 1.0)
}
```

Adjust arg packing to match existing `split_host_args` / named style in `registry_test.mbt`.

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

In `cmd_layer_show` / `cmd_layer_set`:

- Read `named_double(named, "scale")`
- New layer: set `scale` (default 1.0); if `duration>0` and scale specified, either snap scale or tween from 1.0→target — **pin: snap scale on show unless duration>0 then tween Scale from current (new layer current=1.0) to target**
- `layer.set scale= duration=` → `start_layer_tween(..., Scale, ...)`

- [ ] **Step 4: `moon test -p std_commands` PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(std_commands): scale= on layer.show/set"
```

---

### Task 5: trans.dissolve (TDD)

**Files:**
- Modify: `runtime/stage.mbt`, `runtime/engine.mbt`
- Modify: `std_commands/trans.mbt`, `registry.mbt`, `registry_test.mbt`
- Modify: `script/resolve.mbt`, `script/resolve_test.mbt`

**Semantics (locked):**

```text
Stage fields:
  dissolve_phase : Int   // 0=none, 1=out (→1), 2=in (→0)
  // reuse overlay_opacity, fade_to, fade_remaining

@trans.dissolve duration
  if duration <= 0:
    overlay_opacity = 0; dissolve_phase = 0; fade_remaining = 0
  else:
    dissolve_phase = 1 (Out)
    fade_to = 1.0
    overlay_opacity = 0.0   // start transparent
    fade_remaining = duration  // total wall time for Out+In

Engine::tick (where fade is advanced today):
  if dissolve_phase == 0:
    existing fade-to-target logic
  else:
    advance overlay toward fade_to over remaining of *current half*
    When Out half completes (overlay ~1 and half elapsed):
      dissolve_phase = 2; fade_to = 0.0; start second half timer
    When In half completes:
      dissolve_phase = 0; overlay = 0; fade_remaining = 0
```

Implementation tip: store `dissolve_total : Double` and `dissolve_elapsed : Double`, or split `fade_remaining` into half segments when phase flips.

- [ ] **Step 1: Failing tests**

```mbt
///|
test "trans.dissolve goes out then in" {
  let reg = standard_registry()
  let stage = @runtime.Stage::new()
  ignore(reg.call("trans.dissolve", stage, [Float(1.0)]))
  // phase out, opacity starts 0, fade_remaining > 0
  // simulate engine fade tick 0.5s → near opaque, phase may still Out or flipped
  // tick another 0.5s → clear
}

///|
test "builtin_externs includes trans.dissolve" {
  let builtins = @script.builtin_externs()
  // assert name present (same style as resolve_test)
}
```

Also add engine-level test: during `wait_remaining > 0`, dissolve still advances (presentation clock), and `skip_held` does not snap dissolve (same as fade — document only unless code today snaps fade).

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement command + engine tick**

`std_commands/trans.mbt`:

```mbt
///|
/// `trans.dissolve duration` — full-screen veil 0→1→0 over `duration` seconds.
pub fn cmd_trans_dissolve(
  stage : @runtime.Stage,
  args : Array[@runtime.Value],
) -> @runtime.HostResult {
  let d = match args {
    [v, ..] =>
      match @runtime.value_as_double(v) {
        Some(x) => x
        None => return Error("trans.dissolve: expected duration number")
      }
    _ => return Error("trans.dissolve: expected duration")
  }
  // set phase / opacity / remaining as pinned
  Ok
}
```

Register in `registry.mbt` and `script/resolve.mbt` `builtin_externs`.

Wire Engine fade tick to honor dissolve phases (read current fade tick code in `engine.mbt` and extend — do not break `@trans.fade`).

- [ ] **Step 4: `moon test -p std_commands -p runtime -p script` PASS**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat: trans.dissolve dual-phase veil transition"
```

---

### Task 6: Demo + docs (Engine track)

**Files:**
- Modify: `demo/game/main.yuki`, optional `demo/game/scenes/*.yuki`
- Modify: `docs/host-commands.md`, `docs/play-input.md`, `README.md`

- [ ] **Step 1: Extend demo**

In `intro` after welcome lines, add something like:

```yuki
y:Watch a dissolve and scale beat.
@trans.dissolve 0.8
@flow.wait 0.4
@layer.set "y" scale=0.85 duration=0.3
@flow.wait 0.4
@layer.set "y" scale=1.0 duration=0.3
@flow.wait 0.3
```

Add a short extra scene (e.g. revisit garden with dissolve in) so play time is clearly longer than Q1.

- [ ] **Step 2: Document**

`host-commands.md` — new sections:

```markdown
### `trans.dissolve duration`

Full-screen black veil eases 0→1→0 over `duration` seconds (two equal halves).
Does **not** block the VM; pair with `@flow.wait`. Skip does not snap the veil
(same family as `trans.fade`).

### layer `scale=`

`@layer.show` / `@layer.set` accept `scale=` (default 1.0). Linear tween via
`duration=`. Scale is about the layer's top-left `(x,y)`. Save format v4.
```

`play-input.md` — one paragraph: dissolve/fade clocks advance during wait; skip still blocked by `wait_remaining`.

`README.md` — Q2 in-scope bullets for dissolve/scale; note Host/Docs WIP if not done yet when committing mid-track.

- [ ] **Step 3: Build demo**

```bash
export CC=gcc
moon check && moon test
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Expected: success; `dist/demo/game.msb` present.

- [ ] **Step 4: Commit**

```bash
git commit -am "docs+demo: dissolve/scale presentation and longer demo"
```

---

## Track B — Svelte host skeleton

### Task 7: Scaffold `apps/host-web` (Vite + Svelte 5 + TS)

**Files:**
- Create: `apps/host-web/package.json`
- Create: `apps/host-web/vite.config.ts`
- Create: `apps/host-web/tsconfig.json`
- Create: `apps/host-web/index.html`
- Create: `apps/host-web/src/main.ts`
- Create: `apps/host-web/src/App.svelte`
- Create: `apps/host-web/src/app.css`
- Create: `apps/host-web/.gitignore` (`node_modules`, `dist`)

- [ ] **Step 1: Scaffold package**

`apps/host-web/package.json`:

```json
{
  "name": "moonsight-host-web",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "devDependencies": {
    "@sveltejs/vite-plugin-svelte": "^5.0.0",
    "svelte": "^5.0.0",
    "typescript": "^5.6.0",
    "vite": "^6.0.0"
  }
}
```

`vite.config.ts`:

```ts
import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  plugins: [svelte()],
  base: "./",
  build: {
    outDir: "dist",
    emptyOutDir: true,
    target: "esnext",
  },
  server: {
    port: 5173,
  },
});
```

`index.html` at app root with `<div id="app"></div>` and `<script type="module" src="/src/main.ts">`.

`App.svelte` minimal: status text + `<canvas id="game" width="1920" height="1080">` + hint (mirror current `index.html` styles).

- [ ] **Step 2: Install and build empty shell**

```bash
cd /mnt/nvme1n1p2/moonsight/apps/host-web && npm install && npm run build
```

Expected: `dist/index.html` exists.

- [ ] **Step 3: Commit**

```bash
git add apps/host-web
git commit -m "chore(host-web): scaffold Vite Svelte TypeScript app"
```

---

### Task 8: Move adapters + port boot to TS modules

**Files:**
- Create: `apps/host-web/public/fonts/**` (copy from `host_web/js_glue/fonts`)
- Create: `apps/host-web/src/adapters/webgpu_bridge.js` (copy)
- Create: `apps/host-web/src/adapters/slug/**` (copy)
- Create: `apps/host-web/src/lib/intents.ts`
- Create: `apps/host-web/src/lib/prefs.ts`
- Create: `apps/host-web/src/lib/audio.ts`
- Create: `apps/host-web/src/lib/gameSession.ts`
- Create: `apps/host-web/src/lib/wasm.ts`
- Modify: `apps/host-web/src/App.svelte`, `main.ts`

- [ ] **Step 1: Copy adapters**

```bash
mkdir -p apps/host-web/src/adapters apps/host-web/public/fonts
cp host_web/js_glue/webgpu_bridge.js apps/host-web/src/adapters/
cp -a host_web/js_glue/slug apps/host-web/src/adapters/
cp host_web/js_glue/fonts/NotoSans-Regular.ttf apps/host-web/public/fonts/
```

Fix any relative imports inside slug that break under new path (grep for `./` imports).

- [ ] **Step 2: Port constants and prefs**

`src/lib/intents.ts`:

```ts
export const INTENT_NONE = 0;
export const INTENT_ADVANCE = 1;
export const INTENT_SKIP = 2;
export const INTENT_OPEN_MENU = 3;
export const INTENT_TOGGLE_AUTO = 4;
export const INTENT_MENU_UP = 5;
export const INTENT_MENU_DOWN = 6;
export const INTENT_MENU_LEFT = 7;
export const INTENT_MENU_RIGHT = 8;
export const INTENT_OPEN_BACKLOG = 9;
```

`src/lib/prefs.ts` — load/save `localStorage` key `moonsight/prefs` with the same JSON shape as `boot.js`.

`src/lib/audio.ts` — extract BGM/SE HTMLAudioElement logic from `boot.js`.

`src/lib/wasm.ts` — `loadWasm(url: string): Promise<WebAssembly.Exports>` matching current instantiation.

`src/lib/gameSession.ts` — class or object that owns:

- exports, pendingIntent, ctrlHeld
- `start(canvas: HTMLCanvasElement): Promise<void>`
- `frame(ts: number): void` (rAF body from boot.js)
- keyboard/mouse handlers (same bindings as boot.js: Enter/Space/Z, Esc, arrows, H, Ctrl hold, 1–9, A, Ctrl+S/L)

**Rule:** Prefer moving code in chunks; behavior must match `host_web/js_glue/boot.js`. Do not invent new intent codes.

- [ ] **Step 3: Wire App.svelte**

OnMount: `gameSession.start(canvas)`; show status errors on failure (WebGPU missing message preserved).

- [ ] **Step 4: Manual smoke (dev)**

```bash
# terminal 1: ensure dist/demo assets exist
export CC=gcc
moon build --target wasm-gc --release host_web
cp _build/wasm-gc/release/build/host_web/host_web.wasm apps/host-web/public/host_web.wasm
# copy or symlink demo msb/manifest/assets into public for dev, OR
# vite proxy — simplest: copy from dist/demo after moonsightc build
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
cp dist/demo/game.msb dist/demo/manifest.json apps/host-web/public/ 2>/dev/null || true
cp -a dist/demo/assets apps/host-web/public/ 2>/dev/null || true
cp dist/demo/host_web.wasm apps/host-web/public/ 2>/dev/null || true
cd apps/host-web && npm run dev
```

Open `http://localhost:5173` with WebGPU browser; expect title screen.

- [ ] **Step 5: Production build**

```bash
cd apps/host-web && npm run build
# ensure dist contains index.html, assets, adapters hashed or public files
```

- [ ] **Step 6: Commit**

```bash
git add apps/host-web
git commit -m "feat(host-web): port boot loop to Svelte+TS with JS adapters"
```

---

### Task 9: moonsightc prefers Svelte host dist

**Files:**
- Modify: `cmd/moonsightc/build.mbt`
- Modify: `host_desktop/README.md`
- Modify: `docs/project-layout.md` (short note)

- [ ] **Step 1: Change discovery order**

In `find_js_glue` (rename conceptually to `find_host_shell` in comments):

```text
candidates order:
  1. apps/host-web/dist  (must contain index.html)
  2. host_web/js_glue    (fallback)
```

Implementation sketch:

```mbt
fn find_host_shell() -> String? {
  let candidates = [
    "apps/host-web/dist",
    "./apps/host-web/dist",
    "host_web/js_glue",
    "./host_web/js_glue",
    // ... existing parent walk for both
  ]
  // prefer path that has index.html; for dist also accept without boot.js
}
```

When copying from Svelte dist, still skip overwriting project `manifest.json`; still inject release `host_web.wasm` into out dir.

- [ ] **Step 2: Document build order in README**

```markdown
## Web host (Q2+)

1. `cd apps/host-web && npm i && npm run build`
2. `moon build --target wasm-gc --release host_web`
3. `moon run cmd/moonsightc --target native -- build demo/game -o dist/demo`
```

- [ ] **Step 3: Integration build**

```bash
cd apps/host-web && npm run build
export CC=gcc
moon build --target wasm-gc --release host_web
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
ls dist/demo/index.html dist/demo/host_web.wasm
```

Expected: files present; serve `dist/demo` and play title.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(moonsightc): prefer apps/host-web/dist as web shell"
```

---

### Task 10: Tauri shell uses new dist (smoke)

**Files:**
- Modify: `host_desktop/tauri/scripts/serve-dist.mjs` and/or `tauri.conf.json` if paths hard-coded to old layout
- Modify: `host_desktop/README.md`

- [ ] **Step 1: Read current paths**

Ensure desktop still loads `dist/demo` (or documented path). No React/Svelte inside Tauri required — it loads the built static host.

- [ ] **Step 2: Adjust docs only if needed; run `npm run dev` in tauri only if environment allows**

If CI-less machine: document manual verification; do not fail the plan if display is headless — note in commit message.

- [ ] **Step 3: Commit doc/path fixes**

```bash
git commit -am "docs(desktop): align Tauri with Svelte host dist"
```

---

## Track C — Fumadocs site

### Task 11: Scaffold `apps/docs-site`

**Files:**
- Create: `apps/docs-site/**` (Fumadocs app)

- [ ] **Step 1: Scaffold**

Preferred:

```bash
cd /mnt/nvme1n1p2/moonsight/apps
# Use official fumadocs create flow if network allows, e.g.:
# npm create fumadocs-app@latest docs-site
```

If interactive create is unavailable, hand-roll a minimal Next.js + `fumadocs-ui` + `fumadocs-mdx` app with:

- `package.json` scripts: `dev`, `build`, `start`
- MDX content source under `content/zh`, `content/en`
- i18n routing: `/zh/...`, `/en/...` (or Fumadocs i18n helper)

Pin **Next.js App Router** as required by Fumadocs.

- [ ] **Step 2: `npm install && npm run build`**

Expected: build succeeds (empty or placeholder pages ok).

- [ ] **Step 3: Commit**

```bash
git add apps/docs-site
git commit -m "chore(docs-site): scaffold Fumadocs bilingual docs app"
```

---

### Task 12: Core pages (zh + en) + migrate content

**Files:**
- Create: `apps/docs-site/content/zh/index.mdx` (or meta)
- Create: `apps/docs-site/content/zh/getting-started.mdx`
- Create: `apps/docs-site/content/zh/moon-yuki.mdx`
- Create: `apps/docs-site/content/zh/play-input.mdx`
- Create: matching `content/en/*.mdx`
- Modify: root `README.md` link to docs-site

- [ ] **Step 1: Information architecture**

```text
/zh                  Home
/zh/getting-started  Install, WebGPU, build demo, play
/zh/moon-yuki        from docs/moon-yuki-subset.md
/zh/play-input       from docs/play-input.md
/en/...              English equivalents
```

- [ ] **Step 2: Migrate**

- Getting Started: distill README quickstart + WebGPU Linux notes (both languages).  
- MoonYuki: port `docs/moon-yuki-subset.md` (zh can be primary translation; en can start as edited English of the same technical content — repo docs are already English; **zh pages need Chinese translation**, en can adapt existing English md).  
- Play input: port `docs/play-input.md` similarly.

Keep source of truth note at top of each page: "Engine behavior must match repo docs until migration completes; Q2 core pages are authoritative for listed topics."

- [ ] **Step 3: Build**

```bash
cd apps/docs-site && npm run build
```

Expected: success.

- [ ] **Step 4: Commit**

```bash
git commit -am "docs(docs-site): Getting Started, MoonYuki, play-input zh/en"
```

---

### Task 13: Hygiene + Q2 acceptance checklist

**Files:**
- Modify: `README.md` Scope section for Q2
- Modify: `docs/project-layout.md` for `apps/`
- Optional: `docs/superpowers/specs/2026-07-11-moonsight-roadmap-v2-design.md` — no change required unless dates

- [ ] **Step 1: Full verify**

```bash
export CC=gcc
moon check
moon test
cd apps/host-web && npm run build && cd ../..
cd apps/docs-site && npm run build && cd ../..
moon build --target wasm-gc --release host_web
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

Expected: all green / success.

- [ ] **Step 2: Manual play checklist (record in commit or PR body)**

- [ ] Title → Start → dialogue  
- [ ] Dissolve visible mid-demo  
- [ ] Scale tween visible  
- [ ] Ctrl skip still respects `@flow.wait`  
- [ ] H backlog / Esc menu still work on **Svelte** host  
- [ ] Docs site `/zh/getting-started` and `/en/getting-started` render  

- [ ] **Step 3: Final commit**

```bash
git commit -am "docs: Q2 scope, apps layout, acceptance notes"
```

---

## Parallelism guide

| Order | Tasks | Notes |
|------|-------|--------|
| 1 | Tasks 1–6 | Engine serial (scale → save → render → commands → dissolve → demo) |
| 2 | Tasks 7–10 | Host can start after Task 6 **or** parallel once Task 1 lands if demo not required for host smoke |
| 3 | Tasks 11–12 | Docs fully parallel with Engine/Host |
| 4 | Task 13 | After all tracks |

Conflict rule (from roadmap): if Host/Docs slip, **ship Engine Tasks 1–6** and leave Host fallback on `js_glue`; do not block dissolve/scale on Svelte polish.

---

## Self-review (plan vs roadmap Q2)

| Roadmap Q2 requirement | Task |
|------------------------|------|
| `trans.dissolve` | Task 5–6 |
| layer scale (min set; no rotate required) | Tasks 1–4, 6 |
| voice **or** SE — chose **neither deep**; SE status quo | explicit pin |
| mid-length demo skeleton | Task 6 |
| wait/fade/tween/skip consistency docs | Tasks 5–6 |
| Svelte+TS skeleton, boot, adapters | Tasks 7–8 |
| default playable path | Task 9–10 |
| Fumadocs IA + core bilingual pages | Tasks 11–12 |
| Hygiene / P0 | Task 13 |
| Editor / ScrollView / publish | out of scope ✓ |

**Placeholder scan:** none intentional.  
**Type consistency:** `TweenProp::Scale`, `LayerState.scale`, save v4, `trans.dissolve` name used throughout.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-11-moonsight-q2-multitrack.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — this session with executing-plans and checkpoints  

Which approach?
