# MoonSight Phase 4 — MoonBit UI 内核与可定制界面

**日期：** 2026-07-10  
**状态：** Approved for implementation planning  
**仓库：** `moonsight`  
**前序：**  
- [Phase 1 运行时内核设计](./2026-07-10-moonsight-runtime-design.md)  
- [Phase 2 图层与演出语义硬化](./2026-07-10-moonsight-phase2-layers-design.md)  
- [Phase 3 Screen 语言与系统 UI](./2026-07-10-moonsight-phase3-screen-ui-design.md)

## 1. 背景与目标

### 1.1 问题

Phase 3 交付了 Screen DSL（`.yuki` `- screen`）、系统四屏、多槽存档与 prefs。仍存在结构性缺口：

1. **叙事 HUD 硬编码** — 对话框 / 姓名牌 / 选项由 `render` 经 `UiLayout` 绘制，作者无法用与系统菜单同一模型替换布局或皮肤。  
2. **UI 能力闭合过死** — `ScreenAction` 枚举扩展成本高；自定义行为不能以类型安全的 MoonBit 回调表达。  
3. **双轨语义** — 系统菜单走 Screen 栈，对话走 Stage+UiLayout，耦合分散在 `runtime/screen`、`render/snapshot`、host。  
4. **作者面偏 DSL** — 游戏无法以 **MoonBit 一等包** 编写完整界面；长期目标是引擎内统一 UI 框架，而非永久依赖 Screen DSL。

### 1.2 Phase 4 定位

**一句话：** 引入 **retained MoonBit UI 内核**（双表面：base HUD + modal 栈），用其实现默认真话/选项与系统菜单；**游戏 MoonBit UI 包与引擎同链一份 wasm**；用 **闭合 Capabilities + 游戏回调** 表达动作；**切断** 项目 `- screen` / `screens.json` 主路径。

**策略取向：** 架构 **A（Retained UiTree + dual slots）**；优先序 **叙事 HUD 可定制 → 动态/可编程 → 控件丰富度（后者本阶段仅 MVP）**。

### 1.3 范围

#### 必做

1. **`runtime/ui` 内核** — `UiTree` / 布局 / 焦点 / 命中 / 绑定刷新 / `UiDrawOp` 绘制请求。  
2. **双表面** — `HudSlot`（对话+选项）+ `ModalStack`（系统菜单等）；统一组件模型、分开生命周期与输入门控。  
3. **Capabilities** — 引擎实现的闭合系统原语；按钮等经 MoonBit 回调调用。  
4. **`std_ui`（MoonBit）** — 默认 HUD + title / game_menu / save_load / settings；行为对齐 Phase 3。  
5. **同 wasm 链接** — `moonsightc build` 链接 `std_ui` + 可选项目 `ui_package`。  
6. **解耦 render** — 删除 `UiLayout` 对话/选项硬路径；几何由 UI 树表达。  
7. **切断 Screen DSL 主路径** — 项目 `- screen` 为编译错误；不再发布/依赖 `screens.json` 作为主 UI 源。  
8. **demo + 文档 + 测试** — 默认可玩；可选 demo 项目 UI 覆盖；`moon test` 全绿。

#### 明确不做

- 完整控件集（拖拽 slider、通用主题文件、复杂动画）— 仅留扩展点  
- 第二 wasm / 动态加载 UI 模块  
- DOM / 混合 HTML 菜单  
- `.yuki` Screen 的 lower 兼容层（本阶段 **直接迁走**，不做双轨长期支持）  
- backlog、槽位截图、可视化编辑器、i18n、Live2D  
- 开放任意 host 字符串 action / 通用表达式语言  

### 1.4 成功标准

1. 冷启动 **title**（MoonBit）→ Start → 叙事 entry。  
2. Playing 时对话与选项 **仅** 经 HUD 树绘制；替换 `set_hud` 可改变布局。  
3. Esc 系统菜单、多槽存读、prefs 行为相对 Phase 3 **不回退**。  
4. 项目可配置 `ui_package`，链接后覆盖 title 与/或 HUD；回调只经 Capabilities。  
5. 项目含 `- screen` → **build 失败**，诊断含迁移指引。  
6. `moon test` 全绿；无占位/假实现。

### 1.5 实现切片（高层次）

1. `runtime/ui` 内核 + Capabilities trait + 单测  
2. Engine 输入门控接线；render 消费 `UiDrawOp`  
3. `std_ui` 默认 HUD + 四屏；删除硬编码对话路径  
4. `moonsightc` 同 wasm 链接；删除 screen 编译/打包主路径  
5. demo / 文档 / 全量验证  

---

## 2. 架构

### 2.1 原则

1. **Stage 是叙事权威状态**（text、choices、layers、vars）；UI 只绑定展示并触发 Capabilities。  
2. **双表面：**  
   - **HudSlot** — Playing 时 base HUD（对话 + 选项），非 modal。  
   - **ModalStack** — title / game_menu / save_load / settings 等。  
3. **同一组件模型：** 两边均为 retained `UiTree`（布局、焦点、绘制一致）。  
4. **输入门控：** modal 非空 → 只处理栈顶；否则 Playing 叙事 Intent + HUD（选项焦点等）。  
5. **动作边界：** 闭合 Capabilities（引擎）+ 游戏/std 回调；禁止 UI 直调 VM 内部 API。  
6. **构建：** 项目 UI 与 `host_web` **同编一份 wasm**；启动时 `register`。  
7. **render 只读绘制数据：** 不解释 Stage 对话几何；不保留对话硬路径。  
8. **存档不变：** 叙事 v3 + 独立 prefs；UI 栈与焦点 **不进档**。

### 2.2 逻辑分层

```
Game UI package (MoonBit, linked into host wasm)
  register · set_hud · register_modal · callbacks
                    │
                    ▼
runtime/ui — UiRuntime (HudSlot + ModalStack)
  layout · focus · hit-test · binds · Capabilities
         │                         │
         ▼                         ▼
   render (DrawList)         Engine / VM / Stage / prefs / save
```

依赖方向：`game_ui` / `std_ui` → `runtime/ui` → `render`（仅绘制）与 Engine 能力；`script` 只服务叙事，不再承担 Screen DSL 主路径。

### 2.3 与 Phase 3 的关系

| Phase 3 | Phase 4 |
|---------|---------|
| `- screen` + `screens.json` | 删除主路径；项目使用 → 编译错误 |
| `ScreenAction` 闭合枚举 | 折叠为 Capabilities + 回调 |
| `std_screens/*.yuki` | 由 `std_ui` MoonBit 包替代 |
| `UiLayout` 画对话/选项 | 删除；默认几何在 `std_ui` HUD |
| `ScreenState` 栈 | 由 `UiRuntime` modal 栈 + HudSlot 取代（可演进重命名） |

### 2.4 UiMode（保留语义）

| 模式 | 含义 |
|------|------|
| `Title` | 冷启动 / 回标题；title modal 在栈上 |
| `Playing` | 叙事可推进；无 modal 时 HUD 可见 |
| `Menu` | modal 栈非空（含从 Playing 打开的菜单） |

也可用「栈深度 + 是否已 start_game」表达；文档层保留 Title vs Playing。

---

## 3. 组件与 MoonBit API

### 3.1 包边界

| 路径 | 职责 |
|------|------|
| `runtime/ui`（新，或 `runtime` 内模块） | `UiNode`、`UiTree`、`UiApp`、`UiRuntime`、布局/焦点/命中、Capabilities、与 Engine 接线 |
| `std_ui`（新） | 默认 HUD + 四 modal；替代 `std_screens` |
| 项目 `ui/`（约定） | 游戏一等 UI；导出 `register(app)` |
| `render` | layers + `UiDrawOp` → DrawList；无对话硬编码 |
| `script` | 叙事 only；遇到 `- screen` → 错误 |
| `moonsightc` | 链接 UI 包；不再合并 `screens.json` 为主产物 |
| `host_web` | init 调用 std 再 game `register`；指针/键盘 → Intent |

### 3.2 控件 MVP

| 类别 | 节点 |
|------|------|
| 布局 | `VBox`、`HBox`、`Fixed`、`Spacer` |
| 内容 | `Text`、`TextBind`、`Image`、`Button`、`Panel`（色块/占位 resource） |
| HUD 辅助 | `ChoiceList`（或由 Button 列表等价实现；std 可用专用节点简化绑定） |
| 可见性 | `VisibleIf(predicate)` |

**本阶段不做：** 拖拽 slider、滚动视图、通用样式表、变换动画栈。

### 3.3 绑定与谓词（最小可编程）

**TextBind 源：**

| 源 | 含义 |
|----|------|
| `DialogueName` / `DialogueBody` | Stage 打字机可见名/正文 |
| `Pref(key)` | prefs 只读展示 |
| `SlotLabel(i)` | 存档槽展示 |
| `Var(name)` | Stage 变量只读展示 |

**VisibleIf 谓词（枚举，可扩展）：**  
`HasText`、`HasChoices`、`PrefBool(key)`、`SlotOccupied(i)`、`ModeIs(save|load)`、`Always` / `Never`。

无通用表达式语言。

### 3.4 UiApp 注册面

```text
UiApp:
  set_hud(tree: UiTree) -> Unit
  register_modal(name: String, tree: UiTree) -> Unit
  // 可选：on_boot 钩子；默认 boot 行为见 4.x
```

**覆盖顺序：** `std_ui.register(app)` 先，项目 `register(app)` 后；后写的 `set_hud` / 同名 `register_modal` 生效。

**约定导出：** 项目 UI 包提供：

```text
pub fn register(app : UiApp) -> Unit
```

（具体类型路径以实现包名为准，如 `@runtime.UiApp` 或 `@ui_runtime.UiApp`。）

### 3.5 Capabilities（闭合）

引擎实现；UI 回调只拿此面：

| 能力 | 语义 |
|------|------|
| `start_game` | 清 modal（或按策略）、加载 entry、`Playing` |
| `quit_to_title` | 拆叙事、Title、压 title modal |
| `show_modal(name, mode?)` | 压栈；`mode` 用于 save_load 等 |
| `return_modal` | 弹一层；Menu 且空栈 → Playing |
| `hide_modal(name?)` | 弹顶或移除匹配名 |
| `save_slot(i)` / `load_slot(i)` | 多槽存读；load 后 Playing、清栈 |
| `slot_occupied(i)` / `slot_label(i)` | 供绑定与 focus 过滤 |
| `set_pref` / `adjust_pref` | 写 prefs 并 `apply_prefs` |
| `confirm_choice(i)` | 提交叙事选项并清 choice UI 状态 |
| `advance` | 与 Playing 下 Advance 对齐（完成打字机或推进 VM） |

未知 modal 名、非法 slot：**noop + 诊断日志**，不 panic。

**回调形态（概念）：** `fn(caps: Capabilities) -> Unit`，可选附带只读 `UiCtx`（当前 mode、slot 数等）。

### 3.6 默认 std_ui 行为

与 Phase 3 对齐：

- **title：** Start / Load / Settings  
- **game_menu：** Continue / Save / Load / Settings / Title  
- **save_load：** 槽 0..N-1；`mode=load` 时空槽不可聚焦；Back  
- **settings：** text_speed、auto、master/BGM/SE；Back  
- **HUD：** 对话盒 + 姓名牌 + 正文绑定 + 选项列表；无 text/choices 时用 VisibleIf 隐藏  

默认 **N = 6**；`moonsight.json` 的 `save_slots` 继续生效（clamp 1..20）。

### 3.7 项目配置

```json
{
  "entry": "main.yuki",
  "ui_package": "ui",
  "save_slots": 6
}
```

- 省略 `ui_package` → 仅链接 `std_ui`  
- `ui_package` 为相对项目根的 MoonBit 包路径  

---

## 4. 数据流、输入与绘制

### 4.1 Tick 顺序

1. Host → Intent（及可选指针坐标）。  
2. Engine 路由：  
   - **modal 非空：** `UiRuntime` 处理栈顶（MenuUp/Down、Advance=Activate、指针命中、Esc=`return_modal`）。  
   - **Playing 且空栈：** 有 choices → HUD 焦点/确认；否则叙事 Advance / Select；点击空白可 Advance（保持现手感）。  
   - **Title：** title 在栈上，走 modal 路径。  
3. 叙事 VM tick：仅 `Playing && stack.is_empty()`。菜单打开时保留 Stage 画面；wait/tween 策略对齐 Phase 2/3（菜单不吞掉已启动 wait 的语义：关闭后继续）。  
4. `UiRuntime.sync_binds(Stage, Prefs, slots)`。  
5. layout → paint → `UiDrawOp` → `render` 打包 DrawList。

### 4.2 OpenMenu

- Playing + 空栈 → `show_modal("game_menu")`  
- 已有 modal → Esc = `return_modal`  

### 4.3 绘制顺序（先下后上）

1. 叙事 layers（kind + z）  
2. 菜单 dim（有 modal 时）  
3. 栈顶 modal 控件  
4. HUD（仅 Playing 且空栈）  
5. `trans.fade` 全屏 veil  

### 4.4 render 解耦

- 删除 `build_draw_list` 内基于 `UiLayout` 的 dialogue / nameplate / choice 分支。  
- `UiLayout` 收缩为 canvas 度量 / 默认字号常量（可改名 `CanvasMetrics`），或仅保留 canvas 尺寸供 layer 全画布 sprite。  
- 占位 resource id（`ui.dialogue_box`、`ui.button` 等）由 UI 树 `Panel`/`Image` 引用；host 缺贴图时占位色逻辑可保留。

### 4.5 存档

- 体：叙事 save **v3**；prefs 独立键。  
- UI 栈、焦点、HUD 树实例 **不序列化**。  
- 读档：恢复叙事 → Playing → 清 modal 栈；HUD 随 Stage 绑定自动更新。

### 4.6 错误与诊断

| 情况 | 行为 |
|------|------|
| 项目含 `- screen` | **编译/check 失败**，迁移说明指向 MoonBit `UiApp` |
| 未注册 modal | noop + 日志 |
| boot 需要 title 但未注册 | **build 失败**（要求存在 `title` modal 注册；std 保证） |
| 回调非法 slot / pref | clamp 或 noop + 日志 |
| 更高 save version | 拒绝（同前） |

---

## 5. 构建链接与迁移

### 5.1 同 wasm 链接

`moonsightc build` 逻辑步骤：

1. 编译叙事 `.yuki` → `game.msb`（**无**主路径 `screens.json`）。  
2. 解析 `ui_package`（可选）。  
3. 构建可链接 moon 图：`host_web` + `runtime` + `render` + `audio` + `std_ui` + 可选项目 UI。  
4. 产出 `host_web.wasm` 拷入 dist。  
5. 打包 assets、manifest、js_glue。  

Init 顺序：`std_ui.register(app)` →（若有）`game_ui.register(app)` → boot 显示 title。

具体 monorepo path / 临时 `moon.mod` 生成由实现计划钉死；作者体验钉为：**只维护项目 `ui/` + `moonsight.json` 字段**。

### 5.2 迁移切断

| 旧物 | Phase 4 |
|------|---------|
| `std_screens/*.yuki` | 删除或仅作历史参考；运行时不读 |
| 项目 `- screen` | 硬错误 + 迁移指引 |
| `screens.json` | 退出 dist 主路径 |
| `ScreenDef` / `ScreenAction` 主路径 | 移除或过渡后删除 |
| `docs/screen-language.md` | 废弃声明，指向新 `docs/ui-moonbit.md` |
| demo | 默认 `std_ui`；可选 `demo/game/ui` 覆盖样例 |

### 5.3 文档交付

- 新：`docs/ui-moonbit.md`（作者：UiApp、Capabilities、绑定、覆盖）  
- 更新：README、project-layout、host-commands、screen-language（废弃）  
- **叙事桥（钉死）：** 保留 `@ui.show` / `@ui.hide` 作为叙事侧 bridge，内部调用 `Capabilities.show_modal` / `hide_modal`；**不**再加载 Screen IR / `screens.json`。

---

## 6. 测试与风险

### 6.1 测试矩阵

| 层 | 覆盖 |
|----|------|
| `runtime/ui` | 布局、焦点环、modal 栈、VisibleIf、bind 刷新；Capabilities test double |
| Engine | 输入门控、菜单暂停叙事、HUD choice 确认、OpenMenu/Esc |
| render | 无 UiDrawOp 时无对话精灵；layers 仍绘制 |
| `std_ui` | 默认四屏 + HUD 逻辑烟测 |
| moonsightc | 拒绝 `- screen`；识别 `ui_package` |
| 回归 | 现有 VM / save / audio / layer 测试保持绿 |

### 6.2 风险

| 风险 | 缓解 |
|------|------|
| 每游戏重链 wasm 变慢 | 缓存 build；文档写增量流程 |
| 回调/树所有权与 wasm 生命周期 | 注册期建树；计划钉所有权规则 |
| 范围膨胀 | 控件 MVP 冻结；slider/主题不做 |
| Phase 3 文档/demo 漂移 | 切断与 docs/demo 同交付集 |
| ChoiceList vs 手写 Button | std 用一种；文档说明等价扩展方式 |

### 6.3 非目标回顾

可视化编辑器、DOM 菜单、双 wasm、yuki screen 兼容层、富主题系统 — 均不在本阶段。

---

## 7. 决策记录（brainstorm）

| 决策点 | 选择 |
|--------|------|
| 作者面 | MoonBit 作为引擎 UI 框架；游戏包一等公民 |
| 优先序 | 叙事 HUD → 动态/回调 → 控件丰富度 |
| 表面模型 | base HUD 槽 + modal 栈 |
| 构建 | 同编进 `host_web` wasm |
| 动作 | Capabilities + 游戏回调 |
| Screen DSL | 本阶段直接迁走（无 long-term lower 兼容） |
| 架构 | Retained UiTree + dual slots |

---

## 8. 成功标准检查表（验收）

- [ ] 无项目 UI 时，std 行为 ≈ Phase 3 系统菜单 + 新默认对话 HUD  
- [ ] 对话/选项几何不来自 `render` 硬编码 `UiLayout` 路径  
- [ ] 项目 `ui_package` 可覆盖 HUD 与 title  
- [ ] `- screen` 构建失败  
- [ ] 存读档与 prefs 回归通过  
- [ ] `moon check` / `moon test` 全绿  
- [ ] 作者文档 `docs/ui-moonbit.md` 可依样写出覆盖包  
