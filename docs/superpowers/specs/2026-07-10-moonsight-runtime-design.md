# MoonSight Phase 1 — 运行时内核设计

**日期：** 2026-07-10  
**状态：** Draft for implementation planning  
**仓库：** `moonsight`（工作区根）

## 1. 背景与目标

### 1.1 问题

需要一款**通用视觉小说引擎**：作者可编写叙事脚本，引擎在浏览器中以现代图形 API 呈现完整画面，并可通过桌面壳分发。技术选型为 **MoonBit + WebGPU**，脚本体系以 [YukimiScript](https://github.com/Strrationalism/YukimiScript) 的设计理念为基底，在 MoonBit 中**重写**解析与编译，并允许**魔改语法与语义**（不追求与官方源码/字节码 100% 兼容）。

### 1.2 产品定位

| 维度 | 选择 |
|------|------|
| 目标用户 | 引擎使用者 / 游戏作者（通用框架，非单作专用） |
| 运行平台（Phase 1） | **浏览器为主** + **桌面壳**（同一套 Wasm + WebGPU） |
| 脚本 | **MoonYuki**（暂名）：Yukimi 风格 DSL，MoonBit 实现编译器 |
| 执行模型 | 编译为 **IR / 字节码**，运行时 **解释执行** |
| 渲染 | **WebGPU 全场景合成**（背景、立绘、特效、对话框、选项、文字均 GPU 绘制，无 DOM UI） |
| 长期愿景 | 接近完整产品（编辑器、本地化、成就、资源管线等）——**分期交付** |

### 1.3 本规格范围

本文件只定义 **Phase 1：运行时内核**。后续子系统各自独立规格与实现计划。

**Phase 1 包含：**

- MoonYuki 词法/语法/宏展开/基础类型检查 → IR / 字节码
- IR VM、Director、Stage、图层栈
- WebGPU 精灵批处理、UI 几何、字形纹理图集、基础转场
- 对话（打字机）、选项、变量与条件分支、scene 跳转
- 基础 BGM / SE
- 存读档
- 标准 host 命令表与文档
- 浏览器入口 + 最小桌面壳集成
- 可玩 demo + CLI 编译/检查工具
- 核心包自动化测试

**Phase 1 明确不包含：**

- 可视化编辑器
- 完整本地化 / 成就系统
- Live2D 或 3D
- 与官方 YukimiScript 字节码二进制互通
- 非 Web 的第二渲染后端（Vulkan/Metal 原生路径）
- 商业级安装器、自动更新、资源商店

## 2. 架构总览

### 2.1 选定路线：分层剧院模型

剧本命令驱动「导演」修改「舞台」；渲染器每帧只读舞台快照。不采用完整 ECS 作为 Phase 1 核心（允许 Stage 内轻量 id 索引对象）。

```
Author: *.yuki + assets
        │
        ▼
Script Compiler (MoonBit)
  Lexer → Parser → Macro → Resolve/Typecheck → IR → Bytecode (.msb)
        │
        ▼
Runtime Kernel
  IR VM ──Host calls──► Director ──mutates──► Stage (authoritative)
        │                                      │
        │                                      ▼
        │                                   Layer stack + vars + UI mode
        │                                      │
        │                              snapshot (read-only)
        ▼                                      ▼
Input → Intent                          WebGPU Renderer
        │                                      │
        └──────── resume Yield/Choose ─────────┘
                       │
                       ▼
                 Host Shell (Web page / Desktop shell)
```

### 2.2 核心原则

1. **Stage 是唯一权威场景状态**；Renderer 禁止回写玩法状态。  
2. **脚本只通过 host 命令改变世界**；VM 保持通用控制流 + `Host` 调用。  
3. **存档 = VM 执行状态 + Stage 逻辑快照 + 变量**，不含 GPU 句柄。  
4. **平台差异收口在 host-\***（加载、存档路径、窗口）；游戏逻辑与渲染核心共享。  
5. **依赖单向**：`script` 不依赖 `render`；`runtime` 不依赖具体 GPU API。

## 3. 脚本方言与编译管线（MoonYuki）

### 3.1 设计取向

保留 Yukimi 的**写作手感**，不为官方兼容做捆绑：

| 保留 | 可魔改 |
|------|--------|
| 按行解析 | 关键字集合、内建命令名 |
| `- scene` / `- macro` / `- extern` 风格声明 | 模块系统、类型细节 |
| `角色:对白` 文本行 | 内联标记语法 |
| `@command key=val --flag` | 与引擎绑定的标准命令 |
| scene 继承/状态延续思路 | 编译产物格式 |

### 3.2 编译管线

```
.yuki source
  → line-oriented Lexer
  → Parser → AST
  → Macro expansion
  → Name/type resolution (scenes, externs, vars)
  → Lower → IR
  → Bytecode emit (.msb) + debug map (source ↔ instruction)
```

- **开发期：** 可直接解释 IR，保留完整源映射。  
- **发布期：** 加载字节码包 + 资源清单；浏览器与桌面使用同一产物格式。

### 3.3 IR 模型

指令分两类：

1. **控制流：** `Call` / `Return` / `Jump` / `JumpIf` / `Choose` / `Yield` 等。  
2. **Host 调用：** `Host(op, args)` → Director 执行。

对话在 Lower 阶段展开为 host 序列（类似 Yukimi 的 `__text_begin` / `__text_type` / `__text_end`），避免在 VM 内核 hardcode 叙事语法。

### 3.4 Phase 1 语法必做子集

- 极简模块/多文件引入  
- `extern` / `macro` / `scene`  
- 对白行 + 基础内联（变量插入、暂停）  
- `@` 命令：位置参数、命名参数、flag  
- 变量与条件跳转  
- 选项（`menu` 或等价 `@choice` 结构）  
- 注释  

**延后：** 复杂类型体操、官方 diagram 元数据、官方字节码兼容。

### 3.5 与引擎契约

`extern` 声明绑定 **Host API**。引擎提供标准命令组；游戏或插件可注册额外 handler。未声明或签名不符的调用在**编译期**报错。

## 4. 运行时：VM · Director · Stage

### 4.1 组件职责

| 组件 | 职责 | 不负责 |
|------|------|--------|
| IR VM | 控制流、host 调用、在 Yield/Choose 挂起 | 像素 / GPU |
| Director | 将 host 落到 Stage（图层、文本、音频、变量） | 绘制 |
| Stage | 权威状态：图层树、UI 模式、变量、scene、进行中转场 | 执行脚本 |
| Renderer | 读 snapshot，WebGPU 合成 | 改玩法状态 |
| Input | 映射为 Intent（Advance / Select / Skip / Auto / OpenMenu…） | 直接改 IP |

### 4.2 图层栈（自下而上）

1. Background  
2. Characters / CG（z 序、位置、表情/变体资源 id）  
3. Effects  
4. UI · 对话框 + 名字 + 正文  
5. UI · 选项 / 系统菜单  
6. Overlay · 淡入淡出 / 转场遮罩  

图层节点可动画属性至少包括：`opacity`、`transform`、`color_mul`、可见性。转场通过对属性 tween + 可选全屏 veil 实现。

### 4.3 帧循环

1. 收集输入 → Intent  
2. 若 VM 处于 Yield/Choose：按 Intent 恢复（补全打字、推进、选择选项）  
3. VM 执行直至再次挂起或本帧指令预算用尽  
4. Director 更新；tick 动画/转场  
5. Renderer 提交 WebGPU  

### 4.4 叙事语义

- **打字机：** Stage 持有当前文本块；Advance 先补全再下一句。  
- **选项：** `Choose` → Stage 展示 → 用户选择写入结果并 resume。  
- **快进/自动：** 策略根据设置合成 Advance Intent；遇强制等待或选择则停下。

### 4.5 存档

快照字段：

- 模块/剧本 id + 指令指针 + 调用栈  
- 变量表  
- Stage 可恢复视图（资源 **逻辑 id** 与属性，非 GPU 句柄）  
- RNG 种子（若使用）  
- 音频逻辑状态（曲目 id、循环、音量目标）  

读档：恢复 VM + Stage；Renderer 按资源 id 重新绑定纹理。存档含**格式版本**；不兼容时拒绝加载并给出明确错误，禁止静默坏档。

### 4.6 扩展

新玩法 = 新 host 命令 + 可选新 Layer 类型。不在 Phase 1 引入完整 ECS。

## 5. WebGPU 渲染与文字

### 5.1 目标

所有玩家可见元素进入同一 WebGPU 渲染图（**无 DOM 对话框/选项**）。

### 5.2 Phase 1 渲染路径

1. 上传脏纹理 / 维护 glyph atlas  
2. **Sprite batch**：背景、立绘、九宫格/面板 UI  
3. **Text pass**：字形四边形  
4. **Fullscreen veil**：淡入淡出等  
5. Present 到 canvas  

不强制多离屏后处理链；自定义全屏 shader 接口可预留，完整特效栈后期。

### 5.3 文字

- CPU 侧布局（换行、对齐、基础富文本预留）  
- TTF（打包或平台可加载）→ 光栅化 → **动态 glyph atlas**  
- Phase 1 富文本下限：颜色、打字速度相关 mark；ruby/复杂排版后置  
- 后期可选 SDF 文字  

### 5.4 坐标与适配

- 逻辑分辨率（可配置，如 1920×1080）  
- 输出 letterbox / pillarbox 保持宽高比  
- UI 与精灵统一逻辑坐标，避免多套像素空间  

### 5.5 资源

- 纹理：PNG/WebP（具体格式在实现计划中钉死一种主格式）  
- 逻辑资源 id → URL/包内路径映射表  
- 缺失资源：加载期失败并诊断，不进入无提示黑屏  

### 5.6 设备丢失

监听/检测 GPU device lost → 尝试重建 device 与资源绑定；失败则显示宿主层友好错误。

## 6. 模块划分、宿主与 API

### 6.1 建议包结构

```
moonsight/
  moon.mod.json
  packages/
    script/           # 词法/语法/宏/类型/IR/字节码
    runtime/          # VM、Director、Stage、变量、存档
    render/           # WebGPU 抽象、batch、文字、转场
    audio/            # 逻辑音频 + 后端接口
    host-web/         # 浏览器入口、canvas、输入、fetch
    host-desktop/     # 桌面壳胶水（最小）
    std-commands/     # 标准 host 实现
    demo/             # 示例作品
  tools/
    moonsightc/       # CLI：编译、检查、打包
  docs/
```

### 6.2 桌面策略（Phase 1）

**不双写渲染后端。** 桌面壳承载同一套 Wasm + WebGPU（WebView 或等价方案）。原生第二后端不在 Phase 1。

| 能力 | Web | Desktop |
|------|-----|---------|
| 呈现 | canvas + WebGPU | 壳内嵌同一技术栈 |
| 资源 | fetch / 静态托管 | 本地文件 + 自定义协议（可选） |
| 存档 | localStorage 或 OPFS | 用户目录文件 |
| 音频 | Web Audio | 同 Web 栈优先 |

### 6.3 标准 host 命令组（Phase 1）

| 组 | 用途 |
|----|------|
| `flow.*` | scene 跳转、等待、选项 |
| `text.*` | 对白 begin/type/end、名字、清除 |
| `layer.*` | 背景/立绘 show/hide/move/换图 |
| `trans.*` | fade、简单 dissolve |
| `var.*` | 变量读写（或语法糖降到此） |
| `audio.*` | BGM/SE play/stop/fade |
| `sys.*` | 存档点提示、回标题（最小） |

### 6.4 作者触点

1. 脚本：文档化的 MoonYuki 子集 + 标准命令表  
2. 可选 MoonBit 插件：注册自定义 host / 高级绘制回调  
3. CLI：`moonsightc build` 产出可部署目录（wasm + msb + assets + index）

## 7. 错误处理

| 阶段 | 策略 |
|------|------|
| 编译期 | 诊断带文件/行/列；未知 extern、类型错误必须失败；宏错误指向调用点 |
| 加载期 | 资源缺失、字节码版本不匹配 → 可读错误 |
| 运行期可恢复 | 非法 host 参数：dev 断言 / 调试 HUD；release 可配置 fail-soft 或硬停 |
| 运行期不可恢复 | device lost 重建失败 → 友好错误页 |
| 存档 | 版本 + 拒绝不兼容档 |

开发模式调试 HUD（WebGPU 绘制）：当前 scene、IP、最近 host、图层列表。

## 8. 测试策略

1. **script：** golden tests（源 → AST/IR 或诊断）  
2. **runtime：** 无 GPU 的 VM + Director（mock host → 断言 Stage/变量）  
3. **存档：** 序列化 round-trip  
4. **render：** 布局与 atlas 键等纯逻辑；像素对比非 Phase 1 门槛  
5. **demo 路径：** 标题 → 对话 → 选项 → 存读档（mock 或半自动）  
6. **浏览器冒烟：** WebGPU 初始化 + 一屏对话  

CI 至少跑 `script` + `runtime`（及不依赖真实 GPU 的测试）。

## 9. 成功标准（Phase 1 验收）

1. 使用 MoonYuki 编写并编译 demo：多 scene、对白、选项、变量分支、换背景/立绘、BGM/SE、淡入淡出。  
2. 在 WebGPU 可用的桌面 Chrome/Firefox 最新版完整玩通 demo。  
3. 存档 → 重启 → 读档恢复叙事位置与画面关键逻辑状态。  
4. 桌面壳加载同一构建产物并完成同样路径。  
5. 文档齐备：语法子集、标准 host 表、工程目录约定。  
6. 核心包测试在 CI 可重复通过。

## 10. 后期路线图（非本规格实现范围）

顺序建议（可调）：

1. **资源与打包管线**（多分辨率、哈希缓存、压缩包）  
2. **可视化编辑器 / 实时预览**（复用 IR 解释与 Stage snapshot）  
3. **本地化**（字符串表、字体回退、RTL 若需要）  
4. **成就与系统菜单增强**  
5. **高级渲染**（SDF 字、粒子、自定义后处理）  
6. **可选 native 图形后端**

## 11. 开放实现细节（计划阶段钉死，不阻塞本设计）

以下不影响架构选择，留给 implementation plan：

- 桌面壳具体技术（Tauri / Wry / 其它）  
- 字节码二进制布局与 `.msb` 魔数  
- 主推纹理格式与音频格式  
- 默认逻辑分辨率与安全区  
- 许可证（建议实现前选定，便于接收贡献）  
- 「MoonYuki」是否保留为正式方言名  

## 12. 决策记录摘要

| 决策 | 选择 |
|------|------|
| 产品类型 | 通用引擎/框架 |
| 平台 | 浏览器 + 桌面壳 |
| 脚本根基 | Yukimi 风格，MoonBit 重写，魔改优先于官方兼容 |
| 执行 | IR/字节码解释 |
| 架构 | 分层剧院（Stage 权威） |
| 渲染 | WebGPU 全合成含 UI/文字 |
| Phase 1 焦点 | 运行时内核，非完整产品一次做完 |
