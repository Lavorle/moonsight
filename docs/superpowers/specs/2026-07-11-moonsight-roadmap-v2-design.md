# MoonSight — 多轨产品路线图总览 v2（12–18 个月）

**日期：** 2026-07-11  
**状态：** Approved design (multi-track roadmap overview; not a single-quarter implementation spec)  
**仓库：** `moonsight`  
**升版对象：** [路线图 v1](./2026-07-11-moonsight-roadmap-design.md)（已 **Superseded** 由本文件）  
**前序（已交付）：**  
- [Phase 1 运行时内核](./2026-07-10-moonsight-runtime-design.md)  
- [Phase 2 图层与演出语义硬化](./2026-07-10-moonsight-phase2-layers-design.md)  
- [Phase 3 Screen 语言与系统 UI](./2026-07-10-moonsight-phase3-screen-ui-design.md)  
- [Phase 4 MoonBit UI 内核](./2026-07-10-moonsight-phase4-ui-kernel-design.md)  
- [Q1 可认真玩 / 0.5](./2026-07-11-moonsight-q1-playable-design.md)（实现已落地：backlog、skip hold、confirm、Slider、prefs→mixer）  

**下一实现入口：** **Q2** 独立 brainstorm → design + implementation plan（Engine 演出主交付 + Host/Docs 并行轨骨架）。本文件**不**直接进入单季 SDD 任务切片。

---

## 1. 背景与北极星

### 1.1 现状（Phase 1–4 + Q1/0.5）

MoonSight 是 **MoonBit + WebGPU** 通用视觉小说引擎（非单作）。已交付：

| 层 | 能力 |
|----|------|
| 脚本 | MoonYuki 子集 → IR / `MSB1`；多文件 scene merge；macro / extern / 条件跳转 / 选项 |
| 运行时 | VM、Director、Stage、图层 tween、`trans.fade`、timed `flow.wait`、存档 v3、prefs、多槽 |
| UI | retained `UiApp` / `UiRuntime`；`std_ui` 默认模态 + 对话 HUD + backlog/confirm；可选 `ui_package` |
| 播放器标配 (Q1) | 会话 backlog、Ctrl hold skip、覆盖存档/回标题 confirm、prefs 音量驱动 mixer、Settings Slider、槽 `saved_at` |
| 渲染 / 音频 | 打包 draw list + WebGPU host；逻辑 BGM/SE mixer × prefs gains |
| 工具 / 宿主 | `moonsightc check/build`；**vanilla JS** `js_glue` 浏览器 host；Tauri 桌面壳；短 demo |
| 文档 | 仓库内 `docs/*.md`（尚未 Fumadocs 站点） |

架构原则保持不变：**Stage 叙事权威**；脚本只经 host 改世界；UI 经闭合 **Capabilities**；render 只读绘制数据；项目 `- screen` 已切断；**游戏内 UI 不走 DOM**。

### 1.2 问题（相对 v1 + 新意图）

v1 已覆盖引擎价值链缺口（演出、系统 UI、发布、1.0）。新增结构性需求：

1. **宿主现代化：** 希望 **Svelte + TypeScript 尽量全量** 重写 host 侧（除 wasm 与 third_party Slug），便于维护与后续编辑器共享栈。  
2. **正式文档站：** monorepo 内 **Fumadocs**，**作者优先、中英双语**。  
3. **可视化编辑器：** Svelte；定位 **1.x stretch**，不挡 1.0。  
4. **持续补功能 / 修 bug：** 作为横切 **Hygiene** 轨，不单开「只修 bug 季」。

v1 时间线仍有效，但需升版为**多轨**视图，避免工具链与引擎排期对不齐。

### 1.3 北极星（已确认）

| 优先级 | 目标 | 含义 |
|--------|------|------|
| **主** | **可发独立 VN** | 爱好者用 MoonYuki + MoonBit UI 写出完整故事，发布 **Web + 桌面**；播放体验达「认真玩」以上 |
| **辅** | **MoonYuki 深度** | 脚本表现力、诊断、源映射；**不为语言花活阻塞 1.0** |
| **工具链** | **现代宿主 + 正式文档** | Svelte 宿主（尽量全量 TS/Svelte）+ Fumadocs 双语作者站；编辑器 **1.x stretch** |

组织方式：**多轨总图** — 每季 **Engine 主交付** + **Host / Docs 次交付** + **Hygiene 横切**；冲突时 **砍并行轨深度，不砍 Engine 主交付**。

### 1.4 本规格范围

**本文件定义：** 轨道边界、版本门槛（含工具链）、Q1–Q6 多轨排期、仓库形态约束、验收与风险、文档工作方式。

**本文件不定义：** 某一能力的 API 形状、Svelte 组件树、Fumadocs 具体路由表、逐任务实现步骤（留给各季 design/plan）。

---

## 2. 轨道定义

| 轨 | 代号 | 职责 | 1.0 角色 |
|----|------|------|----------|
| **Engine** | E | `runtime` / `render` / `script` / `std_*` / `audio` / `moonsightc` / `demo` | **主轨**，决定门槛是否达成 |
| **Host** | H | Svelte + TS 浏览器/桌面壳；boot、input、prefs、manifest、错误页、Tauri 集成；WebGPU/Slug **adapter** | 0.8 可玩；1.0 全量收口（见 §3） |
| **Docs** | D | monorepo `apps/docs-site`（Fumadocs）；中英结构；从 `docs/*.md` 迁入 | 0.8 核心页双语；1.0 作者手册完整 |
| **Editor** | X | Svelte 可视化作者工具 | **1.x stretch only** |
| **Hygiene** | Y | bugfix、回归、文档与行为一致、无假完成 | 横切；P0 可阻塞门槛 |

### 2.1 Host 边界（硬约束）

| 做 | 不做 |
|----|------|
| Svelte 管页面骨架、boot 流程、输入→Intent、prefs/存档适配、加载/错误 UI、Tauri 桥 | 把**游戏内** HUD/菜单改成 DOM 或 Svelte 组件 |
| TS 服务层：`GameSession`、SaveStore 适配、manifest 加载 | 恢复 `- screen` / DOM 菜单主路径 |
| Adapter 模块：WebGPU device、draw-list 消费、Slug、wasm 实例 | 要求 third_party Slug 改写成 Svelte |
| 尽量全量：除 **wasm** 与 **Slug** 外，host 侧目标为 Svelte/TS | 一帧内用 Svelte 重绘 Stage 图层 |

**全量目标的收口定义（1.0）：** 默认游玩路径上，业务调用侧为 TypeScript/Svelte；adapter 实现允许保留必要 JS 文件，但须有清晰模块边界与类型面；不得残留「必须手动维护的第二套 vanilla boot 主路径」。

### 2.2 Docs 边界

- **形态：** monorepo 内 `apps/docs-site`（Fumadocs；底层多为 Next.js 系，实现细节 Q2 design 敲定）。  
- **受众：** **作者优先**；贡献者/架构页次之。  
- **语言：** **中英双语** 同构目录；允许单页暂缺译文但导航占位；**0.8** 要求 Getting Started + 核心作者路径双语。  
- **内容源：** 渐进迁入现有 `docs/moon-yuki-subset.md`、`ui-moonbit.md`、`host-commands.md`、`play-input.md`、`project-layout.md` 等；迁完后站点为权威，repo 根 `docs/` 可保留短链或归档说明。  
- **部署：** 静态导出优先（Cloudflare Pages / GitHub Pages 等在 Q2 design 选定）。

### 2.3 Editor 边界

- 技术栈倾向与 Host 一致（Svelte）。  
- **不进入 1.0 成功标准**；Q6 及以后。  
- 总图仅预留 monorepo 命名（如 `apps/editor`），不排实现任务。

### 2.4 Hygiene

- 每季从 Engine 验收中扣固定注意力：已知 P0/P1、回归、文档一致性。  
- **不**单独开「只修 bug 的漫长季」；缓冲集中在 **Q5**。

---

## 3. 版本门槛

| 门槛 | 含义 | Engine 必须 | Host / Docs | 明确可不做 |
|------|------|-------------|-------------|------------|
| **0.5 可认真内测** | 短 demo 循环试玩，系统不「残」 | backlog、skip、confirm、prefs→音量、Slider、基础回归 | vanilla host 即可 | — |
| **0.8 可发 demo 作** | 作者能做 30–90 分钟样章并 Web 分享 | 0.5 + dissolve 或等价 + scale 最小集 + 中等 demo + 诊断/文档够用 | **Svelte host 默认可玩通 demo**（adapter 可仍厚）；Fumadocs **作者路径中英骨架 + 核心页** | 编辑器、完整 dissolve 特效栈、Live2D、完整主题 |
| **1.0 可发独立 VN** | 爱好者可发布完整 Web + 桌面 | 0.8 + 桌面存档/发布路径 + 项目模板 + 演出/脚本够中小型 + 限制诚实 | **Host 全量目标收口**（§2.1）；Fumadocs **作者手册完整双语**；旧散落 md 归档或重定向 | 可视化编辑器、第二 GPU 后端、官方 Yukimi 字节码互通、DOM UI |
| **1.x stretch** | 可全部砍 | i18n 运行时深度、rollback 深度、粒子/后处理等 | **Svelte 编辑器 MVP**、Live2D 探针等 | 不承诺进 1.0 |

### 3.1 门禁规则

1. **Engine 主清单缺一项 → 该门槛不达标。**  
2. Host/Docs 进入门槛后：允许「可用未精修」；**禁止**「半截迁移导致默认 demo 不能玩」。  
3. 并行轨拖垮工期时：**先砍 Host/Docs 深度与 polish，再砍 Engine 次要花活；最后才动 Engine 门槛项**（需书面修订本总图）。  
4. 双 host 路径：Q2 起必须标明**默认路径**；**Q4 起发布脚手架只认 Svelte dist**；最迟 **Q5** 删除或归档旧 vanilla 主路径。

### 3.2 辅北极星挂钩

- **0.5–0.8：** 诊断、host 与演出/skip 语义硬化。  
- **0.8–1.0：** 脚本小步扩展；**不以语言实验阻塞发布。**  
- **工具链：** 服务作者与可维护性，不替代「可发 VN」成功标准。

---

## 4. 季度多轨排期（约 12–18 个月）

时间起点假设 **2026 Q3**（可整体平移）。Q1 已完成。

| 季度 | Engine 主交付 | Host 次交付 | Docs 次交付 | Hygiene | 门槛目标 |
|------|---------------|-------------|-------------|---------|----------|
| **Q1** | 可认真玩：backlog / skip / confirm / volume / Slider | vanilla 维持 | repo `docs/*.md` | 随实现 | **0.5 ✓** |
| **Q2** | **演出够讲故事：** `trans.dissolve`（或 crossfade 等价）；layer scale（+ 可选 rotate/anchor 最小集）；voice 轨 MVP **或** SE 分层加强；中长 demo 样章骨架；wait/fade/tween 与 skip 一致 | **Svelte+TS 立项：** Vite/Svelte（或 SvelteKit，Q2 design 定）应用骨架；boot 迁入；input/prefs 模块边界；WebGPU/Slug/wasm **adapter 隔离**；默认路径可玩 demo（可暂双轨） | **docs-site 脚手架：** Fumadocs IA、中英路由、首页 + Getting Started；迁入 2–3 核心文 | P0 播放阻断优先 | 向 **0.8** |
| **Q3** | **系统与 UI 完备：** ScrollView（服务 backlog）；通用 confirm 模式；主题/皮肤最小；槽位缩略图（可降级图标） | glue 层基本 TS 化；加载/错误态；Tauri 接新壳 | 作者手册主体中英（MoonYuki / UI / host commands / play-input）；旧 docs 链入或镜像 | 控件回归 | **0.8** 收口 |
| **Q4** | **能发布：** 桌面原生存档路径；发布脚手架（build → dist → Tauri/Web）；`moonsight new` 模板；中等可通关 demo；限制与迁移说明 | 发布路径**只认** Svelte dist；旧 `js_glue` 降级计划执行 | 发布/模板教程双语；部署流水线稳定 | 存档/发布路径测试 | → **1.0 候选** |
| **Q5** | **1.0 硬化：** 性能/存档兼容/回归套件；**i18n 最小** 与 **rollback MVP 二选一主投**；作者反馈修复缓冲 | Host **全量收口** + 兼容；无半截默认路径 | 手册完整双语；贡献指南；归档 repo 散落权威 md | 大缓冲 | **1.0 发布** |
| **Q6** | Stretch 引擎能力（粒子/后处理等，可砍） | — | — | — | **1.x：** Editor MVP **或** Live2D 探针等（可砍） |

### 4.1 依赖与原则

1. **Q2 Engine 不阻塞于 Host 全量** — 演出为主验收；Host 只要求骨架默认可玩。  
2. **Q2 起 Host 与 Docs 并行** — 与「引擎优先、工具链并行」一致。  
3. **Q2–Q3 可部分并行（Engine 内）** — dissolve/scale 优先于主题系统。  
4. **Q4 是发布路径季** — 无模板/桌面存档则 1.0 不成立；Host 与发布合流。  
5. **Q5 故意留缓冲** — 并行轨收口 + 二选一深度不双开主投。  
6. **Q6 全部可砍** — 编辑器不进 1.0 checklist。  
7. **每季独立 design/plan** — 本文件是总图；Q2 design 可包含 Engine + Host 骨架 + Docs 脚手架的契约，若过大可拆子 plan，但**同一季度主题下验收**。

### 4.2 能力 → 最早出现季

| 能力 | 最早季 |
|------|--------|
| backlog / skip / confirm / volume prefs | Q1 ✓ |
| dissolve / scale / demo 加长 | Q2 |
| Svelte host 骨架默认可玩 | Q2 |
| Fumadocs 脚手架 + 核心页 | Q2 |
| scroll / theme / screenshot | Q3 |
| 作者手册主体双语 | Q3 |
| 桌面存档 / 模板 / 发布脚手架 | Q4 |
| 发布只认 Svelte dist | Q4 |
| Host 全量收口 / 手册完整 | Q5 |
| i18n **或** rollback（Q5 二选一） | Q5 |
| 编辑器 / Live2D / 粒子 | Q6 |

### 4.3 架构影响（总图级）

| 区域 | 预期演进 |
|------|----------|
| `runtime` / `std_commands` / `render` | 同 v1：dissolve、scale、ScrollView、voice 等按季；Stage 权威不变 |
| `host_web` / `js_glue` | **迁入** `apps/host-web`；旧路径过渡期双轨 → 删除 |
| `host_desktop` | Tauri 加载新 host dist；原生存档 Q4 |
| `apps/docs-site` | Fumadocs 权威文档 |
| `apps/editor` | 仅命名预留至 Q6 |
| 存档 | 叙事状态权威；UI 栈不进档；格式 bump 可迁移 |
| monorepo 工具 | 根目录 package 工作区或独立 apps 的约定在 Q2 design 敲定（不强制 pnpm/npm 选型于本文件） |

#### 建议仓库形状（可微调）

```text
moonsight/
  runtime/ script/ render/ audio/ std_*/ cmd/ demo/   # MoonBit 引擎
  apps/
    host-web/          # Svelte + TS host
      src/
      adapters/        # webgpu, slug, wasm
    docs-site/         # Fumadocs
      content/zh/
      content/en/
  host_desktop/tauri/  # 指向 apps/host-web 构建产物
  docs/                # 过渡源 md → 迁入 docs-site
  third_party/slug/    # 保持
```

#### Host 逻辑分层

```text
Svelte UI 壳 (boot / error / optional chrome)
    → TS 服务层 (GameSession, Intent map, Prefs, SaveStore 适配)
        → Adapter (WebGPU, draw-list, soft/slug, wasm)
            → host_web.wasm (Stage / UiRuntime 权威)
```

---

## 5. 验收、风险与工作方式

### 5.1 每季最低验收（共性）

1. **Engine 主交付**有可运行 demo 或标准 demo 增量证明。  
2. `moon test` / `moon check` 全绿；关键路径有单测或构建 fixture。  
3. **Host：** 至少一条**默认**路径 smoke（build + 冷启动 title）；并行轨不得破坏该路径。  
4. **Docs：** 与当季行为一致；迁站后以 Fumadocs 为准。  
5. 该季 design 写明 **非目标**；无占位假实现。  
6. Hygiene：已知 P0 不得带入门槛宣布。

### 5.2 门槛验收（汇总）

- **0.5：** 新人按 README 在浏览器走完 demo；Esc 菜单完整；回看/跳过/确认/音量可用。（已达成）  
- **0.8：** 外部作者仅用文档站 + 模板草稿可搭出可分享 Web 样章；演出转场不止 fade；**默认 Svelte host 可玩**；核心作者页中英可读。  
- **1.0：** Web + 桌面均可分发完整短中篇；Host 全量收口；作者手册双语完整；限制列表诚实；无已知 P0 播放阻断。

### 5.3 主要风险

| 风险 | 缓解 |
|------|------|
| Host 全量迁拖垮 Q2 演出 | 主/次门禁；Q2 Host 只验收骨架可玩；全量到 Q5 |
| 双语文档成本爆炸 | 骨架同步；正文可暂缺译文+占位；0.8 仅核心页双语硬门禁 |
| 双 host 路径分叉 | Q2 标明默认；Q4 发布只认新 dist；Q5 删旧主路径 |
| Slug/WebGPU 难 TS 化 | adapter 允许 JS 实现 + TS 类型面；不阻塞 1.0 |
| 总图当实现规格 | 强制每季单独 design；本文件禁止直接 SDD 切片 |
| skip / wait / tween / dissolve 语义纠缠 | Q2 design 写清状态机，复用 Q1 门控 |
| 桌面存档与 Web 分叉 | Q4 统一 SaveStore 抽象 |
| 编辑器回灌 1.0 | Q6 only；checklist 显式排除 |
| Q2 单季 design 过大 | 允许 Engine / Host / Docs 子 plan，同一验收窗口 |

### 5.4 工作方式

- **节奏：** brainstorm → design → plan → SDD tasks → verify（与 Phase 1–4 / Q1 相同）。  
- **并行：** 同季内无共享契约的包可并行；**跨轨契约先写入该季 design**。  
- **文档位置：** 总图本文件；各季 `YYYY-MM-DD-moonsight-qN-<topic>-design.md`；plan 同前缀。  
- **README：** 仅在门槛达成时更新 Scope；避免提前承诺 stretch。  
- **v1 处理：** [roadmap v1](./2026-07-11-moonsight-roadmap-design.md) 状态改为 Superseded，顶部链到本文件。

---

## 6. 文档形态与后续流程

### 6.1 本文件角色

- **是：** 12–18 个月**多轨**产品路线图、版本门槛（含 Host/Docs）、季度挂载、仓库形态约束、风险与工作约定。  
- **不是：** Q2 实现规格、Svelte 组件 API、Fumadocs 全文大纲、任务 DAG。

### 6.2 建议的下一步

1. 用户审阅本 spec。  
2. 通过后对 **Q2「演出 + Host 骨架 + Docs 脚手架」** 启动独立 brainstorm / writing-plans。  
3. Q2 design 批准后再进入实现；Q3+ 在前一季门槛基本达成后再开详细 design。

### 6.3 成功标准（本路线图文档自身）

- 团队能用本文件回答：现在在哪、1.0 要什么、每季 Engine/Host/Docs 各交什么、冲突时砍谁、编辑器何时、下一步开哪份 design。  
- 任一季度 design 能引用本文件的季度行与门槛表，而不复制整份总图。

---

## 7. 决策记录（brainstorming）

| 决策 | 选择 |
|------|------|
| 计划类型 | 多轨产品路线图总览 v2（升版 v1） |
| 北极星 | 主：可发独立 VN；辅：MoonYuki；工具链：Svelte host + Fumadocs |
| Svelte 范围 | 宿主壳 + 远期编辑器；**不是**游戏内 UI |
| Host 深度 | 尽量全量 TS/Svelte（除 wasm 与 Slug） |
| Host 时间 | Q2 与演出**并行**；全量收口 Q5 |
| Docs | monorepo Fumadocs；作者优先；**中英双语** |
| 编辑器 | 仍 1.x stretch（Q6+） |
| 组织方式 | **A. 多轨总图**（每季主/次交付） |
| 优先级冲突 | 砍并行轨深度，保 Engine 主交付 |
| 首个实现入口 | Q2（非本文件直接 SDD） |
| 基线 | Q1/0.5 已交付 |
