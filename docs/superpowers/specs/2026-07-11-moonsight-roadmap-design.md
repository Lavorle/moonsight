# MoonSight — 12–18 个月产品路线图总览

**日期：** 2026-07-11  
**状态：** Approved design (roadmap overview; not a single-quarter implementation spec)  
**仓库：** `moonsight`  
**前序（已交付）：**  
- [Phase 1 运行时内核](./2026-07-10-moonsight-runtime-design.md)  
- [Phase 2 图层与演出语义硬化](./2026-07-10-moonsight-phase2-layers-design.md)  
- [Phase 3 Screen 语言与系统 UI](./2026-07-10-moonsight-phase3-screen-ui-design.md)  
- [Phase 4 MoonBit UI 内核](./2026-07-10-moonsight-phase4-ui-kernel-design.md)  

**下一实现入口：** 每季度单独 brainstorm → 写该季 design + implementation plan（首季建议 **Q1 可认真玩**）。本文件**不**直接进入单季 SDD 实现切片。

---

## 1. 背景与北极星

### 1.1 现状（Phase 1–4 基线）

MoonSight 是 **MoonBit + WebGPU** 通用视觉小说引擎（非单作）。已交付：

| 层 | 能力 |
|----|------|
| 脚本 | MoonYuki 子集 → IR / `MSB1`；多文件 scene merge；macro / extern / 条件跳转 / 选项 |
| 运行时 | VM、Director、Stage、图层 tween、`trans.fade`、timed `flow.wait`、存档 v3、prefs、多槽 |
| UI | retained `UiApp` / `UiRuntime`（HUD + modal）；`std_ui` 默认四模态 + 对话 HUD；可选 `ui_package` 同 wasm 链接 |
| 渲染 / 音频 | 打包 draw list + WebGPU host；逻辑 BGM/SE mixer |
| 工具 / 宿主 | `moonsightc check/build`；浏览器 host；Tauri 桌面壳；短 demo |

架构原则保持不变：**Stage 叙事权威**；脚本只经 host 改世界；UI 经闭合 **Capabilities**；render 只读绘制数据；项目 `- screen` 已切断。

### 1.2 问题

相对「爱好者可发布完整独立 VN」仍有结构性缺口：播放器标配（回看、跳过、确认、音量 prefs 落地）、演出深度、UI 控件完备度、发布与作者脚手架、以及 MoonYuki 表达力与诊断。Phase 1–4 的 out-of-scope 列表已过长，需要**总览级**分期，而不是再做一个无边界的 Phase 5 大杂烩。

### 1.3 北极星（已确认）

| 优先级 | 目标 | 含义 |
|--------|------|------|
| **主** | **可发独立 VN** | 爱好者/独立作者能用 MoonYuki + MoonBit UI 写出完整故事，发布 **Web + 桌面**；系统菜单与播放体验达到「认真玩」水准 |
| **辅** | **MoonYuki 深度（Yukimi 理念）** | 加强脚本表现力、host 命令语义、编译/运行诊断与源映射；**不为语言花活阻塞 1.0** |

组织方式：**玩家/作者价值链**（每季回答「作者多获得什么」），按**季度**粗排约 **12–18 个月**；尽量少硬排除，远期能力进 stretch 槽且可砍。

### 1.4 本规格范围

**本文件定义：** 缺口分桶、版本门槛（0.5 / 0.8 / 1.0）、Q1–Q6 主题与依赖、验收与风险、文档工作方式。

**本文件不定义：** 某一能力的 API 形状、数据结构、逐任务实现步骤（留给各季 design/plan）。

---

## 2. 缺口清单（相对 Phase 1–4）

| 桶 | 已有（不重做） | 明显缺失 / 薄弱 |
|----|----------------|-----------------|
| **叙事播放** | 打字机、选项、变量、跳转、自动、快存快读 | **回看 backlog**、跳过 (skip)、确认框（覆盖存档 / 退出）、rollback（可选深度） |
| **系统 UI** | title / game_menu / save_load / settings（MoonBit） | **Slider / 滚动**、槽位缩略图、通用 confirm modal 模式、主题 / 皮肤 |
| **演出** | layer 四 kind、线性 x/y/opacity tween、`trans.fade`、timed wait | **dissolve**、scale / rotate / anchor、blocking 演出 DSL、时间轴 / 动画队列、粒子 / 后处理 |
| **脚本 MoonYuki** | 多文件 merge、macro、extern、host 命令表 | 更强诊断 / 源映射、跨文件 macro / 模块、内联标记扩展、与演出 / skip 语义协同 |
| **音频** | BGM/SE、volume/fade 命令、mixer 逻辑 | **prefs 音量真正接到 mixer**、声道策略、voice 轨 |
| **资源与构建** | 字面量资源检查、MSB、manifest、ui_package 同链 | 动态 id 策略文档、atlas / 打包优化、版本化资源、错误 UX |
| **宿主** | WebGPU 浏览器、Tauri 壳、localStorage 槽 | 桌面原生存档路径、窗口 / 全屏偏好、安装器 / 发布脚手架 |
| **内容与作者体验** | 短 demo、文档子集 | **中长 demo 作**、项目模板、i18n、成就、可视化编辑器、Live2D（远期） |

清单描述「缺什么」；排序见 §4。

---

## 3. 版本门槛与排除策略

### 3.1 对外版本门槛

| 门槛 | 含义（主北极星） | 必须具备（摘要） | 明确可不做 |
|------|------------------|------------------|------------|
| **0.5 可认真内测** | 短 demo 可循环试玩，系统不「残」 | backlog、skip、confirm、prefs→音量、settings 用 Slider（或等价控件）、基础回归 | 编辑器、完整 dissolve 栈、i18n |
| **0.8 可发 demo 作** | 作者能做 30–90 分钟样章并 Web 分享 | 0.5 + 更稳存读/发布脚手架起步 + dissolve 或等价转场 + 中等 demo + 诊断/文档够用 | Live2D、完整时间轴、成就 |
| **1.0 可发独立 VN** | 爱好者可发布完整 Web + 桌面作品 | 0.8 + 桌面存档/发布路径 + 项目模板 + 演出/脚本够覆盖中小型作 + 已知限制文档 | 可视化编辑器、Live2D/3D、第二 GPU 后端、官方 Yukimi 字节码互通 |
| **1.x stretch** | 体验跃迁，**全部可砍** | 编辑器 MVP、Live2D 探针、i18n 运行时、粒子/后处理、成就、rollback 深度 | 不承诺进 1.0 |

### 3.2 排除策略（少硬排除）

- **1.0 不做，路线图保留槽位：** 可视化编辑器、Live2D/3D、第二原生 GPU 后端、官方 Yukimi 字节码互通、DOM UI。  
- **1.0 倾向不做，1.x 视需求：** 完整粒子/后处理栈、开放 host-string UI action、动态第二 wasm UI 加载。  
- **不作为成功标准：** 与 Ren'Py 脚本 100% 兼容；商业商店一键上架全流程。

### 3.3 辅北极星挂钩

- **0.5–0.8：** 诊断、源映射、host 与演出语义硬化（服务作者）。  
- **0.8–1.0：** 脚本表现力扩展（宏/模块、转场、与 wait/skip 一致）；**不以语言实验阻塞发布门槛**。

---

## 4. 季度路线图（约 12–18 个月）

时间起点假设 **2026 Q3**（可整体平移）。每季主题 = 价值链增量；内部仍用 SDD（spec → plan → tasks）。

| 季度 | 主题 | 主交付（摘要） | 辅：MoonYuki | 门槛目标 |
|------|------|----------------|--------------|----------|
| **Q1** | **可认真玩** | backlog；skip（可配置）；覆盖存档/退出 confirm；prefs 音量驱动 mixer；settings Slider 或等价；slot 元数据完善 | 诊断更可读；host 与 skip/wait 语义写清 | → **0.5** |
| **Q2** | **演出够讲故事** | `trans.dissolve`（或 crossfade 等价）；layer scale（+ 可选 rotate/anchor 最小集）；voice 轨 MVP **或** SE 分层加强；中长 demo 样章骨架 | 演出 host 扩展；wait/fade/tween 与 skip 一致；动态资源策略文档 | 向 **0.8** |
| **Q3** | **系统与 UI 完备** | ScrollView（服务 backlog）；通用 confirm modal 模式；主题/皮肤最小；槽位缩略图（可降级为图标） | Capabilities 保持闭合扩展；`ui-moonbit` → 作者手册级 | **0.8** 收口 |
| **Q4** | **能发布** | 桌面原生存档路径；发布脚手架（build → dist → Tauri/Web 清单）；`moonsight new` 模板；中等可通关 demo；限制与迁移说明 | CLI `check` 加强（坏跳转、死资源启发式等） | → **1.0 候选** |
| **Q5** | **1.0 硬化 + 可选深度** | 性能/存档兼容/回归套件；**i18n 最小实现** 与 **rollback MVP 二选一主投**；作者反馈修复缓冲 | 宏/多文件小步；源映射/调试信息 | **1.0 发布** |
| **Q6** | **Stretch / 可砍** | 编辑器 MVP **或** Live2D 探针 **或** 粒子/后处理之一；成就/CG 回想若有带宽 | 实验性语法/时间轴 DSL 探针 | **1.x** 探索 |

### 4.1 依赖与原则

1. **Q1 不阻塞于演出花活** — 先补玩家标配（主北极星）。  
2. **Q2–Q3 可部分并行** — dissolve/scale 优先于主题系统。  
3. **Q4 是发布路径季** — 无模板/桌面存档则 1.0 不成立。  
4. **Q5 故意留缓冲** — 避免 Q1–Q4 塞爆；二选一深度不双开主投。  
5. **Q6 全部可砍** — 不进 1.0 成功标准。  
6. **每季独立 design/plan** — 本文件是总图，不是实现规格。

### 4.2 能力 → 最早出现季

| 能力 | 最早季 |
|------|--------|
| backlog / skip / confirm / volume prefs | Q1 |
| dissolve / scale / demo 加长 | Q2 |
| scroll / theme / screenshot | Q3 |
| 桌面存档 / 模板 / 发布脚手架 | Q4 |
| i18n **或** rollback（Q5 二选一主投） | Q5 |
| 编辑器 / Live2D / 粒子 | Q6 |

### 4.3 架构影响（总图级，细节各季再定）

| 区域 | 预期演进方向（约束） |
|------|----------------------|
| `runtime` | backlog 环形缓冲 / 事件日志（**不默认进存档全文**，策略在 Q1 design 敲定）；skip 与 wait/tween 门控；confirm 作为 modal 能力 |
| `std_ui` / UI 内核 | Slider、ScrollView、confirm 模式；主题为资源/颜色绑定，非第二 DSL |
| `std_commands` / Stage | dissolve、scale 等演出属性；voice 若做则独立轨 |
| `audio` | prefs → mixer 真实接线（Q1 必做项） |
| `script` / `moonsightc` | 诊断与 check 规则渐进；不恢复 `- screen` 主路径 |
| `host_web` / `host_desktop` | 截图缩略图、桌面 FS 存档、发布清单 |
| 存档 | 保持叙事状态权威；UI 栈/焦点仍不进档；格式 bump 须可迁移 |

---

## 5. 验收、风险与工作方式

### 5.1 每季最低验收（共性）

1. 该季主题能力有 **可运行 demo 或标准 demo 增量** 证明。  
2. `moon test` / `moon check` 全绿；关键路径有单测或构建 fixture。  
3. 用户文档（subset / host-commands / ui-moonbit / README 相关节）与行为一致。  
4. 明确 **非目标** 写入该季 design，防止 scope 回灌。  
5. 无占位假实现（禁止 `TODO` 冒充完成、空 stub 当功能）。

### 5.2 门槛验收（汇总）

- **0.5：** 新人按 README 在浏览器走完 demo；Esc 菜单完整；回看/跳过/确认/音量可用。  
- **0.8：** 外部作者仅用文档 + 模板可搭出可分享 Web 样章；演出转场不止 fade。  
- **1.0：** Web + 桌面均可分发完整短中篇；限制列表诚实；无已知 P0 播放阻断。

### 5.3 主要风险

| 风险 | 缓解 |
|------|------|
| 总图当实现规格，单季 scope 爆炸 | 强制每季单独 design；本文件禁止直接 SDD 切片 |
| UI 控件与演出并行拖垮质量 | Q1 先播放器标配；Q2 演出；Q3 UI 完备 |
| skip / wait / tween 语义纠缠 | Q1 写清状态机；Q2 转场复用同一门控 |
| 桌面存档与 Web localStorage 分叉 | Q4 统一 SaveStore 抽象，host 实现差异 |
| Q5 二选一决策拖延 1.0 | Q4 末根据作者反馈锁定 i18n vs rollback |
| Stretch 回灌 1.0 | Q6 默认可砍；1.0 checklist 不含编辑器/Live2D |

### 5.4 工作方式

- **节奏：** 与既有 Phase 1–4 相同 — brainstorm → design → plan → SDD tasks → verify。  
- **并行：** 同季内无共享状态的包可并行；跨包契约先写进该季 design。  
- **文档位置：** 总图本文件；各季 design 命名建议 `YYYY-MM-DD-moonsight-qN-<topic>-design.md`；plan 同前缀。  
- **README：** 仅在门槛达成时更新「Scope / Out of scope」，避免提前承诺 stretch。

---

## 6. 文档形态与后续流程

### 6.1 本文件角色

- **是：** 12–18 个月产品路线图总览、版本门槛、季度挂载、风险与工作约定。  
- **不是：** Q1 实现规格、API 清单、任务 DAG。

### 6.2 建议的下一步

1. 用户审阅本 spec（本文件）。  
2. 通过后对 **Q1「可认真玩」** 启动独立 brainstorm / writing-plans（backlog、skip、confirm、volume prefs、Slider）。  
3. Q1 design 批准后再进入实现；Q2+ 在前一季门槛基本达成后再开详细 design。

### 6.3 成功标准（本路线图文档自身）

- 团队能用本文件回答：现在缺什么、1.0 要什么、下季做什么、什么可砍。  
- 任一季度 design 能引用本文件的季度行与门槛表，而不复制整份总图。

---

## 7. 决策记录（brainstorming）

| 决策 | 选择 |
|------|------|
| 计划类型 | 产品路线图总览（非单垂直深挖） |
| 北极星 | 主：可发独立 VN；辅：MoonYuki 深度 |
| 时间粒度 | 按季度粗排 12–18 个月 |
| 硬排除 | 尽量少；编辑器/Live2D 等进 stretch 可砍 |
| 组织方式 | A. 玩家/作者价值链 |
| 版本门槛 | 0.5 / 0.8 / 1.0 + 1.x stretch |
| 首季实现入口 | Q1 可认真玩（本文件之后另开 design） |
