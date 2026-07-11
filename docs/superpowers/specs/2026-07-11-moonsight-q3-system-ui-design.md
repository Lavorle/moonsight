# MoonSight Q3 — 系统与 UI 完备（0.8 收口）

**日期：** 2026-07-11  
**状态：** Approved design (implementation planning next)  
**仓库：** `moonsight`  
**总图：** [roadmap v2](./2026-07-11-moonsight-roadmap-v2-design.md)（Q3 行）  
**前序（已交付）：**  
- Phase 1–4、[Q1 0.5](./2026-07-11-moonsight-q1-playable-design.md)、[Q2 multi-track](./2026-07-11-moonsight-roadmap-v2-design.md)  
- [Pointer hit-test + Amber Soft 主题](./2026-07-11-moonsight-pointer-theme-ui-design.md)  

**实现路线：** A — 通用垂直 `UiNode::ScrollView` + 季内硬门禁债清单；backlog 独占消费；全套指针手势；Q3 其它项 MVP 并进。

---

## 1. 背景与目标

### 1.1 问题

相对 0.8「可发 demo 作 / 认真玩」门槛，系统与 UI 仍有明显缺口：

1. **回看不可滚** — `BacklogStore` ring 容量 100，UI 仅绑定固定 12 行 `BacklogLine`，长会话无法认真回看。  
2. **ScrollView 缺失** — retained UI 无 viewport/clip/offset 原语；后续长列表会重复造轮。  
3. **系统 UX 边角** — confirm 已有但需统一契约；槽位无占用视觉区分；Host 加载/失败态弱。  
4. **post-Q2 residual** — scale builtins 漂移、mid-dissolve 存档语义、ctrlHeld blur、文档滞后、人工 WebGPU 清单未关闭等。

主题包（Amber Soft）与引擎 pointer hit-test 已在 Q2 后补丁中交付；本季主题工作是**契约硬化**，不是从零做皮肤。

### 1.2 一句话

收口产品门槛 **0.8**：以通用垂直 **ScrollView** 让 backlog 可认真回看（键盘 + 滚轮 + 内容拖拽 + 滚动条），并进 Q3 系统 MVP，并清零 post-Q2 **可关闭** residual。

### 1.3 策略取向

| 决策 | 选择 |
|------|------|
| 实现路线 | **A** — 通用 `UiNode::ScrollView`，非 backlog 专用黑盒 |
| 第一消费面 | **仅 backlog**（其它 modal 本季不强制挂载） |
| 滚动输入 | **全套**：↑↓（可选 PgUp/PgDn）、滚轮、内容 pan、可拖 scrollbar |
| 同季其它 Q3 项 | **MVP 并进**（confirm / 槽占位 / 主题契约 / Host 错误态 / Docs） |
| 债 | **尽量清零** progress Residual；仅「可关闭」项作硬门禁；人工 WebGPU 跑通一次即关 |
| 冲突砍序 | 见 §4.7；保 ScrollView 手势 + P0 语义债优先于 Docs 厚度 |

### 1.4 范围

#### 必做

1. **`UiNode::ScrollView`（垂直）** — viewport、`scroll_y`、子树布局/命中/绘制 clip；scrollbar 轨道与 thumb。  
2. **全套滚动输入** — 见 §3。  
3. **回看数据面** — 展示条数对齐 ring（默认 100）；废除「固定 12 行占位」为唯一展示模型；空态 + Close 保留。  
4. **并进 MVP** — 通用 confirm 契约；槽位空/占用图标或等价视觉；主题逻辑角色表（含 scroll 资源）；Host 加载/错误可见态；作者文档增量（repo + Fumadocs）。  
5. **债扫尾门禁** — §4.6 清单 D1–D7。  
6. **验收** — 自动化门禁 + 人工 D6 清单；demo/默认 Svelte 路径不回退。

#### 明确不做

- 真槽位截图缩略图；运行时多主题商店 / 切换 UI  
- 横向 ScrollView；嵌套 ScrollView；惯性 fling / 橡皮筋 / 多指触摸  
- 虚拟化列表（100 行全量子树本季可接受）  
- 删除 `js_glue`、Host 全量收口（Q4–Q5）；`moonsight new` / 桌面原生存档（Q4）  
- 编辑器、Live2D、voice 轨、rollback、粒子/后处理  
- 将「CI 环境无 WebGPU」列为永久代码债（人工清单完成即关闭 D6）

### 1.5 成功标准（0.8 本季切片）

1. 写入 **>12** 条对话后打开 backlog：可滚到**最早**条目；滚轮 / 拖内容 / 拖条 / 键盘均可改变 `scroll_y`。  
2. 滚动中 modal 门控不变：不误 Advance 叙事；Close / Esc 关闭回看并清 drag 态。  
3. 覆盖存档 / 回标题等危险操作走**同一** confirm 模式（默认焦点 No）。  
4. 存读档槽空/占用有可读视觉区分，不依赖截图。  
5. §4.6 清单项全部**关闭**或**书面移出**（附理由，见移出表）。  
6. Fumadocs / repo 文档覆盖本季滚动与相关行为；无占位假完成。  
7. `moon check` / `moon test` 全绿；`moonsightc build demo` 与 host-web 构建成功。

---

## 2. 架构：ScrollView 与数据流

### 2.1 原则（沿用）

1. **Stage 叙事权威**；UI 经闭合 **Capabilities**。  
2. **游戏内 UI 不走 DOM**；Host 仅壳、输入、存储、错误页。  
3. **Hit-test 与 paint 同源**（布局几何 + `LaidFocus`）。  
4. **Scroll 状态在 `UiRuntime`**（per ScrollView 实例 / 随栈顶 modal），**不进存档**（与 modal 栈一致；backlog 本身会话-only）。  
5. 打开 backlog 时 **`scroll_y = max`（钉在最新）**；再次打开重置到最新（同会话**不**记忆 offset）。

### 2.2 节点模型

```text
UiNode::ScrollView {
  x, y, w, h     // viewport（逻辑 1920×1080）
  children       // 内容子树（backlog: VBox of Text 行）
}
```

运行时态（`UiRuntime`，非树字面量持久化）：

| 字段 | 含义 |
|------|------|
| `content_h` | 内容测量高度 |
| `scroll_y` | ∈ `[0, max(0, content_h - viewport_h)]` |
| drag 态 | `Idle` / `DragContent` / `DragBar` + 指针锚点 |

**布局：**

1. 在宽度约束下测量 `children` → `content_h`。  
2. 绘制与命中：子节点 y 减去 `scroll_y`。  
3. **Clip：** viewport 外不绘制、不命中。优先 **CPU 丢弃**出界 `UiDrawOp`；若有余力再引入 GPU scissor op（非阻塞本季验收）。  
4. **Scrollbar：** 轨道贴 viewport 右侧固定宽；thumb 高度 ∝ `viewport_h / content_h`（设最小 thumb 高）；位置 ∝ `scroll_y`。`content_h ≤ viewport_h` 时不显示 thumb（或禁用），输入 clamp 为 no-op。

**样式角色：** 新增稳定逻辑名 `ui.scroll_track` / `ui.scroll_thumb`（缺图 solid 回退）；可与 slider 资源视觉相近但名称独立，避免语义耦合。

### 2.3 数据流（backlog）

```text
BacklogStore (ring ≤100)
  → Engine sync_ui_bind
  → UiBindCtx.backlog_lines   // 完整列表，最长 = ring cap；旧→新
  → std_ui build_backlog:
       Panel + ScrollView { VBox[ Text(BacklogLine i) ... ] } + Close
  → layout → paint (+ clip) + focusables
  → pointer / wheel / key → 改 scroll_y → 下帧
```

**绑定演进：**

| 今日 | 目标 |
|------|------|
| `BacklogLine(0..11)` 固定 12 槽 | 按 `backlog_lines.length` 生成行；index 0 = 当前列表中最旧 |
| 空行仍占高 | 空 backlog：提示文案 + Close；无有效滚动 |

`TextBindSrc::BacklogLine(i)` 保留；`i` 越界 → 空串或隐藏（实现选一种并单测）。

### 2.4 包边界

| 包 | 职责 |
|----|------|
| `runtime/ui_types.mbt` | `UiNode::ScrollView`；必要时 focus 目标扩展 |
| `runtime/ui_runtime.mbt` | layout / clip / scroll 态 / 手势 / 键盘滚 |
| `runtime/ui_test.mbt` | ScrollView 与手势单测 |
| `runtime/engine.mbt` | `pointer_event` / 新 wheel 入口；modal 门控；bind 全量 backlog |
| `runtime/backlog*.mbt` | 容量与 push 语义保持；必要时辅助格式化 |
| `render/*` | 若需要 clip 标记或 scissor；否则消费已裁剪 ops |
| `std_ui/modals.mbt` | `build_backlog` 改 ScrollView；槽位占位视觉 |
| `host_web` + `apps/host-web` + `js_glue` | `export_pointer` phase=2 up；`export_wheel`；blur 清 skip；错误/加载 UI |
| `docs/*` + `apps/docs-site` | play-input / ui-moonbit / 站点作者页 |

### 2.5 Host 分层（不变）

```text
Svelte 壳 (boot / error / chrome)
  → TS GameSession (intent, prefs, save)
    → adapters (WebGPU, draw-list, wasm)
      → host_web.wasm (Stage + UiRuntime 权威)
```

滚轮与 pointer up 只增加 export 面，不把滚动逻辑放到 JS。

---

## 3. 输入、手势与门控

### 3.1 Host → Engine

| 事件 | 通道 |
|------|------|
| move / down / up / leave | `export_pointer(x, y, phase)`；**phase：0=move, 1=down, 2=up, 3=leave**（本季补齐 **2=up** 供拖拽结束） |
| wheel | **新** `export_wheel(x, y, dy: Float)` — 逻辑坐标 + 垂直 delta |
| 键盘 | 现有 `export_frame` intents（↑↓ 等） |
| Ctrl skip | `skip_held`；**window blur / visibility hidden → false**（双 host） |

**同一帧顺序：** `export_pointer` / `export_wheel` → `export_frame`。pointer/wheel 已消费交互时，host 将 pending key intent 置空（沿用 pointer-theme 约定）。

**滚轮符号（钉死）：** `dy > 0` → `scroll_y` **减小**（内容相对视口下移，露出**上方更早**条目）。实现用固定灵敏度常量 `k`，单测锁方向。键盘 ↑ 与「看更早」同向。

### 3.2 手势状态机

栈顶 modal 布局结果中存在 ScrollView 时：

```text
Idle
  wheel over viewport           → scroll_y += k * dy; clamp
  down on Close/其它 Button     → 正常 button（优先于 pan）
  down on thumb                 → DragBar
  down on track（非 thumb）     → 按 y 跳转比例；可进入 DragBar
  down on content（viewport 内）→ DragContent（记录 last_y）

DragContent
  move → scroll_y -= (y - last_y); last_y = y; clamp
  up / leave → Idle

DragBar
  move → 由指针 y 映射 thumb 中心 → scroll_y
  up / leave → Idle
```

**命中优先级（高 → 低）：**  
可聚焦控件（Button 等）→ scrollbar thumb → scrollbar track → 内容 pan →（Playing 空白 Advance **不**适用于 modal）。

### 3.3 门控

| 条件 | 行为 |
|------|------|
| modal 非空 | 只处理栈顶；禁止叙事 Advance / Select |
| backlog 打开 | wheel/drag 只改该 ScrollView；不穿透 Stage |
| `wait_remaining > 0` | 叙事门控与现网一致；modal 下本就不进叙事 |
| content 装得下 | thumb 隐藏/禁用；滚动输入 clamp no-op |
| 关闭 modal | 清 drag 态与 hover |

### 3.4 键盘（backlog）

- 栈顶为 backlog 且焦点不在 Slider：`MenuUp` / `MenuDown` 滚动 **一行高**；PgUp/PgDn（若 host 映射）滚动约 **0.9 × viewport_h**。  
- Close 按钮保持可焦点；Esc 关闭 modal。  
- 不在 backlog 内用 ↑↓ 假装「选中历史行」（本季历史只读浏览，不跳转剧本）。

### 3.5 输入非目标

触摸多指、惯性、overscroll 弹性、横向 wheel、拖选复制文本。

---

## 4. 并进 MVP 与债门禁

### 4.1 通用 confirm

- 单一 `confirm` modal + `ConfirmKind`（`OverwriteSave(i)` / `QuitToTitle`；已有）。  
- **契约：** 默认焦点 **No**；Yes/No 仅经 Capabilities；文案由 kind 绑定；打开时清 ScrollView drag 态。  
- 本季任何新危险操作必须走同一 modal，禁止第二套确认 UI。  
- 不做：作者自定义 confirm DSL、超过 Yes/No 的按钮集。

### 4.2 槽位占位 / 图标

- `save_load`：每槽空 / 占用视觉区分（逻辑资源如 `ui.slot_empty` / `ui.slot_filled`，或 panel + 标签样式差）。  
- `slot_labels` 与 `saved_at` 展示保持并修复已知遗漏（若仍存在菜单存档无时间戳等问题，归 D7）。  
- **不做** framebuffer 截图。

### 4.3 主题契约

- 文档钉死逻辑角色表（含 scroll / slot 新增名）。  
- 缺图 → solid；相对 URL 加载保持。  
- **不做** 运行时主题切换 UI。

### 4.4 Host

- **加载中 / 失败** 可读 UI（manifest、wasm、关键纹理硬失败），禁止静默空白。  
- Svelte 与 `js_glue` 对等：`phase=2`、`export_wheel`、blur→skip false。  
- 「glue TS 化」仅限本季 API 与错误面，不重写全部 adapter。  
- 删除 vanilla 主路径仍属 **Q5**。

### 4.5 Docs

- Repo：`docs/play-input.md`、`docs/ui-moonbit.md` 补 ScrollView / wheel / 手势。  
- Fumadocs：play-input 与回看/UI 相关页中英增量；`host-commands` / `project-layout` 能迁则迁，否则链到 repo 并标明权威源。  
- 目标：作者不读源码即可使用回看滚动与系统菜单。

### 4.6 债门禁（可关闭清单）

| ID | 项 | 关闭定义 |
|----|----|----------|
| D1 | scale builtins 漂移 | host builtins 与 `std_commands` / `@layer` scale 语义一致，有测 |
| D2 | mid-dissolve 存档 UX | 中途 save/load 后 dissolve 降级或恢复规则可测，且文档句一致 |
| D3 | ctrlHeld sticky on blur | blur / visibility → `skip_held` false；Svelte + js_glue |
| D4 | pointer 回归 | phase 仅 down 激活点击语义；modal 切栈清 hover；补测保持 |
| D5 | 文档滞后 | repo + 当季 Fumadocs 与指针/主题/dissolve/滚动行为一致 |
| D6 | 人工 WebGPU 清单 | 按 §5.2 **跑通一次**并写入验收记录即关闭 |
| D7 | 其它 Residual/MEDIUM | **修复**或**书面移出**（理由：已过时 / 超 Q3 范围 / 被更大项覆盖） |

**移出规则：** 不得静默忽略。移出项列入本 spec 附录 A（实现期可增补，须在 plan 验收时复审）。

### 4.7 砍序（工期冲突）

1. ScrollView 手势全集 + backlog 数据面  
2. D1–D4 语义债  
3. confirm 统一 + Host 错误态 + D3/D5  
4. 槽图标 + 主题角色  
5. Docs 厚度  
6. D6 人工清单 + D7 清扫  

---

## 5. 测试、验收与风险

### 5.1 自动化（硬门禁）

1. `moon check` + `moon test` 全绿。  
2. **ScrollView 单测：** clamp；wheel 方向；content / bar 拖拽；content≤viewport；clip 外不命中；打开钉最新。  
3. **Engine：** backlog 打开时 wheel/pointer 不 Advance；Confirm 默认 No；D1 scale 路径。  
4. **D2 dissolve：** 中途 save/load fixture 或单测 + 文档对齐。  
5. `moonsightc check/build demo`；`apps/host-web` build；若改站点则 `apps/docs-site` build。

### 5.2 人工（D6）

默认 **Svelte** 路径，`localhost` + WebGPU：

1. Title → Start → 刷 >12 句 → H 回看 → 滚轮 / 拖内容 / 拖条 / ↑↓ 到最早 → Close / Esc。  
2. 对话鼠标 Advance；选项点选；Esc 菜单；覆盖存档 confirm（默认 No）。  
3. dissolve + scale 可见；Ctrl skip 不破 `@flow.wait`；blur 后 Ctrl 不粘住。  
4. 坏资源或 wasm 失败时错误页可读。

### 5.3 风险

| 风险 | 缓解 |
|------|------|
| 无 scissor 字迹溢出 | CPU 丢弃出界 ops；scissor 为增强 |
| 100 行布局成本 | 本季接受；虚拟化非必做 |
| 双 host 分叉 | 同一 export；plan 含 js_glue 对等任务 |
| 债清零蠕变 | D7 移出表 + §4.7 砍序 |
| 手势与按钮抢 hit | §3.2 优先级；Close 永远优先 |

### 5.4 文档与后续流程

| 产物 | 路径 |
|------|------|
| 本 design | `docs/superpowers/specs/2026-07-11-moonsight-q3-system-ui-design.md` |
| 实现 plan（下一步） | `docs/superpowers/plans/2026-07-11-moonsight-q3-system-ui.md` |

总图 v2 的 Q3 行由本文件细化；**不**在本季直接改总图门槛定义，除非验收后宣布 0.8 达成时更新 README Scope。

流程：spec 审阅通过 → **writing-plans** 任务 DAG → SDD 实现。本文件**不是**逐任务 checklist。

---

## 6. 决策记录（brainstorming）

| 决策 | 选择 |
|------|------|
| 本轮范围 | Q3 + 已知债扫尾（非整段 Q3–Q5 大图重写） |
| Engine 主交付 | ScrollView / 回看可滚动 |
| ScrollView 消费面 | 仅 backlog |
| 滚动输入 | 全套指针手势 + 键盘 |
| 同季其它项 | MVP 并进 |
| 债策略 | 尽量清零 residual；可关闭定义 + 移出表 |
| 架构路线 | A — 通用 `UiNode::ScrollView` |
| 打开回看锚点 | 最新（scroll_y = max）；不记忆 offset |
| clip | 先 CPU 丢弃；scissor 可选增强 |
| 截图槽 | 不做；图标/占位 |
| 双 host | 本季保持语义对等；删除 vanilla 待 Q5 |

---

## 附录 A — Residual 移出表（初稿）

实现期填写「移出」行；关闭项在验收报告勾掉即可。

| 来源 | 项 | 处置（关闭 / 移出 / 待定） | 理由 |
|------|-----|---------------------------|------|
| Q2 final | interactive WebGPU play | D6 | 人工清单一次关闭 |
| Q2 final | builtins scale drift | D1 | 必关 |
| Q2 final | mid-dissolve save UX | D2 | 必关 |
| Q1 residual | sticky ctrlHeld on blur | D3 | 必关 |
| Pointer residual | pre-wasm Advance stash 等 | D4/D7 | 修或移出并说明 |
| Docs | Fumadocs 未覆盖 pointer/主题 | D5 | 与本季滚动文档一并关 |
| 历史 minor | lexer/工具链噪音、mbti 生成物 | 移出候选 | 非 0.8 播放门槛；移出须标注 |

---

## 附录 B — 与总图 Q3 对照

| 总图 Q3 表述 | 本 spec |
|--------------|---------|
| ScrollView（服务 backlog） | 主交付；通用节点 + 仅 backlog 挂载 |
| 通用 confirm 模式 | §4.1 最小统一契约 |
| 主题/皮肤最小 | Amber Soft 已有；本季契约 + scroll/slot 角色 |
| 槽位缩略图（可降级图标） | **降级图标/占位**（明确不做真截图） |
| Host glue TS / 加载错误 / Tauri | 加载错误 + 本季 API；Tauri 不阻塞（仍加载现 dist） |
| 作者手册主体中英 | §4.5 增量；完整厚度服从砍序 |
| Hygiene 控件回归 | D4 + 单测 + D6 |
| 门槛 0.8 收口 | §1.5；宣布时更新 README |
