# MoonSight — 指针 Hit-Test、主题系统与 Demo UI（Warm Nocturne）

**日期：** 2026-07-11  
**状态：** Approved / Implemented  
**仓库：** `moonsight`  
**路径选择：** C — 引擎 hit-test 主路径 + 最小完整主题系统  
**视觉：** Warm Nocturne **A1 Amber Soft**  
**前序：** Phase 4 UI 内核、Q1 playable、Q2 multi-track（Svelte host / dissolve / scale）  
**总图：** [roadmap v2](./2026-07-11-moonsight-roadmap-v2-design.md)

---

## 1. 背景与目标

### 1.1 问题

1. **Svelte host（`apps/host-web`）对话界面鼠标完全点不动** — 键盘 Advance / 选项仍可用；用户确认路径为 Svelte host。  
2. **可点组件范围窄** — 引擎已有 `UiRuntime::handle_pointer`，但 **host 未接线**；选项 hit 依赖 host 硬编码 `CHOICE_LAYOUT`；菜单 Button 无法点中具体项；无 hover。  
3. **Demo / 默认 UI 观感弱** — `ui.*` 多为冷蓝 solid placeholder；demo 仅改 title 文案；host 壳偏调试条。

### 1.2 一句话

修好指针输入，把 **完整控件 hit-test + hover/cursor** 收口到引擎权威路径，并交付 **Amber Soft 完整皮肤包** 与 **可扩展主题结构**（本轮只上默认一主题），刷新 `std_ui` / demo / host 壳三层视觉。

### 1.3 范围

#### 必做

| # | 能力 | 验收要点 |
|---|------|----------|
| 1 | **P0 鼠标可用** | Svelte host 对话可鼠标前进；选项可鼠标点选 |
| 2 | **引擎 hit-test** | Button / Choice / Slider 点击走 `LaidFocus`；删除 host `CHOICE_LAYOUT` 业务依赖 |
| 3 | **未命中 Advance** | Playing + 无 modal + 叙事可前进时，空白处 click → Advance（与键盘语义对齐，含 typewriter 门控） |
| 4 | **Hover** | `pointermove` 更新 hover；paint 使用 `*_hover` 资源；focus 优先于 hover |
| 5 | **Cursor** | host 按 hover 类型设 `pointer` / `ew-resize` / `default` |
| 6 | **主题系统** | 逻辑角色名稳定；`themes/amber_soft/theme.json` + 资源；缺图 solid 回退 |
| 7 | **完整皮肤包** | 对话框、名牌、选项行、按钮 idle/focus/hover、菜单 dim、滑条 track/fill |
| 8 | **三层视觉** | std_ui 默认树微调 + demo `ui_package` 品牌 + Svelte host 壳 Amber Soft |
| 9 | **文档** | `play-input.md` / `ui-moonbit.md`（或主题小节）与行为一致 |

#### 明确不做

- 运行时主题切换 UI / 多主题商店  
- 滑条拖拽 scrub（**点击轨道跳比例** 即可）  
- DOM 游戏内 UI、恢复 `- screen`  
- 编辑器、Live2D、新 MoonYuki 语法  
- 强制 Playwright E2E（本轮以 `moon test` + 手动 demo 清单为准）  
- 修改 third_party Slug 内核

### 1.4 成功标准

1. 冷启动 title → **鼠标**点 Start → 对话 **鼠标**推进 typewriter / 下一句。  
2. 选项出现时 **鼠标点行** 提交对应分支；↑↓ 仍可用。  
3. Esc 菜单 / 存读档 / Settings / Confirm：**鼠标点按钮** 生效；滑条 **点击轨道** 改变 prefs。  
4. 指针移过按钮/选项有 hover 外观；cursor 变化。  
5. 默认主题 Amber Soft 成片；host 壳不再像纯调试页。  
6. `moon test` / `moon check` 相关包绿；无占位假完成（hover/主题不得只改注释）。

---

## 2. 架构原则

1. **Stage 叙事权威**；UI 只经 **Capabilities**。  
2. **Hit-test 权威在引擎** — 与 paint 同源 `LaidFocus`，禁止 host 复制布局常量作业务真相。  
3. **逻辑资源名稳定** — paint 仍发 `ui.button` / `ui.button_focus` / `ui.button_hover` 等；主题只解析物理纹理。  
4. **键盘 Intent 路径保留** — pointer 是并行通道，不取代 Esc / ↑↓ / 1–9。  
5. **门控与键盘一致** — `wait_remaining > 0` 时不 Advance/Select；modal 非空时只栈顶；`skip_held` 语义不变。  
6. **游戏内 UI 不走 DOM** — host 壳可美化；HUD/菜单仍 WebGPU `UiDrawOp`。

---

## 3. 指针与输入

### 3.1 现状

| 路径 | 行为 |
|------|------|
| Host `pointerdown` | 命中硬编码 choice 行 → `Select(n)`；否则 `Advance` |
| `UiRuntime::handle_pointer` | 单测覆盖；**无 wasm 导出 / host 调用** |
| 菜单 | click ≈ Advance → 只激活 **当前焦点** 按钮，不能点其它项 |

### 3.2 目标数据流

```
pointerdown / pointermove (canvas)
  → pointerToLogical (1920×1080 letterbox-safe)
  → wasm export_pointer(x, y, phase, buttons)
       phase: 0=move, 1=down, 2=up(optional), 3=leave
       buttons: bit0 = primary down (for future drag; down 事件必带)

  Move / Leave:
    UiRuntime::pointer_hover(x,y) | clear_hover
    返回 hover_kind 供 cursor（或独立 export_hover_kind）

  Down:
    1. sync_ui_bind
    2. 若 modal 非空或 Title：handle_pointer(caps,x,y)；未命中则 no-op
    3. 若 Playing + stack empty：
         handle_pointer(caps,x,y)  // choices / 未来 HUD 按钮
         若未命中且叙事可前进 → 等价 Intent::Advance
    4. wait_remaining / Choose / typewriter 门控复用 Engine 现有逻辑
```

**键盘** 继续 `export_frame(intent, dt, skip_held)`。同一帧若既有 pointer down 又有 key intent：  
**约定：** pointer 先处理（host 在 frame 前调用 `export_pointer`），再 `export_frame`；避免双触发时，host 在 pointer down 的帧将 `pendingIntent` 置 `None`（pointer 已消费交互）。

### 3.3 未命中 Advance 规则

| 条件 | 结果 |
|------|------|
| Playing，stack empty，`wait_remaining == 0`，VM Yield/Choose 可处理 Advance | 空白 click → Advance（Choose 下 Advance = 确认焦点行，与键盘一致） |
| Choose 且点中某 choice 行 | `confirm_choice(i)`（非焦点行也可直接选） |
| modal / Title | 仅 hit-test 栈顶；空白不 Advance 叙事 |
| `wait_remaining > 0` | 忽略叙事 Advance/Select |

**整幅可点前进（已确认）：** 不要求必须点在 dialogue panel 上。

### 3.4 Slider 点击

- 命中 `UiFocusTarget::Slider(key)`：按点击 x 在 track 宽度内的比例写入 pref（0..1 映射到该 key 合法范围）。  
- **不做** 拖拽。  
- MenuLeft/Right 键盘步进保留。

### 3.5 P0 诊断清单（实现第一步）

在接线 `export_pointer` 前/同时验证 Svelte host：

1. `canvas` 是否收到 `pointerdown`（临时 log）  
2. `pointerToLogical` 是否在 0..1920 / 0..1080  
3. `pendingIntent` 是否进入 `export_frame`  
4. letterbox `fitCanvas` + `position:absolute` 是否导致错误 hit 区域  

根因修复纳入本规格，不单独开「以后再查」。

### 3.6 删除 / 降级

- 删除（或测完后删除）`apps/host-web` 与 `js_glue` 中 **业务用** `CHOICE_LAYOUT` / `choiceRowAt`。  
- vanilla `js_glue`：至少同等 `export_pointer` 接线，或明确文档「默认路径仅 Svelte」；**不得**留下半截默认可玩路径。

---

## 4. Hover 与 Cursor

### 4.1 引擎

- `UiRuntime` 增加 `hover : Int`（`-1` = none），与 modal `focus` / `hud_focus` 分离。  
- `pointer_hover(x,y)`：遍历当前 focusables，设 hover 索引。  
- `pointer_leave` / canvas leave：`hover = -1`。  
- paint 时对 Button / Choice（及需要的 Slider chrome）：  
  - `focused` → `*_focus`  
  - else `hovered` → `*_hover`  
  - else idle  

`UiDrawOp` 增加 `hovered : Bool`（或仅靠 resource 名区分；优先显式 `hovered` 以利测试）。

### 4.2 Host cursor

| hover_kind | CSS cursor |
|------------|------------|
| Button / Choice | `pointer` |
| Slider | `ew-resize` |
| none，且 Playing 可 Advance | `default` |
| none，不可交互 | `default` |

`export_pointer` 返回 hover_kind 码，或 `export_hover_kind()` 只读。

---

## 5. 主题系统

### 5.1 逻辑角色（稳定 ID）

| 角色 | 用途 |
|------|------|
| `ui.dialogue_box` | 对话框底 |
| `ui.nameplate` | 名牌 |
| `ui.choice_row` | 选项行 idle |
| `ui.choice_row_focus` | 选项行 focus（若无则回退 `ui.choice_row` + focus 色） |
| `ui.choice_row_hover` | 选项行 hover |
| `ui.button` | 按钮 idle |
| `ui.button_focus` | 按钮 focus |
| `ui.button_hover` | 按钮 hover |
| `ui.menu_dim` | 菜单遮罩 |
| `ui.slider_track` | 滑条轨道 |
| `ui.slider_fill` | 滑条填充 |

`render/snapshot.mbt` 常量与 paint 路径对齐；新增 hover/slider 常量。

### 5.2 主题包布局

```
apps/host-web/public/themes/amber_soft/
  theme.json
  dialogue_box.png
  nameplate.png
  choice_row.png
  choice_row_focus.png
  choice_row_hover.png
  button.png
  button_focus.png
  button_hover.png
  menu_dim.png          # 可选；可 solid
  slider_track.png
  slider_fill.png
```

构建产物：`dist/**/themes/amber_soft/`（或打进 host dist 根 `themes/`），保证离线 demo 可加载。

**`theme.json` 形状（示意）：**

```json
{
  "id": "amber_soft",
  "display_name": "Amber Soft",
  "fallback_solids": {
    "ui.dialogue_box": [22, 16, 20, 220],
    "ui.button": [48, 36, 40, 220],
    "ui.button_focus": [120, 72, 48, 240],
    "ui.button_hover": [90, 56, 42, 230]
  },
  "roles": {
    "ui.dialogue_box": { "file": "dialogue_box.png" },
    "ui.button": { "file": "button.png" },
    "ui.button_focus": { "file": "button_focus.png" },
    "ui.button_hover": { "file": "button_hover.png" }
  }
}
```

未列出的角色 → `fallback_solids` → 最后引擎/host 内置冷回退（应尽量不触发）。

### 5.3 解析位置

| 层 | 职责 |
|----|------|
| 引擎 | 只发逻辑名 + focused/hovered |
| Host | 读 `theme.json`，`createTexture` / `makePlaceholderSolid` 注册到与 `resource_name` 一致的 key |
| 项目 | `moonsight.json` 可选 `"theme": "amber_soft"` 或 `"theme_path": "themes/amber_soft"`；默认 `amber_soft` |
| Demo | 可覆写主题文件或 `demo/game/ui` 树；不强制第二套主题 ID |

**本轮不实现** 游戏内切换主题的 UI；结构上多主题目录可并存。

### 5.4 视觉语言（A1 Amber Soft）

| Token | 意向 |
|-------|------|
| 底 | 暖墨 / 深褐黑 `#100e12`–`#1a1520` |
| 强调 | 琥珀 `#d4a06a` / 焦点更亮 |
| 文本 | 暖白 `#f2ebe4`；名牌 `#e0b080` |
| 次要紫 | 极低饱和玫瑰紫余韵（可选光晕，勿抢主色） |
| 圆角 | 面板约 10–12px 等效（位图内制作） |
| Host 壳 | 同色系背景、status/hint 低对比、加载态友好 |

资产可用手绘 PNG 或程序生成后 **写入主题目录**（提交可复现文件）；禁止仅改一处 `makePlaceholderSolid` 常量却声称「完整皮肤包」而未落主题结构。

---

## 6. 组件与文件触点

| 区域 | 文件（预期） | 变更 |
|------|----------------|------|
| 引擎 UI | `runtime/ui_runtime.mbt`, `ui_types.mbt`, `ui_test.mbt` | hover、pointer API、Slider 点击比例、paint hovered |
| 引擎 tick | `runtime/engine.mbt` | 未命中 Advance 与门控；可选统一 pointer 入口 |
| 资源常量 | `render/snapshot.mbt` | hover / slider 逻辑名 |
| paint | `runtime` button/choice paint 路径 | 选 focus/hover/idle 资源 |
| std_ui | `std_ui/hud.mbt`, `modals.mbt` | 布局层次微调（非必须大改树） |
| wasm host | `host_web/main.mbt` | `export_pointer`、hover_kind、主题预 intern |
| Svelte host | `apps/host-web/src/lib/gameSession.ts`, `App.svelte`, `app.css` | 接线 pointer、cursor、壳美化、去 CHOICE_LAYOUT |
| GPU | `apps/host-web/src/adapters/webgpu_bridge.js`（及 js_glue 对齐） | 主题加载 / solid 回退色 |
| 主题资产 | **权威路径** `apps/host-web/public/themes/amber_soft/**`；`moonsightc build` 复制进 dist；js_glue 可镜像或读同一 public | 完整包 |
| Demo | `demo/game/ui/lib.mbt`, 可选 `moonsight.json` theme 字段 | 品牌 title / 主题指向 |
| 文档 | `docs/play-input.md`, `docs/ui-moonbit.md` | pointer / theme |
| 构建 | `cmd/moonsightc/build.mbt` 如需复制主题进 dist | dist 可玩 |

---

## 7. 错误处理

| 情况 | 行为 |
|------|------|
| 主题目录缺失 | 使用内置 Amber Soft solids；status 可提示一次 |
| 单角色图加载失败 | 该角色 solid 回退；不中断帧循环 |
| `export_pointer` 在未 init engine 时调用 | no-op 返回 |
| 坐标越界 | clamp 到 canvas 逻辑范围再 hit-test |
| 非法 pref 比例 | clamp 到 slider 合法区间 |

---

## 8. 测试计划

### 8.1 自动（`moon test`）

- `handle_pointer`：按钮 / 多按钮点中正确 action  
- Choice 行点击 `confirm_choice` 索引  
- Slider 点击中点 → pref ≈ 中值  
- hover：move 设置 / leave 清除；paint `hovered` 或 hover 资源  
- focus 优先于 hover  
- 未命中 + Playing Yield → Advance 语义（engine 级）  
- `wait_remaining > 0` 时 pointer Advance 无效  
- modal 打开时 pointer 不推进叙事  

### 8.2 手动 demo 清单

1. Title：鼠标点 Start / Settings / 返回  
2. 对话：点击空白前进；点选项 Talk/Leave  
3. Esc 菜单：点各按钮；Save/Load 槽；Confirm Yes/No  
4. Settings：点滑条左右半区  
5. Hover + cursor 可见  
6. 键盘回归：Enter/方向/1–9/Esc/H/Ctrl  

### 8.3 非目标测试

- 无强制浏览器 E2E 框架（可后续 Hygiene）

---

## 9. 实现分期（建议，供 plan 切片）

| 阶段 | 内容 |
|------|------|
| **P0** | 诊断并恢复 Svelte 点击；`export_pointer` + handle_pointer + 未命中 Advance；删 CHOICE_LAYOUT |
| **P1** | hover 状态 + hover 资源 + cursor |
| **P2** | ThemeManifest + amber_soft 包 + host 加载 + solid 回退色改暖 |
| **P3** | std_ui/demo 微调 + Svelte 壳美化 + 文档 |

可并行：P2 资产制作与 P0 输入互不阻塞。

---

## 10. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 「完全点不动」根因非缺 handle_pointer | P0 诊断清单强制先做 |
| 主题图工作量爆炸 | 允许程序生成 PNG 落盘；结构完整优先于手绘艺术 |
| js_glue 与 Svelte 双路径漂移 | 共享 adapter 或文档标明默认 Svelte 并同步 pointer API |
| 同帧 pointer + key 双触发 | host 约定 pointer 帧清空 pendingIntent |
| hover 每帧 layout 成本 | focusables 列表与 paint 同路径，规模小（菜单级） |

---

## 11. 决策记录（brainstorm）

| 问题 | 决定 |
|------|------|
| 鼠标症状 | 完全点不动（Svelte host） |
| 点击范围 | 完整 hit-test + hover + cursor |
| 视觉层 | 全面：std_ui + demo + host 壳 |
| 风格 | Nocturne 暖化 → **A1 Amber Soft** |
| 材质 | 完整皮肤包 |
| 架构 | **C** 主题系统 + 引擎 hit-test |
| 空白前进 | 整幅可点（不限对话框） |
| 主题切换 UI | 不做；仅结构可扩展 |
| E2E | 不强制 Playwright |

---

## 12. 相关文档

- [`docs/play-input.md`](../../play-input.md) — Intent / skip / wait  
- [`docs/ui-moonbit.md`](../../ui-moonbit.md) — UiApp / HUD / modal  
- Phase 4 UI kernel design  
- Q1 playable design  
- Roadmap v2（Q3 含 theme/scroll；本规格将 **主题最小集 + 指针** 提前作为 hygiene/体验补丁，不替代 Q3 ScrollView）
