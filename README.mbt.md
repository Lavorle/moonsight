# MoonSight

**中文** | [English](./README.en.md)

基于 MoonBit + WebGPU 的视觉小说引擎（Phase 1–4 + Q1/0.5 + Q2 多轨 + Q3/0.8
系统 UI + **Q4 / 1.0 候选**发布路径：`moonsightc new`、仅 Svelte 构建、
SaveStore Web/桌面、样章、发布脚本）。

MoonYuki 脚本编译为 IR/字节码，在 VM + Stage/Director 上运行，经打包后的
draw list 由 JS WebGPU Host 绘制。系统菜单与对白 HUD 使用常驻 MoonBit UI 树
（`std_ui` + 可选项目 `ui_package`）。桌面端在精简 Tauri 壳中加载同一套 Web 构建。

## 快速开始

```bash
# 在仓库根目录
export CC=gcc

# 类型检查 + 单元测试
moon check
moon test

# Svelte Host 壳（moonsightc build 必需）
cd apps/host-web && npm i && npm run build && cd ../..
moon build --target wasm-gc --release host_web

# 编译示例游戏并打包 Web dist（demo 配置了 ui_package → 会重建 host wasm）
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo

# 浏览器游玩（需要 WebGPU；请用 localhost，不要用 file://）
cd dist/demo && python3 -m http.server 8080
# 打开 http://localhost:8080/
```

从空项目脚手架（复制 `templates/minimal`）：

```bash
export CC=gcc
moon run cmd/moonsightc --target native -- new mygame
cd apps/host-web && npm i && npm run build && cd ../..
moon run cmd/moonsightc --target native -- check mygame
moon run cmd/moonsightc --target native -- build mygame -o dist/mygame
```

一键 Web 打包：`./scripts/publish-web.sh [project] [out]`（默认
`demo/game` → `dist/demo`）。桌面：`./scripts/publish-desktop.sh`（见
[`host_desktop/README.md`](./host_desktop/README.md)）。

## Web Host（Svelte）

`moonsightc build` 会从 **`apps/host-web/dist`** 复制 **Svelte** Web 壳
（需要 `index.html`）。请先构建该壳，再打包游戏。

```bash
export CC=gcc
cd apps/host-web && npm i && npm run build && cd ../..
moon build --target wasm-gc --release host_web
moon run cmd/moonsightc --target native -- build demo/game -o dist/demo
```

若无 `ui_package`，moonsightc **不会**自动重建 wasm — 开发时如需可手动刷新到
Svelte `public/`：

```bash
moon build --target wasm-gc --release host_web
cp _build/wasm-gc/release/build/host_web/host_web.wasm apps/host-web/public/
```

### 浏览器 / WebGPU（Linux 上尤其重要）

MoonSight **需要 WebGPU**，没有 WebGL 回退。

| 浏览器 | 说明 |
|---------|--------|
| **Chrome / Edge / Chromium** | 首选。**Linux** 上如有需要请开启下列 flags。 |
| **Brave** | Chromium 系；Linux 上通常与 Chrome 相同 flags。 |
| **Firefox** | WebGPU 在 Windows/macOS 上更完整；**Linux 仍偏实验**，常需 `about:config` 或 Nightly。 |

**Brave / Chrome（Linux）— 若出现 `WebGPU not available`：**

1. 打开 `brave://flags` 或 `chrome://flags`
2. 启用 **Unsafe WebGPU Support**（`#enable-unsafe-webgpu`）
3. 启用 **Vulkan**（`#enable-vulkan`）— Linux 上通常必需
4. 可选：**Ignore GPU blocklist**（`#ignore-gpu-blocklist`）
5. 重启后查看 `brave://gpu` / `chrome://gpu`（WebGPU 不应为 “Disabled”）

命令行：

```bash
brave-browser --enable-unsafe-webgpu --enable-features=Vulkan --use-angle=vulkan http://localhost:8080/
# 或: google-chrome --enable-unsafe-webgpu --enable-features=Vulkan ...
```

**Firefox：**

1. `about:config` → 设置 `dom.webgpu.enabled` = `true`
2. 可再试 `gfx.webgpu.force-enabled` 和/或 `gfx.webgpu.ignore-blocklist` = `true`
3. 重启；若仍无 `navigator.gpu`，请用 **Firefox Nightly** 或 Chromium 系浏览器

务必通过 **`http://localhost`**（或 https）提供服务。直接打开 `file://` 会拦截 WebGPU。

**输入：** 冷启动在 **标题**（Start → 入口场景）。指针经引擎命中测试
`export_pointer`（按钮 / 选项 / 滑条；Playing 空点击 → Advance；移动 = hover +
光标；离开清除 hover）。同帧：先 pointer 再 `export_frame(0, dt, skip)` — 不会
双重 Advance。键盘：Enter / Space / Z 推进（或激活聚焦菜单按钮）；**Esc** 系统
菜单；**↑↓** / W/S 聚焦；**←→** 设置滑条；**H** 履历；**按住 Ctrl** 快进；1–9
选选项；A 自动；Ctrl+S / Ctrl+L 快捷存读档位 0（`localStorage`）。计时
`@flow.wait` 在倒计时结束前忽略 Advance/skip。菜单会暂停叙事 Advance。完整语义见
[`docs/play-input.md`](./docs/play-input.md)。

**主题：** 默认 **Amber Soft** 包位于 `themes/amber_soft`（逻辑 `ui.*` 角色；
Host 纯色 + 可选 PNG）。作者说明：
[`docs/ui-moonbit.md`](./docs/ui-moonbit.md#themes)。

**桌面壳：** 先构建 `dist/demo`，再看
[`host_desktop/README.md`](./host_desktop/README.md)。桌面存档用 **appData**
（`DesktopSaveStore`）；浏览器用 **`localStorage`** — 槽位 **不互通**。

## 包一览

| 路径 | 职责 |
|------|------|
| `script` | MoonYuki → IR / `MSB1`（拒绝项目 `- screen`） |
| `runtime` | VM、Director、Stage、UiApp/UiRuntime、prefs、存档 (v4)、tween + scale |
| `render` | draw list 打包、文字布局、kind+z 排序、scale→精灵尺寸、`UiDrawOp` 绘制 |
| `audio` | 逻辑 BGM/SE 混音（音量 / 淡入淡出） |
| `std_commands` | 标准 `@` Host 命令（图层、dissolve、ui.show/hide、音频） |
| `std_ui` | 默认 HUD + 标题 / 游戏菜单 / 存读档 / 设置 / 确认 / 履历 |
| `host_web` | 浏览器 wasm Host（WebGPU 入口；壳在 `apps/host-web`） |
| `apps/host-web` | Svelte+TS Host 壳（**moonsightc 必需**；先构建 `dist/`） |
| `host_desktop` | Tauri 2 壳（appData SaveStore） |
| `cmd/moonsightc` | `new` / `check` / `build` CLI（脚手架、资源检查、可选 ui_package） |
| `templates/minimal` | `moonsightc new` 的源树 |
| `demo/game` | 示例项目（+ 可选 `ui/` 覆盖） |

## 文档

**站点：** 双语 Fumadocs 应用位于 [`apps/docs-site`](./apps/docs-site) —
入门（含 `new`）、MoonYuki、游玩输入、UI、**发布**、**桌面**（中 + 英）。
在该目录：`npm install && npm run dev` →
`http://localhost:3000`（默认 `/zh`）。

仓库内 Markdown（迁移完成前的引擎真相源；站点上 Q2 核心页面对所列主题为准）：

- [`docs/moon-yuki-subset.md`](./docs/moon-yuki-subset.md) — 语法子集
- [`docs/ui-moonbit.md`](./docs/ui-moonbit.md) — MoonBit UI 作者指南（HUD + 模态）
- [`docs/host-commands.md`](./docs/host-commands.md) — Host 命令表 + intents
- [`docs/play-input.md`](./docs/play-input.md) — intents、快进按住、wait 门控、履历/确认
- [`docs/project-layout.md`](./docs/project-layout.md) — 仓库布局与 `moonsight.json`
- [`docs/draw-list-pack.md`](./docs/draw-list-pack.md) — 帧打包格式
- [`docs/screen-language.md`](./docs/screen-language.md) — 已废弃的 Phase 3 Screen DSL 存档

## 范围

### Phase 1（运行时内核）

**包含：** 编译管线、VM、图层、对白打字、选项、变量、跳转、BGM/SE、淡入淡出、
存读档、浏览器 Host、桌面壳、demo、CLI、测试。

### Phase 2（图层与呈现）

**包含：** `@layer.show kind=…` 的 `LayerKind`、线性 `x`/`y`/`opacity` duration
tween、`@layer.set`、墙钟 `trans.fade`（`fade_remaining`）、真正的
`@flow.wait` 计时（不可跳过）、存档格式 **v3**（tween + wait/fade 剩余；v2 仍可
加载）、构建期字面量资源检查、贴图加载硬失败、更新后的 demo/文档。

### Phase 3（Screen UI + 系统菜单）

**包含（历史路径）：** Screen DSL + 运行时栈/焦点、标准四屏、多槽存档 + prefs、
冷启动标题、WebGPU 绘制的控件、`@ui.show`/`@ui.hide`、命名负数、音频加载硬失败、
BGM 音量/淡入淡出。

### Phase 4（MoonBit UI 内核）

**包含：** 常驻 `UiApp` / `UiRuntime`（HUD + 模态栈）、Capabilities + 按钮处理器、
`std_ui` 默认 HUD 与四模态、可选项目 `ui_package` 链入同一 host wasm、对白/选项
仅经 HUD 树绘制、项目 `- screen` 硬错误、无 `screens.json` 主 dist 路径、demo
覆盖样例 + 作者文档。

### Q1 / 0.5（可玩核心）

**包含：** 会话 **履历**（环缓冲 100；H / History；不写入存档）；**按住 Ctrl**
`skip_held` 爆发推进（每帧最多 8；不计时 wait 跳过；不自动选项）；覆盖存档 +
回标题的 **确认**（默认焦点 No）；**prefs → 混音器** 增益（master/bgm/se）；
设置 **Slider**（←/→）；槽位标签在有值时显示 `saved_at`；输入/wait 语义见
[`docs/play-input.md`](./docs/play-input.md)。

### Q2（引擎呈现 + 多轨）— 已交付

**引擎：** `@trans.dissolve duration` 双相全屏遮罩（墙钟时长内 0→1→0；非阻塞，
与 `@flow.wait` 配合）；`@layer.show` / `@layer.set` 的 `scale=` 及线性
`duration=` tween（原点左上角 `(x,y)`；无旋转/锚点）；存档格式 **v4**（图层
`scale`；v3 加载时默认 `scale=1.0`）；更长的 demo（`demo/game`）含 dissolve/scale
节拍与额外花园/长椅场景；dissolve/scale 与呈现 vs wait/skip 文档见
[`docs/host-commands.md`](./docs/host-commands.md) /
[`docs/play-input.md`](./docs/play-input.md)。语音轨与深度 SE 明确 **不在**
范围内（SE 维持现状）。

**Host：** Vite + Svelte 5 + TypeScript 壳位于 [`apps/host-web`](./apps/host-web)，
WebGPU/Slug 适配器在 `src/adapters/`。`moonsightc build` 需要
`apps/host-web/dist`（`index.html`）。在 `apps/host-web` 执行 `npm run build`
后再 `moonsightc build` 的默认可玩路径即为 Svelte 壳。

**文档：** Fumadocs（Next.js）双语站点位于
[`apps/docs-site`](./apps/docs-site) — 入门、MoonYuki 子集、游玩输入、发布、桌面
（**中** 与 **英**）。路由：`/{lang}/docs/getting-started`（及
`/{lang}/docs/…` 下兄弟页）。默认语言 **zh**。仓库 `docs/*.md` 对未迁移主题仍为
引擎真相源。

### Q3 / 0.8（系统 UI）— 自动化门禁绿

**包含：** 纵向 `UiNode::ScrollView`（裁剪、滚动条 track/thumb），履历模态使用
（绑定整环，打开时钉到最新）；滚轮 + 内容拖动 + 条拖动 + ↑/↓ 行滚动；指针
**phase 2**（`pointerup`）结束拖动且不触发 Advance；双 Host 滚轮符号
（`dy = -deltaY`）与 **Ctrl blur/visibility** 清除粘滞快进；确认统一（覆盖存档 /
回标题，默认 **No**）；槽位空/满主题图标；滚动 + 槽位主题角色；Host 全局面板
加载/错误；`layer.show`/`set` 的 **scale** 在 builtins 与 std_commands 两条路径；
中途 dissolve 读档 **硬清除** dissolve 遮罩；菜单/快捷存 Host 盖戳 `saved_at`
供槽位标签；作者文档 + Fumadocs 中英（play-input + UI）。见
[`.superpowers/sdd/q3-final-verify-report.md`](./.superpowers/sdd/q3-final-verify-report.md)。

**自动化门禁（0.8）：** `export CC=gcc` 后执行 `moon check`、`moon test`、
`moon build --target wasm-gc --release host_web`、
`moon run cmd/moonsightc --target native -- build demo/game -o dist/demo`、
`apps/host-web` 的 `npm run build`、`apps/docs-site` 的 `npm run build` — 全部
exit 0。

**手动 D6（WebGPU 浏览器）：** 标题 → Start → 长履历滚动（滚轮 / 拖动 / 条 /
↑↓）→ Close/Esc；鼠标 Advance / 选项 / Esc 菜单 / 覆盖确认默认 No；dissolve +
scale 可见；Ctrl 快进 vs `@flow.wait`；blur 清除快进；强制错误路径文案。
**推迟到人工浏览器**（与 Pointer Theme 相同的诚实策略）— 不在 CI/agent 无头环境
宣称通过。

### Q4 / 1.0 候选（发布）— 自动化联合门禁绿

**包含：** 从 [`templates/minimal`](./templates/minimal) 的
`moonsightc new <name> [-o parent]`；`moonsightc build` **硬依赖**
[`apps/host-web/dist`](./apps/host-web)（Svelte 壳；缺失时明确 `npm run build`
错误 — **无** `js_glue` 回退；退役源码在
[`archive/js_glue`](./archive/js_glue)）；Host **SaveStore**
（`WebSaveStore` = 不变的 `localStorage` 键；`DesktopSaveStore` = Tauri appData
`…/moonsight/prefs.json` + `saves/{n}.json`；Web 槽位 ≠ 桌面）；引擎存档 JSON
仍为 **v4**；demo 样章骨架（约 30–60 分钟弧）在 [`demo/game`](./demo/game)；
`./scripts/publish-web.sh` + `./scripts/publish-desktop.sh`；作者文档（仓库 +
Fumadocs 中英：new / publish / desktop）；可选 `check` 未知 `@flow.jump` 场景目标。

**自动化门禁（1.0 候选）：** `export CC=gcc` 后 `moon check`、`moon test`、
`moon build --target wasm-gc --release host_web`、`apps/host-web` `npm run build`、
`moonsightc new` + `check` + `build`、`moonsightc build demo/game -o dist/demo`、
`apps/docs-site` `npm run build`、无 Svelte dist 时 build **失败**、
`localStorage` 仅出现在 `apps/host-web/src/lib/saveStore.ts` — 全部绿。见
[`.superpowers/sdd/q4-final-verify-report.md`](./.superpowers/sdd/q4-final-verify-report.md)。

**手动 W1（WebGPU 浏览器可玩 + localStorage 存读）：** 标题 → Start → 推进 →
Esc 存档 → 重载 → 读档。agent CI 中 **推迟**：无头 Chromium 有 `navigator.gpu`
但 `requestAdapter()` 为 null（无 WebGPU 适配器）。dist 对 index/wasm/msb/manifest
返回 200；错误面板诚实。宣称可玩需人工 WebGPU 浏览器。

**手动 D1（桌面 appData 存读）：** Tauri GUI 存档 → 退出 → 从 appData 读档。
无交互 GUI 会话 / 同样 WebGPU 限制时 **推迟** — 清单见
[`host_desktop/README.md`](./host_desktop/README.md)。禁止假绿。

正式 **1.0 发布**（硬化、Host 全量收口、rollback/i18n 缓冲）仍属 **Q5**。

### 范围外 / 推迟到 Q5+

可视化编辑器、超出 docs-site 语言环境的完整产品 i18n、成就、Live2D / 3D、
粒子/后处理栈、完整时间轴 / 动画队列、阻塞式呈现 DSL、旋转/锚点、语音轨、
槽位截图、横向 / 嵌套 ScrollView、列表虚拟化、惯性/橡皮筋、履历写入存档槽、
rollback、DOM 游戏菜单、第二套原生 GPU 后端、第二套 wasm / 动态 UI 加载、运行时
主题切换器 / 多主题商店、变换动画栈、开放 Host 字符串 UI 动作、官方 Yukimi
字节码兼容、长期 Screen DSL 下沉兼容、Host adapter 零 JS / 全量收口、交互式
WebGPU CI、将 wasm 构建产物提交进 git、云存档 / Web↔桌面槽位迁移。
