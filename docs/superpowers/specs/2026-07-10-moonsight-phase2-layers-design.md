# MoonSight Phase 2 — 图层与演出语义硬化

**日期：** 2026-07-10  
**状态：** Approved for implementation planning  
**仓库：** `moonsight`  
**前序：** [Phase 1 运行时内核设计](./2026-07-10-moonsight-runtime-design.md)

## 1. 背景与目标

### 1.1 问题

Phase 1 交付了可运行的运行时内核（MoonYuki → IR/MSB、VM、Director、Stage、WebGPU 合成、基础音画与存读档、CLI、demo、最小 Tauri 壳）。若干演出相关能力处于「半成品」状态：

- `LayerKind` 已在 Stage 定义，但 `@layer.show` 一律写入 `Background`
- 图层属性无 duration tween；`layer.move` 立即生效
- `trans.fade` 可用，但与脚本停顿的配合依赖未文档化的习惯
- `flow.wait` 时长语义未真正落地
- 资源缺失易静默失败
- 存档未覆盖进行中动画状态

### 1.2 Phase 2 定位

**一句话：** 在不大改剧院架构的前提下，把图层/转场/等待做成语义正确、可线性 tween、可存档的最小演出层，并允许小幅破坏性 API 调整。

**策略取向：** 先补 Phase 1 欠债，焦点为**图层与演出表现**；完成度定为「语义正确 + 最小动画」；并带上**直接相关的运行时**（wait、转场期输入、动画态存档）。不引入完整时间轴或阻塞式演出 DSL。

### 1.3 实现路线

**路线 A — 图层目标属性 + 引擎 tick（已选定）**

- 每层持有**当前值**与可选的 per-property tween（目标 + 剩余时间）
- `Engine::tick(dt)` 推进 tween / overlay fade / wait
- 动画默认 **fire-and-forget**；需要同步停顿时用 `@flow.wait`
- 不采用阻塞式演出命令（路线 B）或动画队列/时间轴（路线 C）

### 1.4 范围

#### 必做

1. **图层种类接透** — `LayerKind`（`background` / `character` / `effect` / `ui`）经 `@layer.show` 暴露；绘制排序规则明确。
2. **最小属性动画** — `x` / `y` / `opacity` 支持「目标值 + duration」；引擎 linear ease；新 tween 覆盖同属性旧 tween。
3. **转场硬化** — 钉死 `trans.fade` 行为；**不做** `trans.dissolve`。
4. **相关运行时** — `flow.wait` 真实时长；wait 期间输入策略；存档 v3 恢复图层当前值 + 进行中 tween / fade / wait。
5. **资源诊断** — 构建期尽力校验字面量 resource；运行时未知 id / fetch 失败可读错误。
6. **demo + 文档 + 测试** — 更新 demo、host 命令表、语法子集、README；核心包单测全绿。

#### 明确不做

- 可视化编辑器、本地化、成就、Live2D / 3D
- 粒子、后处理、自定义 shader 栈
- 完整时间轴 / 动画队列 / 阻塞式演出 DSL
- 宏系统大修、第二原生 GPU 后端、官方 Yukimi 字节码兼容
- 系统菜单 / 回看 / 多存档 UI
- 调试 HUD（非本阶段必做）
- 非 linear 的 ease 曲线编辑

### 1.5 成功标准

1. demo：背景与角色分层、立绘移入/淡入、`trans.fade` + `@flow.wait`、错误资源有可读失败。
2. 存档 v3：动画或 wait 中途保存 → 重启读档 → 按 `remaining` 继续。
3. v2 存档仍可加载（kind 默认与无 tween，见 §4）。
4. `moon test` 全绿；`builtin_externs` 与 `standard_registry` 对齐。
5. 文档反映 Phase 2 命令与破坏性变更。

---

## 2. 架构

### 2.1 原则（沿用 Phase 1）

1. **Stage 是唯一权威场景状态**；Renderer 只读 snapshot 当前值。
2. **脚本只通过 host 命令改变世界**。
3. **存档 = VM 状态 + Stage 逻辑快照 + 变量**（含逻辑动画状态，不含 GPU 句柄）。
4. **依赖单向**：`script` ↛ `render`；`runtime` 不绑定具体 GPU API。

### 2.2 数据流

```
MoonYuki @layer.* / @trans.* / @flow.wait
        │
        ▼
Director (host handlers) ──写入──► Stage
                                   │  layers[]: kind + current + tweens
                                   │  overlay fade state
                                   │  wait timer
                                   ▼
Engine::tick(dt, intents)
  1. 处理 Intent（受 wait 策略约束）
  2. 推进 wait；到期则从 Yield resume
  3. 推进每层 property tween 与 overlay fade
  4. VM 执行直至 Yield / Choose / 指令预算
  5. 产出 StageView → render draw list
```

### 2.3 组件职责

| 组件 | Phase 2 职责 |
|------|----------------|
| **Stage.Layer** | `kind`；当前 `x,y,opacity,z,resource,visible`；每属性最多一条进行中 tween；可选 `pending_hide` |
| **Stage** | 全局 `overlay_opacity` / `fade_to` / `fade_duration`；wait 状态（计时或「等 Advance」） |
| **Engine** | 用真实 `dt` 推进 tween / wait / fade；`pending_hide` 且 opacity 到位后 remove 层 |
| **Director / std_commands** | 解析 kind、duration；`layer.set`；`flow.wait` 设时并 Yield |
| **render** | 排序：固定 kind 阶，再 `z`；只读当前几何/透明度 |
| **host_web** | 资源 miss / fetch 失败 → 可读错误，禁止静默「成功的空精灵」 |
| **save** | format **v3**（见 §4） |
| **moonsightc** | build 时尽力校验脚本中的字面量 resource ⊆ manifest |

### 2.4 动画语义

| 规则 | 说明 |
|------|------|
| 当前值权威 | 绘制与 snapshot 只使用当前 `x/y/opacity` |
| Fire-and-forget | 启动 tween **不**阻塞 VM |
| 覆盖 | 同层同属性新 tween：取消旧的，`from = 当前值`，`to = 新目标`，`remaining = duration` |
| Ease | Phase 2 固定 **linear** |
| Hide | `duration=0` 或省略：立即 remove；`duration>0`：`pending_hide`，opacity → 0 后 remove |
| 已存在层 + duration | 被指定的 `x` / `y` / `opacity` 各自从**当前值** linear ease 到目标；`z` / `kind` / `resource` 立即应用（不可 tween） |
| 新建层 + duration | `kind` / `resource` / `z` / `x` / `y` 立即设为目标；`opacity` 当前值从 **0** 起，ease 到目标（目标默认 `1.0`）；若 `duration=0` 则 opacity 亦立即为目标 |
| `layer.set` 缺 id | 返回 `Error`（soft-halt），不静默 no-op |

### 2.5 绘制排序

升序绘制（先画在下）：

1. `background`
2. `character`
3. `effect`
4. `ui`（对话框等逻辑层若走 layer 栈时）
5. 全屏 overlay veil（`trans.fade`，非 layer 列表项）

同 kind 内按 `z` 升序；`z` 相同则保持稳定顺序（如插入序 / id 序，实现计划钉一种）。

---

## 3. 作者 API

允许相对 Phase 1 **小幅破坏性**调整；demo 与文档同步改写。

### 3.1 `layer.show`

```yuki
@layer.show "bg" "bg_room" kind=background
@layer.show "y" "char_y" kind=character z=10 x=200 y=0 opacity=1.0
@layer.show "y" "char_y" kind=character opacity=1.0 duration=0.4
```

| 参数 | 说明 |
|------|------|
| `id`, `resource` | 必填（两参数主形式） |
| `kind` | 命名参数；`background` \| `character` \| `effect` \| `ui`（大小写不敏感） |
| **默认 `kind`** | **`character`**（破坏点：Phase 1 全部当作 Background） |
| `z`, `x`, `y`, `opacity` | 目标值 |
| `duration` | 秒；`0` 或省略 = 立即应用到目标 |

单参数旧形式若保留：仅「同 id 刷新/noop」类行为，实现计划决定保留或删除；**背景必须显式 `kind=background`**。

### 3.2 `layer.move`

```yuki
@layer.move "y" 400 0
@layer.move "y" 400 0 duration=0.5
```

目标 `x`,`y`；可选 `duration`。

### 3.3 `layer.hide`

```yuki
@layer.hide "y"
@layer.hide "y" duration=0.3
```

立即移除，或 fade-out 后移除（`pending_hide`）。

### 3.4 `layer.set`（新增）

```yuki
@layer.set "y" opacity=1.0 duration=0.25
@layer.set "y" x=100 y=0 duration=0.2
```

改属性、不换 `resource`；避免 `show` 语义过载。加入 `builtin_externs` 与 `standard_registry`。

### 3.5 `trans.fade`（硬化，非破坏）

保持 Phase 1 参数形态（`from to duration` 及短形式）。文档钉死：

- linear ease，与图层 tween **并行**
- **不**自动 Yield；需等待时脚本写 `@flow.wait <duration>`
- Phase 2 **不**增加 `trans.dissolve`

### 3.6 `flow.wait`（语义补全）

```yuki
@flow.wait 1.0    # Yield；真实时间倒数；到 0 自动 resume
@flow.wait        # 无参：等待一次 Advance 再 resume
```

### 3.7 输入策略

| 状态 | Advance | Select |
|------|---------|--------|
| 对白打字机 | 补全 / 下一句（同 Phase 1） | — |
| `flow.wait` 计时中 | **忽略**（不可跳过） | 忽略 |
| `flow.wait` 无参 | 一次 Advance → resume | — |
| Choose | — | 选肢 |
| 仅有图层 tween / fade 且 VM Running | 不额外拦截 | — |

### 3.8 注册表

标准命令集合在 Phase 1 基础上增加 `layer.set`。完整列表（排序以测试为准）：

```
audio.bgm
audio.se
flow.choice
flow.jump
flow.wait
flow.yield
layer.hide
layer.move
layer.set
layer.show
sys.save_hint
text.begin
text.end
text.type
trans.fade
var.set
```

---

## 4. 存档、资源诊断与错误

### 4.1 存档 format v3

在 v2 上扩展（字段名实现时可微调，语义固定）：

```json
{
  "format_version": 3,
  "module_id": "",
  "scene": "intro",
  "ip": 0,
  "call_stack": [],
  "vars": {},
  "layers": [
    {
      "id": "y",
      "kind": "character",
      "resource": "char_y",
      "z": 10,
      "x": 200,
      "y": 0,
      "opacity": 0.5,
      "tweens": [
        { "prop": "opacity", "to": 1.0, "remaining": 0.2 }
      ],
      "pending_hide": false
    }
  ],
  "overlay_opacity": 0.3,
  "fade_to": 0.0,
  "fade_remaining": 0.5,
  "wait": { "$tag": "Timed", "remaining": 0.8 },
  "auto": false
}
```

| 策略 | 行为 |
|------|------|
| 写档 | 始终写 v3 |
| 读 v3 | 恢复 current + tweens（`from = current`，向 `to` 走 `remaining`）+ fade（`overlay_opacity` / `fade_to` / `fade_remaining`）+ wait |
| 读 v2 | **接受**：旧图层字段加载；`kind` 默认 `character`；无 tween；若仅有旧 `fade_duration` 字段则按 Phase 1 语义推断为 remaining 或 snap（实现计划与现有 load 对齐，优先可玩恢复） |
| 未知高版本 | 拒绝，明确错误 |
| tween 序列化 | 存 `prop` + `to` + `remaining`；不存 `from` |
| fade 序列化 | 存当前 `overlay_opacity`、`fade_to`、到达 `fade_to` 的 **`fade_remaining` 秒**（不用「全程原始 duration」） |

### 4.2 资源诊断

| 阶段 | 行为 |
|------|------|
| `moonsightc build` | 尽力收集脚本中的**字面量** resource 字符串，校验 ⊆ manifest（贴图/音频映射）；缺失 → **构建失败** |
| 运行时 fetch 失败 | host 可读错误；不当作加载成功 |
| 运行时未知 resource id | Director `Error("… unknown resource …")` soft-halt |

动态拼接的 resource id 不做构建期保证（YAGNI）；运行时仍校验。

### 4.3 错误处理

- 非法 host 参数：`Error(msg)` soft-halt（与 Phase 1 一致）
- 动画中途允许 save/load
- 不新增 panic 路径作为正常错误通道

---

## 5. 测试与验收

### 5.1 自动化测试

| 包 | 覆盖 |
|----|------|
| `runtime` | 固定 `dt` 的 tween 步进；覆盖旧 tween；`pending_hide` 移除；`flow.wait` 计时 resume；wait 中吞 Intent；fade 与 layer tween 并行 |
| `runtime` save | v3 round-trip；v2 → 加载兼容 |
| `std_commands` | `layer.show` kind；`layer.set`；`move`/`hide` + duration；错误信息 |
| `script` | `layer.set` 在 externs；与 registry 名对齐 |
| `render` | kind 阶再 `z` 的排序（对 StageView / draw 输入的纯逻辑断言） |
| `cmd/moonsightc` 或集成 | 缺资源构建失败的最小 testdata |

### 5.2 手测 / demo

- 浏览器：分层、移入/淡入、`trans.fade` + `@flow.wait`、中途 Ctrl+S / Ctrl+L
- 更新 `demo/game` 脚本以使用新 API

### 5.3 文档交付

- 本规格
- 更新 `docs/host-commands.md`、`docs/moon-yuki-subset.md`、`README.mbt.md`（Phase 2 范围）
- 实现计划：另文 `docs/superpowers/plans/…`（本规格批准后的 writing-plans 产出）

### 5.4 实现触点（供计划分解）

`runtime` · `std_commands` · `script`（externs）· `render`（sort）· `cmd/moonsightc`（资源校验）· `host_web`（加载错误）· `demo/game` · `docs/*`

---

## 6. 与 Phase 1 / 后期路线图的关系

| 阶段 | 焦点 |
|------|------|
| Phase 1 | 运行时内核可玩通 |
| **Phase 2（本规格）** | 图层/演出语义 + 相关 wait/存档/资源诊断 |
| 更后（仍非本规格） | 资源打包管线增强、编辑器、本地化、成就/系统菜单、高级渲染、native GPU |

Phase 1 设计文档 §10 中的「资源与打包管线」仅部分触及（字面量资源校验 + 运行时诊断）；完整多分辨率/哈希缓存/压缩包仍属后续阶段。

---

## 7. 决策记录

| 决策 | 选择 |
|------|------|
| Phase 2 主题 | 先补 Phase 1 欠债，主攻图层与演出 |
| 完成度 | 语义正确 + 最小动画 |
| 附带运行时 | wait 时长、输入策略、动画态存档 |
| 架构 | 目标属性 + Engine tick（路线 A） |
| API 兼容 | 允许小幅破坏；默认 `kind=character` |
| 新命令 | 包含 `layer.set` |
| Ease | linear only |
| 同步模型 | fire-and-forget + `@flow.wait` |
| Wait 中 Advance | 忽略（不可跳过计时） |
| Dissolve | 不做 |
| 存档 | v3；兼容读 v2 |
| 构建期资源校验 | 做（字面量尽力） |

---

## 8. 开放实现细节（计划阶段钉死）

不影响本规格架构选择：

- `z` 并列时的稳定排序键（插入序 vs id 序）
- wait 状态在 Engine 与 Stage 之间的具体字段归属
- `moonsightc` 资源收集是走 AST 扫描还是 lower 后常量
- 单参数 `layer.show` 是否删除（若保留：行为必须文档化）
- host 资源错误呈现：console 必做；DOM 文案 vs canvas 内文案二选一即可
- v2 `fade_duration` → v3 `fade_remaining` 的精确换算（与现有 engine fade 步进公式对齐）
