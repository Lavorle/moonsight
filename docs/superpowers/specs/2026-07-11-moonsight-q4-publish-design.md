# MoonSight Q4 — 能发布（1.0 候选）

**日期：** 2026-07-11  
**状态：** Approved design (implementation planning next)  
**仓库：** `moonsight`  
**总图：** [roadmap v2](./2026-07-11-moonsight-roadmap-v2-design.md)（Q4 行）  
**前序（已交付）：** Phase 1–4、Q1/0.5、Q2 multi-track、Pointer Theme、Q3/0.8 系统 UI（自动门禁绿）  

**实现组织：** **方案 C — 多轨并行 + 联合门禁**（Engine / Host / Docs 同季契约；Hygiene 横切）。

---

## 1. 背景与目标

### 1.1 问题

相对路线图 **1.0 候选** 与北极星「可发独立 VN」，0.8 之后仍缺发布闭环：

1. **无项目脚手架** — 作者只能抄 `demo/game`；无 `moonsightc new`。  
2. **双 host 静默分叉** — `build` 可 fallback 到 `host_web/js_glue`，维护与文档易漂移。  
3. **桌面存档非原生** — Tauri 壳加载同一 Web 包，槽位仍绑 webview `localStorage`；无统一 SaveStore、无 appData 文件槽。  
4. **发布路径未产品化** — 缺固化的 Web 静态托管 + Tauri 打包清单/脚本与作者文档。  
5. **Demo 偏短** — 不足以支撑「短中篇可通关」叙事验收。

### 1.2 一句话

把 MoonSight 从「仓库里能玩 demo」收口成 **外部作者可发短中篇**：脚手架生成项目 → 只认 Svelte 壳构建 Web dist → 桌面经统一 **SaveStore** 写 appData 槽位 → 同一套产物可 Web 静态托管与 Tauri 打包分发。

### 1.3 成功故事（已确认）

> **Web + 桌面都能正经分发短中篇。**

联合门禁通过后宣布 **1.0 候选**；正式 **1.0 发布** 仍属 Q5（硬化、Host 全量收口、缓冲）。

### 1.4 已确认决策

| 决策 | 选择 |
|------|------|
| 组织方式 | 多轨并行 + 联合门禁（方案 C） |
| 桌面存档 | Tauri **appData** + 统一 **SaveStore**；Web 继续 **localStorage** |
| 模板 | **`moonsightc new`** + **最小可 build** 模板 |
| `js_glue` | **删除主路径**（比路线图「Q4 降级 / Q5 删除」更激进） |
| Demo | **`demo/game` 扩成 30–60 分钟样章骨架** |

### 1.5 相对路线图 v2 的有意偏差

| 项 | 路线图 v2 | 本 design |
|----|-----------|-----------|
| `js_glue` | Q4 降级，最迟 Q5 删 | **Q4 删除主路径**（可 `archive/` 只读参考，不参与 build） |
| 门槛措辞 | Q4 → 1.0 候选 | 联合验收通过即 **1.0 候选**；正式 1.0 在 Q5 |

---

## 2. 架构总览

### 2.1 原则

| # | 原则 |
|---|------|
| 1 | **Stage 叙事权威**；UI 经 Capabilities；游戏内 UI 不进 DOM |
| 2 | **存档语义权威仍在 wasm**（save **v4** JSON）；Host 只负责 **持久化后端** |
| 3 | **一条默认发布路径**；禁止双 boot 静默分叉 |
| 4 | **SaveStore 是 Host 边界**：Web / 桌面换存储实现，引擎 API 不变 |
| 5 | **模板最小可 build**；能力与叙事展示放 `demo/game`，不把小说写进模板 |
| 6 | 冲突砍序：联合门禁项 > Host/Docs polish > 样章文笔厚度 |

### 2.2 逻辑分层

```text
作者 / CI
  moonsightc new|check|build
       │
       ▼
  project/  (moonsight.json, *.yuki, assets/, 可选 ui/)
       │  moonsightc build -o dist/<name>
       ▼
  dist 包  ←  必须含 Svelte shell + host_web.wasm + game.msb + assets
       │
       ├─ Web：静态托管
       │     SaveStore → localStorage
       │
       └─ Desktop：Tauri 加载同一 dist
             SaveStore → appData 文件（Tauri invoke）
                    │
                    ▼
             host_web.wasm  (Engine / Stage / UiRuntime 不变)
```

### 2.3 包与职责

| 区域 | Q4 职责 |
|------|---------|
| `cmd/moonsightc` | 增 `new`；`build` **硬依赖** Svelte shell；可选 check 启发式 |
| `templates/minimal/` | 最小可 build 项目；`new` 的复制源（路径名实现时可微调，语义不变） |
| `apps/host-web` | **唯一**浏览器壳；抽出 `SaveStore`；Web 实现 = localStorage |
| `host_desktop/tauri` | 桌面 SaveStore 后端（appData 多槽）；加载同一 dist |
| `host_web/js_glue` | **删除主路径**；推荐迁 `archive/js_glue/` + 退役说明，或不参与任何默认 build |
| `demo/game` | 30–60 分钟样章骨架 |
| `docs/*` + `apps/docs-site` | 发布 / 模板 / 桌面存档中英作者路径 |
| `runtime` 存档格式 | **默认不 bump**（仍 v4）；桌面元数据不进档 |

### 2.4 硬边界（本季不碰）

- 不恢复 `- screen` / DOM 游戏菜单  
- 不把 SaveStore 逻辑下沉进 MoonBit  
- 不做编辑器、Live2D、voice、rollback、槽位真截图、粒子/后处理  
- 不做第二 GPU 后端  
- Host「adapter 零 JS / 全量收口」属 **Q5**；本季要求 **默认路径唯一 + SaveStore 清晰**

---

## 3. 组件设计

### 3.1 `moonsightc new` + 最小模板

**CLI：**

```text
moonsightc new <name> [-o <parent_dir>]
```

- 在 `<parent_dir>/<name>/`（默认 cwd）生成项目。  
- 目标已存在 → **失败**，不覆盖。  
- 成功后打印下一步：`check` / `build` 与文档链接。

**模板源 `templates/minimal/`：**

| 文件 | 作用 |
|------|------|
| `moonsight.json` | `entry`、资源表、`save_slots` 等最小合法配置 |
| `main.yuki` | title 冷启动后可玩的极短环（数句 + 一处 choice + yield） |
| `assets/` | 保证 **build 必绿** 的最小资源（占位图；音频可选但若引用则必须存在） |
| `README.md` | 5–10 行：check / build / play |
| **无** `ui/` | 默认 `std_ui`；注释说明可选 `ui_package` |

**不做：** 多模板变体、交互向导、整仓克隆 demo。

### 3.2 `moonsightc build`：只认 Svelte 壳

**解析顺序（新）：**

1. 若存在可用的 **`apps/host-web/dist/index.html`**（相对 monorepo 根，或实现约定的可配置 shell 路径）→ 复制该 shell 进 `-o`。  
2. **否则失败**，错误信息明确：先 `cd apps/host-web && npm run build`，并指向发布文档。  
3. **不再** fallback 到 `host_web/js_glue`。

**仍由 build 负责：** `game.msb`、`manifest.json`、资源拷贝、可选 `ui_package` 链 wasm、注入/覆盖 `host_web.wasm`（与现行为一致）。

**`build` 不自动跑 `npm run build`**（moonsightc 不依赖 Node）。缺 shell 时失败并提示；发布脚本可串联 npm + moon + moonsightc。

**`js_glue` 处置：**

- 从默认构建与 README Quickstart **主路径**删除。  
- 源码迁 `archive/js_glue/`（推荐）或删除；归档 **不被** moonsightc 引用。  
- CI / `moonsight-demo.sh` / 文档只描述 Svelte 路径。

### 3.3 SaveStore（Host 统一持久化）

**TS 接口（形状级；命名实现时可微调）：**

```ts
interface SaveStore {
  loadPrefs(): string | null;
  savePrefs(json: string): void;
  loadSlot(slot: number): string | null;
  saveSlot(slot: number, json: string): void;
  // 可选最小集：clearSlot — 若菜单需要则本季一并做
}
```

| 实现 | 后端 | 键/路径约定 |
|------|------|-------------|
| **WebSaveStore** | `localStorage` | 保持 `moonsight/prefs`、`moonsight/save/{n}` |
| **DesktopSaveStore** | Tauri appData | `{appData}/moonsight/prefs.json`、`{appData}/moonsight/saves/{n}.json` |

**接线：** 现有 `GameSession` 中 seed/sync prefs 与 slots **只依赖 SaveStore**，不再直接散落 `localStorage`（Web 实现内部才访问 LS）。

**桌面：**

- Tauri 最小 command：读/写 slot 与 prefs（或等价 FS API）；路径固定在 appData 子树。  
- 写文件优先 **tmp + rename** 原子写。  
- 启动：DesktopSaveStore → 灌入 wasm `set_slot_json` / prefs（与 Web 对称）。  
- **`saved_at` 盖戳** 仍在 Host（与 Q3 一致），与存储后端无关。  
- 存档 JSON 仍为引擎 **v4**；不因桌面改格式。

**不做：** 云同步、加密、Web↔桌面自动迁移（文档写明槽位不互通）。

### 3.4 发布脚手架（Web + 桌面）

**Web：**

1. `apps/host-web` → `npm run build`  
2. `moon build --target wasm-gc --release host_web`（项目需 ui 链时）  
3. `moonsightc build <project> -o dist/<name>`  
4. 整目录静态托管  
5. 验收：冷启动 title → 可玩 → 存读槽  

**桌面：**

1. 同上产出 dist  
2. Tauri `frontendDist` 指向该 dist  
3. `tauri build` → 平台包  
4. 验收：运行 → 存档在 appData → 杀进程再开仍在  

**仓库：** `host_desktop` README 与可选 `scripts/publish-*.sh` 固化顺序。  
**不做：** 商店一键上架、自动签名流水线。

### 3.5 Demo：30–60 分钟样章骨架

在 **`demo/game`** 扩展：

| 要求 | 说明 |
|------|------|
| 完整弧 | title → 多场景 → **明确结局**（可多结局，至少 1 个主结局） |
| 分支 | 至少 2 条可感知路径（汇合或分结局） |
| 引擎能力 | dissolve、scale、wait/skip 门控、菜单存读、backlog、settings 在流程中可触及 |
| 体量 | 约 **30–60 分钟**通关量（文笔不追求文学质量） |
| 资源 | 可复用/占位；不强制新原画管线 |
| 存档引导 | 至少一次 save hint 或引导 Esc 存档，便于验收 SaveStore |

**与模板：** `templates/minimal` 极短；`demo/game` 为能力与叙事展示。

### 3.6 Docs

**Fumadocs（中英同构；译文可占位规则沿用 roadmap v2）：**

- Getting Started（含 `new`）  
- Build & Publish（Web）  
- Desktop build & saves  

同步 play-input / moon-yuki / ui 与本季行为不一致处。

**Repo：** `project-layout.md`、README Scope 更新至 Q4 / 1.0 候选；标明 `js_glue` 已退役。

### 3.7 可选 Engine 小加强（非联合门禁杀手）

- `moonsightc check`：坏跳转目标 / 未声明字面量资源等启发式（有则更好；不得阻塞 `new` / SaveStore 主交付）。  
- `moonsightc version` 展示串可 bump（如 `0.9.0-candidate`）；本季不强制完整 semver 政策。

---

## 4. 数据流与状态

### 4.1 作者产物流

```text
moonsightc new mygame
  → 复制 templates/minimal → mygame/
作者改脚本 / 资源 / moonsight.json
moonsightc check mygame   （可选；CI 建议必跑）
[前置] apps/host-web/dist 存在
[前置] host_web.wasm release（需要时）
moonsightc build mygame -o dist/mygame
  → MSB + manifest + assets + Svelte shell + wasm
dist/mygame/  → Web 托管 或 Tauri frontendDist
```

- 模板默认 **无** `ui_package` → 用壳内默认 wasm。  
- 有 `ui_package` → 保持现有 moonsightc 链接/注入语义，本季不重设计。

### 4.2 运行时存档数据流

```text
用户存档/快存 → Engine (wasm) save_json / set_slot_json
             → GameSession（盖 saved_at）
             → SaveStore
                  ├─ WebSaveStore → localStorage
                  └─ DesktopSaveStore → appData 文件
```

**启动顺序（两宿主相同）：**

1. 创建平台 `SaveStore`  
2. `loadPrefs` → 引擎 prefs  
3. 各 slot `loadSlot` → `set_slot_json`（空则跳过）  
4. 既有 title / boot  
5. 之后菜单存、快存、改设置：经 SaveStore 写回  

**读档：** 引擎 `load` 解析 slot JSON；Host 只保证 seed 时 blob 已在。

### 4.3 桌面 Tauri 桥

```text
saveSlot(n, json) → invoke write → appData/moonsight/saves/{n}.json（原子写）
loadSlot(n)       → invoke read  → 不存在则 null
```

- 权限：仅 appData 子树。  
- 多实例：本季不保证；后写覆盖（与 LS 同级诚实限制）。  
- Web 与桌面槽位 **不互通**（文档写明）。

### 4.4 会话态 vs 持久态

| 数据 | 持久？ | 持有方 |
|------|--------|--------|
| Stage / VM / 变量 / 图层 / dissolve 等 | 是（save v4） | wasm |
| UI modal 栈 / ScrollView / focus | 否 | UiRuntime |
| Backlog ring | 否（会话） | 引擎会话 |
| Prefs | 是（SaveStore） | Host + 引擎镜像 |
| 槽位 blob | 是（SaveStore） | Host |

本季 **不** 把 backlog / UI 栈写入桌面文件。

### 4.5 删除 `js_glue` 后路径

| 场景 | 行为 |
|------|------|
| 有 `apps/host-web/dist` | build 成功 |
| 无 Svelte dist | build **硬失败**；无第二壳 |
| 归档 js_glue | 不被 moonsightc 引用 |

---

## 5. 错误处理

### 5.1 CLI

| 情况 | 行为 |
|------|------|
| `new` 目标已存在 | 非 0；不覆盖 |
| `new` 不可写 / 模板缺失 | 非 0；明确 IO 或「模板源找不到」 |
| `build` 无 Svelte `index.html` | 非 0；单路径建议 npm build host-web；**禁止**再提 js_glue |
| 编译/资源失败 | 现有失败语义；临时 out 不晋升 |
| check 启发式 | 不得误杀合法最小模板 |

退出码：成功 0；用户/构建错误非 0（细分码本季不强制）。

### 5.2 SaveStore

| 情况 | 行为 |
|------|------|
| 读槽不存在 | `null`，seed 跳过 |
| 写失败 | 可见错误；**不**静默成功；不崩溃引擎；内存槽可仍在 |
| 槽 JSON 损坏 | 跳过坏槽；不拖垮 boot；不删其他好槽 |
| prefs 损坏 | 回退默认 prefs |
| `saved_at` 盖戳失败 | 仍写出 blob |

**原则：** 持久化失败 ≠ 引擎崩溃；启动必须能进 title。

### 5.3 桌面 / Tauri

| 情况 | 行为 |
|------|------|
| appData 创建失败 | 可读启动失败；无任意路径 fallback |
| invoke 不可用 | 明确「桌面存档桥不可用」；禁止误报写入成功 |
| 错误 dist | 文档强调先 `moonsightc build` |

### 5.4 Host 壳

- 沿用 Q3 加载/错误全屏面板与 WebGPU 说明。  
- 不新增第二套错误 UI 框架。

---

## 6. 验收、测试与非目标

### 6.1 联合门禁（1.0 候选）

全部满足方可宣布：

1. **`moonsightc new`** → `check` + `build` 成功（已有 Svelte dist）。  
2. **`build` 无 Svelte dist 时失败**，无 js_glue fallback；默认文档/CI 不依赖 js_glue。  
3. **Web：** 托管 dist；title→可玩；存读经 **localStorage**；刷新后可读。  
4. **桌面：** Tauri 加载同一 dist 形态；存档在 **appData**；杀进程再开仍在。  
5. **SaveStore：** `GameSession` 无直接散落 `localStorage`（测试或 grep 门禁）。  
6. **Demo：** 约 30–60 分钟可通关弧；分支可感知；dissolve/scale/系统菜单路径可用。  
7. **文档：** Fumadocs（或等价中英路径）含 new / Web 发布 / 桌面构建与存档；README Scope 更新。  
8. **自动化：** `moon check` / `moon test` 全绿；host-web / docs-site build 绿；`new`→`build` smoke 可复现。

### 6.2 测试策略

| 层 | 内容 |
|----|------|
| MoonBit | 现有回归；`new` 可用临时目录 fixture（native） |
| Host | SaveStore 内存假实现测 seed/sync；Web 可用 mock LS |
| 桌面 | 手工清单；CI 无 GUI 时不伪造通过 |
| 构建 smoke | `new` → `build` → dist 含 `index.html` + `game.msb` + wasm |
| 内容 | demo `check`/`build`；可选关键 jump 目标检查 |

**人工清单：** Web + 桌面存多槽、覆盖 confirm、杀进程、prefs 保持；环境不足时诚实 defer。

### 6.3 明确非目标

- 可视化编辑器、Live2D/3D、voice、rollback、粒子/后处理  
- 槽位真截图、运行时多主题商店  
- 横向/嵌套 ScrollView、backlog 进存档  
- Web↔桌面存档迁移、云存档  
- Host 全量收口 / 删除全部 adapter JS（**Q5**）  
- 商店签名、自动更新、安装器品牌化  
- 官方 Yukimi 字节码互通、第二 GPU 后端  
- 商业级剧本质量  
- 交互式 WebGPU CI  

### 6.4 风险与缓解

| 风险 | 缓解 |
|------|------|
| 删 js_glue 导致无 Node 作者卡死 | 文档写死前置；发布脚本串联；错误信息单路径 |
| 样章体量拖垮工程 | 与工程并行；文笔可糙；复用资源；门禁要可通关弧非佳作 |
| 桌面 FS 分平台坑 | 只写 appData；原子写；Linux 先验收 |
| SaveStore 半截迁移 | GameSession 唯一出口；grep 门禁 |
| 与 Q5 边界糊 | 本文件区分 **1.0 候选** vs Q5 硬化 |

---

## 7. 多轨交付映射

| 轨 | Q4 主交付 |
|----|-----------|
| **Engine** | `moonsightc new` + `templates/minimal`；demo 样章；可选 check 启发式 |
| **Host** | SaveStore（Web LS / 桌面 appData）；Tauri 桥；**删除 js_glue 主路径**；build 只认 Svelte dist |
| **Docs** | new / Web 发布 / 桌面存档中英作者路径；README Scope |
| **Hygiene** | 存档往返与 build 失败信息；默认路径 smoke；无假完成 |

冲突时：先砍 polish 与文笔，**不**砍联合门禁项（new、SaveStore 双端、Svelte-only build、可通关样章弧、作者文档最小集）。

---

## 8. 后续流程

1. 用户审阅本 spec。  
2. 通过后 invoke **writing-plans** → `docs/superpowers/plans/2026-07-11-moonsight-q4-publish.md`。  
3. Plan 批准后 SDD 任务实现；收口时更新 README Scope 与（可选）roadmap v2 状态注。

---

## 9. 决策记录（brainstorming）

| 决策 | 选择 |
|------|------|
| 本季主题 | Q4 能发布 / 1.0 候选 |
| 成功故事 | Web + 桌面正经分发短中篇 |
| 组织 | 方案 C：多轨 + 联合门禁 |
| 桌面存档 | appData + SaveStore；Web = LS |
| 模板 | CLI `new` + 最小可 build |
| js_glue | Q4 删除主路径 |
| Demo | 30–60 分钟样章骨架于 `demo/game` |
| 存档格式 | 保持 v4；不进 UI/backlog |
| build 与 Node | 不自动 npm；缺 shell 硬失败 |
| 正式 1.0 | 仍 Q5 |
