# MoonSight Phase 3 — Screen 语言与系统 UI

**日期：** 2026-07-10  
**状态：** Approved for implementation planning  
**仓库：** `moonsight`  
**前序：**  
- [Phase 1 运行时内核设计](./2026-07-10-moonsight-runtime-design.md)  
- [Phase 2 图层与演出语义硬化](./2026-07-10-moonsight-phase2-layers-design.md)

## 1. 背景与目标

### 1.1 问题

Phase 1–2 交付了可玩的运行时内核与图层/演出语义（MoonYuki → IR/MSB、VM、Director、Stage、WebGPU、存读档 v3、tween、`flow.wait` 等）。系统层仍缺口明显：

- `OpenMenu` Intent 已定义，无默认菜单实现
- 存档实质为单槽快捷键 + `localStorage`，无多槽 UI
- 无标题冷启动、无设置页（语速/自动/音量）
- 对话框/选项依赖硬编码 `UiLayout`；长期需要**可自定义界面**
- Phase 2 残留债：命名负号参数（`x=-200`）、音频加载 warn-only、BGM 无 volume/fade

若系统菜单先硬编码进 Engine，自定义 UI 时几乎必然返工。

### 1.2 Phase 3 定位

**一句话：** 引入**最小 Screen 语言 + Screen 运行时**，用其实现标准 VN 系统 UI（标题/菜单/存读档/设置），并清掉挡作者与挡本阶段的 D/B 债；为日后自定义 UI 留下同一扩展路径。

**策略取向：** A（系统 UX）为主 + D（扫债）+ 少量 B（语言/音频）；UI 走 **S1（Screen DSL）**，非永久硬编码菜单，非 DOM 覆盖层。

### 1.3 范围

#### 必做

1. **Screen 语言子集** — `.yuki` 顶层 `- screen`；控件 `vbox` / `hbox` / `fixed` / `text` / `button`；闭合 **action** 枚举。
2. **Screen 运行时** — 实例栈、焦点、键盘/指针导航、action 执行；与叙事 VM 门控。
3. **标准四屏** — `title`、`game_menu`、`save_load`、`settings`（引擎默认 + 项目同名覆盖）。
4. **核心三件套 UX** — 多槽存读档、系统菜单、基础设置（语速/自动/主音量/BGM/SE）。
5. **冷启动** — 启动进 `title`，非直接跑 entry scene。
6. **全 WebGPU** — 控件进 draw list；无 DOM 菜单。
7. **D+B 地基** — 命名负号 lexer；音频 hard-fail；`@audio.bgm` volume/fade；构建失败不留坏 `out_dir`。
8. **demo + 文档 + 测试** — 冷启动 demo；host/语法/布局文档；核心单测全绿。

#### 明确不做

- 回看 / backlog
- 槽位截图缩略图、存档二次确认框
- DOM / 混合 HTML 菜单
- 对话框 / 选项 screen 化（仍硬编码 `UiLayout`；可列 Phase 3.1）
- `if` / 通用表达式 / `image` / slider 拖拽 / 主题系统
- SE fade；OS 用户目录存档（仍 webview `localStorage`）
- layer scale / color_mul；对话内联大修（stretch，不承诺）
- 可视化编辑器、i18n、成就、Live2D、native GPU、完整时间轴

### 1.4 成功标准

1. 冷启动 **title** → Start 进入叙事 entry。
2. Playing 中 Esc → **game_menu**；可存/读 **6** 槽（可配置）、改设置并持久化。
3. 回标题保留 prefs；读档恢复叙事 + Stage 逻辑态；screen 栈不入档。
4. 作者可定义同子集 `- screen`，经 `@ui.show` / action 打开。
5. `x=-200` 命名参数可用；缺音频资源构建或加载可读失败；BGM volume/fade 可感知。
6. `moon test` 全绿；`builtin_externs` 与 registry 对齐（含 `ui.*` 扩展）。

### 1.5 实现路线（高层次）

1. D+B 地基  
2. Screen IR + 解析/lower + std 合并  
3. Screen 运行时 + Intent + Engine 门控  
4. Prefs + 多槽 header + host 存储  
5. render 绘制 screen  
6. 标准四屏 + demo  
7. 文档与全量验证  

---

## 2. 架构：Screen 模型与输入

### 2.1 原则（沿用 Phase 1–2）

1. **Stage 是场景权威状态**；Renderer 只读 snapshot。  
2. **叙事脚本**通过 host 改世界；**Screen**通过 action / `@ui.*` 改 UI 栈与系统状态。  
3. **存档 = 叙事 VM + Stage 逻辑快照 + 变量**（+ 音频逻辑）；**不含** screen 栈、GPU 句柄。  
4. **Prefs** 独立于槽位存档。  
5. 依赖单向：`script` ↛ `render`；`runtime` 不绑定具体 GPU API。

### 2.2 逻辑分流

```
叙事 MoonYuki (- scene …)          Screen DSL (- screen …)
        │                                    │
        ▼                                    ▼
   叙事 IR / VM                      ScreenDef 注册表
        │                                    │
        │         @ui.show / OpenMenu         │
        ▼                                    ▼
         Stage + Engine：UiMode、screen 栈、焦点、prefs 应用
                              │
                              ▼
                     snapshot → DrawList → WebGPU
```

### 2.3 UiMode

| 模式 | 含义 |
|------|------|
| `Title` | 冷启动；显示 `title`；叙事 VM 未进入或已 teardown |
| `Playing` | 正常叙事；可 Advance / Choose |
| `Menu` | 存在 modal screen 栈（如 `game_menu` / `save_load` / `settings`） |

也可用「仅 screen 栈深度」表达 Menu，但文档层保留 **Title vs Playing** 区分。

### 2.4 Screen 栈

- 栈元素：`ScreenInstance { name, mode?, focus_index, … }`  
- `show_screen`：**压栈**（modal）  
- `return` / `hide_screen`：**弹栈**；栈空且来自游戏菜单 → 回 `Playing`  
- `quit_to_title`：清空叙事 + 栈，进 `Title` + `title`  
- `start_game`：清空栈，加载 entry，`Playing`  
- `load_slot`：恢复存档，`Playing`，清空栈  

### 2.5 与叙事 VM 的门控

| 状态 | 叙事 VM tick | 叙事 Advance | Screen 输入 |
|------|--------------|--------------|-------------|
| `Title` | 否 | 否 | 是 |
| `Playing`（无 modal） | 是 | 是 | 否（除非脚本 `@ui.show`） |
| modal screen 打开 | **暂停** | **忽略** | 是 |
| 定时 `flow.wait` | 同 Phase 2 | 忽略 Advance | 若同时开菜单：菜单优先；关闭菜单后 wait 继续 |

菜单打开时 **显示挂起时的 Stage 画面作背景**（不撕掉图层）。

### 2.6 Intent

| Intent | 行为 |
|--------|------|
| `OpenMenu` | `Playing` 且无 modal → show `game_menu`；已在菜单 → 视为 `return` 或忽略（钉：**再按 Esc = return 一层**） |
| `Advance` | Playing：同 Phase 2；菜单：= Activate 当前 button |
| `Select(n)` | Choose 时同 Phase 2；菜单：可选直接激活第 n 个可聚焦控件（可选增强） |
| 方向键 / 上下 | 菜单：移动焦点（host 映射为新 Intent 或内部 UI 事件；实现计划钉一种） |
| `ToggleAuto` | 写 prefs.`auto_mode` 并切换引擎 auto |
| Ctrl+S / Ctrl+L | 槽 **0** 存/读（兼容）；不经 screen |

默认键位：

- **Esc** → `OpenMenu`  
- **Enter / Space / Z** → Advance / Activate  
- **↑↓** 或 **W/S** → 焦点移动  
- **A** → ToggleAuto（同现有）  
- **1–9** → Choose 选肢（Playing）

### 2.7 模块职责

| 组件 | Phase 3 职责 |
|------|----------------|
| **script** | 解析 `- screen` → Screen IR；与 scene 分流 |
| **runtime Screen** | 栈、焦点、action、与 UiMode |
| **Engine** | tick 顺序：UI 输入 →（若 Playing）叙事；prefs 作用于 typewriter/audio |
| **std_commands** | `@ui.show` / `@ui.hide`；音频 volume/fade |
| **render** | 活动 screen → 几何 + 文字；焦点高亮 |
| **host_web** | 键位；prefs / 多槽 storage；音频 load hard-fail |
| **moonsightc** | 合并 std screens；资源校验；失败清理 |
| **save** | v3 + 槽 header 元数据 |

---

## 3. 语法子集与标准 screen

### 3.1 顶层声明

```text
- screen "name"
  … body …
```

- 与 `- scene` / `- macro` / `- extern` 并列。  
- 名称全局唯一（跨文件合并冲突 = 错误）。  
- **不**进入叙事 `scenes` 表；进入 **Screen 注册表**。  
- 载体文件：`*.yuki`（`moonsightc` 一并收集）。

### 3.2 缩进与节点

缩进：**2 空格** 表示父子。

| 节点 | 形态 | 语义 |
|------|------|------|
| `vbox` | `vbox:` / `vbox x=… y=…:` | 子节点垂直流式排列 |
| `hbox` | 同上 | 水平流式排列 |
| `fixed` | `fixed x= y= w= h=:` | 固定区域容器 |
| `text` | `text "…"` 或绑定形式 | 显示字符串 |
| `button` | `button "Label" action=…` | 可聚焦；Activate → action |

空行与 `#` 全行注释忽略。

**布局规则：**

- 根 screen 默认覆盖逻辑画布（1920×1080 默认）。  
- `vbox`/`hbox` 内子项流式排布；流式子项的 x/y 忽略（子 `fixed` 除外）。  
- `button`/`text` 行高与现有 UI 字号体系一致（共享常量）。  

**本阶段不做：** `image`、`bar`、拖拽、transform、样式类、主题文件、通用表达式、`if` 节点。

### 3.3 Action 枚举（闭合）

| Action | 语义 |
|--------|------|
| `return` | 弹栈一层 |
| `start_game` | 进 entry，Playing |
| `quit_to_title` | 回 Title |
| `show_screen("name")` | 压栈；可选 `mode=save` \| `mode=load` |
| `hide_screen` / `hide_screen("name")` | 弹栈顶或移除指定 |
| `save_slot(i)` | 写槽 i |
| `load_slot(i)` | 读槽 i |
| `set_pref("key", value)` | 字面量写入 prefs |
| `adjust_pref("key", delta)` | 相对步进 + clamp |
| `noop` | 无操作 |

- **禁止**任意 host 字符串 action。  
- 扩展 = 改引擎枚举 + 文档。  
- 未知 action / 非法字面量 → **编译期**诊断（能静态看见时）。

### 3.4 文本绑定（最小）

| 形式 | 含义 |
|------|------|
| `text "Settings"` | 字面量 |
| `text slot_label(0)` | 空槽 `"Empty"` 或 `"<scene> · <time>"` |
| `text pref("master_volume")` | 当前 prefs 只读展示 |

无通用表达式。

### 3.5 标准 screen

引擎默认提供（仓库 `std_screens/*.yuki` 或等价路径），**项目同名 screen 覆盖 std**。

| Screen | 用途 |
|--------|------|
| `title` | Start / Load / Settings |
| `game_menu` | Continue / Save / Load / Settings / Title |
| `save_load` | 槽 0..N-1；由 `mode` 区分存或读；Back |
| `settings` | 语速、自动、主/BGM/SE 音量（± 步进）；Back |

- 默认 **N = 6**；`moonsight.json` 可选 `"save_slots": N`（建议 clamp **1..20**）。  
- `mode=load`：**空槽不可聚焦**。  
- `mode=save`：可覆盖已有档；**无确认框**。  
- 槽展示：scene 名 + 时间；**无截图**。

### 3.6 叙事侧 host

```text
@ui.show "game_menu"
@ui.hide
@ui.hide "settings"
```

- `OpenMenu` ≡ Playing 且无 modal 时 `show "game_menu"`。  
- 自定义 UI：写 `- screen`，不要用 host 拼控件树。

### 3.7 示例（示意）

```text
- screen "title"
  vbox x=760 y=360:
    text "MoonSight"
    button "Start" action=start_game
    button "Load" action=show_screen("save_load", mode=load)
    button "Settings" action=show_screen("settings")

- screen "game_menu"
  vbox x=760 y=300:
    button "Continue" action=return
    button "Save" action=show_screen("save_load", mode=save)
    button "Load" action=show_screen("save_load", mode=load)
    button "Settings" action=show_screen("settings")
    button "Title" action=quit_to_title
```

---

## 4. 存档、Prefs、音频与 D+B

### 4.1 多槽存档

| 项 | 选择 |
|----|------|
| 键 | `localStorage`：`moonsight/save/{slot}` |
| 体 | Save format **v3** 叙事体 |
| Header | `saved_at`、`scene`、可选 `label`（可内嵌 JSON 顶层字段） |
| 写档时机 | **任意 Playing 可存**（与现 Ctrl+S 一致）；菜单打开时序列化的是 **挂起前游戏快照**，非 UI 状态 |
| 读档 | 恢复 v3 → Playing，清空 screen 栈 |
| 快捷键 | Ctrl+S / Ctrl+L → 槽 **0** |
| 桌面 | 仍 webview storage；OS 目录 **非本阶段** |
| 兼容 | 旧单槽数据视为 slot 0 |

**Screen 栈不进叙事存档。Prefs 不进槽位档。**

### 4.2 Prefs

| 键 | 类型 | 默认 | 作用 |
|----|------|------|------|
| `text_speed` | float | `1.0` | 打字机速率倍率（`chars_per_second = base * text_speed`） |
| `auto_mode` | bool | `false` | 与 ToggleAuto / 设置同步 |
| `master_volume` | float | `1.0` | 0..1 |
| `bgm_volume` | float | `1.0` | 0..1 |
| `se_volume` | float | `1.0` | 0..1 |

- 存储键：`moonsight/prefs`（一整包 JSON）。  
- `adjust_pref` 后 clamp：音量 **0..1**；语速建议 **0.25..3.0**。  
- 变更立即作用于 mixer / typewriter / auto。

### 4.3 BGM volume / fade

```text
@audio.bgm "bgm_soft"
@audio.bgm "bgm_soft" volume=0.8
@audio.bgm "bgm_soft" volume=0.8 fade=1.0
@audio.bgm none          # 停止；可选 fade= 淡出
```

| 规则 | 行为 |
|------|------|
| `volume` | 曲目逻辑音量；输出 = 逻辑 × master × bgm prefs |
| `fade` | 秒；linear；fire-and-forget |
| SE | one-shot；× master × se；**无 se fade** |
| 存档 | 保存 bgm id + 逻辑 volume；fade 中存当前 volume 与 remaining/to（可恢复） |

### 4.4 音频 hard-fail

| 阶段 | 行为 |
|------|------|
| build | 字面量音频 id ⊆ `manifest.audio`；缺失 → **失败** |
| 运行时 fetch | 与贴图一致：失败 → 可读错误，禁止假成功 |
| 动态 id | 构建不保证 |

### 4.5 命名负号

- Lexer：`name=-123` / `name=-1.0` → Named + 负数字面量。  
- layer 与 screen 坐标共用。

### 4.6 其它 D 债

| 项 | Phase 3 |
|----|---------|
| 命名负号 | **做** |
| 音频 hard-fail | **做** |
| 构建失败清理 out_dir | **做**（失败不留半成品或 staging 提交） |
| re-show 缺 kind → character | **文档钉死**，行为保持 |
| host/std 解析重复重构 | **不做**（除非挡 screen） |
| GPU batch 顺序 | **不做** |
| 图/音类型互斥检查 | stretch |

### 4.7 错误

- Screen 编译错误 → check/build 失败，带位置。  
- 菜单 action 非法状态 → **noop + 诊断日志**，不 panic。  
- 未知更高 save version → 拒绝。  
- Prefs 缺字段 → 默认值。

---

## 5. 编译管线、渲染、测试与风险

### 5.1 编译与产物

```
*.yuki
  → Lexer / Parser
      ├─ scene / macro / extern → 叙事 IR → MSB
      └─ screen → Screen AST → Screen IR
  → 合并 screen：项目覆盖同名 std
  → 输出 game.msb（叙事 + screen 段或旁路 blob；**单一加载入口优先**）
  → manifest（含可选 save_slots）
```

**Screen IR（逻辑）：**

```
ScreenDef { name, root: Node }
Node = VBox | HBox | Fixed | Text(TextSrc) | Button(label, Action)
Action = Return | StartGame | QuitToTitle | ShowScreen(name, mode?) | HideScreen(name?)
       | SaveSlot(i) | LoadSlot(i) | SetPref | AdjustPref | Noop
TextSrc = Literal | SlotLabel(i) | Pref(key)
```

二进制布局由实现计划钉死，并带版本字段。

### 5.2 渲染顺序（先画在下）

1. 叙事 layers（kind + z）— 菜单时保留挂起画面  
2. 可选菜单 dim veil  
3. 活动 screen 控件 + 焦点高亮  
4. 叙事对话框/选项（仅 Playing 且无 modal；Title 不显示）  
5. `trans.fade` 全屏 veil  

### 5.3 测试

| 包 | 覆盖 |
|----|------|
| script | screen 解析/lower；负号 named；重名诊断 |
| runtime | 栈与焦点；slot 存读；prefs clamp；StartGame/QuitToTitle；菜单吞叙事 Advance |
| audio | volume×prefs；fade tick |
| render | screen → draw list（无 GPU） |
| moonsightc | 缺音频失败；失败清理；覆盖合并 |
| 手测 | 标题→开始→Esc→存读→音量→回标题；缺 ogg hard-fail |

### 5.4 文档

- 本规格  
- 更新 `host-commands.md`、`moon-yuki-subset.md`、`project-layout.md`、`README`  
- 可选作者短文 `docs/screen-language.md`  
- 实现计划：`docs/superpowers/plans/2026-07-10-moonsight-phase3-screen-ui.md`（writing-plans 产出）

### 5.5 风险与缓解

| 风险 | 缓解 |
|------|------|
| DSL 范围膨胀 | 闭合控件/action；无 if/image |
| 两套 UI（对话 vs screen） | 文档承认；对话框 screen 化后置 |
| 焦点难用 | 标准屏单列 vbox；默认焦点第一 button |
| 存档与菜单交错 | 只存游戏快照；screen 不入档 |
| MSB 兼容 | 版本字段；旧 host 明确失败或忽略策略钉在计划 |
| 工期 | D+B 先行；验收以 DSL 源写的标准屏为准 |

### 5.6 实现切分（供计划）

1. D+B 地基（lexer / audio fail / bgm fade / build cleanup）  
2. Screen IR + 解析/lower + std 合并  
3. Screen 运行时 + Intent + Engine 门控  
4. Prefs + 多槽 header + host 存储  
5. render 绘制 screen  
6. 标准四屏 + demo 冷启动  
7. 文档与全量验证  

---

## 6. 与路线图的关系

| 阶段 | 焦点 |
|------|------|
| Phase 1 | 运行时内核可玩通 |
| Phase 2 | 图层/演出语义 + wait/存档/资源诊断 |
| **Phase 3（本规格）** | **Screen 语言最小集 + 系统 UI 三件套 + D/B 地基** |
| 更后 | 对话框 screen 化、回看、资源打包增强、表达式/image 控件、编辑器、i18n… |

---

## 7. 决策记录

| 决策 | 选择 |
|------|------|
| 主题组合 | A 系统 UX + D 扫债 + 少量 B |
| 系统 UI 实现 | S1：最小 Screen DSL + 运行时（非硬编码终态、非 DOM） |
| 语法载体 | `- screen` 于 `*.yuki` |
| 自定义 UI 路径 | 同子集 screen + 项目覆盖 std |
| 控件子集 | vbox/hbox/fixed/text/button |
| Action | 闭合枚举 |
| 槽位 | 默认 6；可配置 1..20 |
| 确认框 / 截图 / 回看 | 不做 |
| 对话框 | 仍硬编码 |
| Prefs | 独立 localStorage |
| 存档 | v3 + 槽 header；Playing 可存 |
| B 必做 | 负号、音频 hard-fail、BGM volume/fade |
| Stretch | scale/color、对话内联、图音类型检查 |

---

## 8. 开放实现细节（计划阶段钉死）

不影响本规格架构：

- Screen 二进制进 MSB 的具体段布局与魔数  
- 上下键：新 Intent 变体 vs host 侧合成 Select  
- 菜单 dim veil：复用 overlay 字段 vs 独立常量  
- `std_screens` 目录最终路径  
- typewriter `base` chars/sec 数值  
- fade 中 BGM 存档字段精确命名  
- 构建失败清理：删 out_dir vs staging rename  

---

## 9. 批准摘要

经 brainstorming 确认：

- 方案 **S1** + **`.yuki` 内 `- screen`**  
- 核心三件套 + 标准 VN 冷启动 + 全 WebGPU  
- B 必做三项；其余 B 为 stretch  
- §1–§5 设计通过，进入 implementation planning  
