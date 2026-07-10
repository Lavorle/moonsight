# MoonSight Q1 — 可认真玩（Playable Core）

**日期：** 2026-07-11  
**状态：** Draft for implementation planning  
**仓库：** `moonsight`  
**总图：** [12–18 个月产品路线图](./2026-07-11-moonsight-roadmap-design.md)  
**门槛目标：** **0.5 可认真内测**  
**前序基线：** Phase 1–4（运行时内核、图层演出、系统 UI、MoonBit UI 内核）

---

## 1. 背景与目标

### 1.1 问题

Phase 4 后引擎已能跑通 title → 叙事 → Esc 菜单 → 存读/设置，但仍缺现代 VN **播放器标配**，内测体验「残」：

1. **无回看 (backlog)** — 错过对白只能重开或读档。  
2. **无跳过 (skip)** — `SkipTyping` 仅补全当前打字机，无法连跳已读/可跳行；hold 跳过未接入。  
3. **无确认框** — 覆盖已占用存档槽、从游戏回标题均为一键生效。  
4. **音量 prefs 未进 mixer** — `Prefs.master/bgm/se_volume` 可改 UI，但 `audio/mixer.mbt` 的 `output_*_volume` 仍是 `logical * 1.0 * 1.0`。  
5. **设置 UX 粗** — 仅有 ± 按钮；本季以 **Slider 最小可用**（或强化步进）改善。  
6. **槽位标签弱** — `saved_at` 已在存档 JSON，UI 标签几乎不展示。

### 1.2 一句话

交付 **回看 · 跳过 · 危险操作确认 · prefs→mixer 真接线 · 设置控件升级 · 槽位元数据展示**，并写清 **skip / wait / fade 门控语义** 与更可读诊断，使 demo 达到路线图 **0.5**。

### 1.3 范围

#### 必做

| # | 能力 | 验收要点 |
|---|------|----------|
| 1 | **Backlog 回看** | 完成过的对白进入环形缓冲；菜单或快捷键打开只读列表；关闭后回到原状态 |
| 2 | **Skip 跳过** | 按住 Skip 时：补全打字机并快速推进 Yield；**不**跳过 `wait_remaining` / 进行中 fade 门控（与现网 Advance 一致） |
| 3 | **Confirm** | 覆盖占用槽存档、游戏菜单 → Title 需确认；Yes/No 可键盘操作 |
| 4 | **Prefs → mixer** | 改 master/bgm/se 立即影响输出音量；读档/加载 prefs 后一致 |
| 5 | **Settings 控件** | `UiNode::Slider`（焦点 ± / 可选点击粗调）或等价；默认 settings 使用之 |
| 6 | **槽位元数据** | `slot_label` / 绑定展示 `saved_at`（有则）+ 占用态 |
| 7 | **语义与诊断文档** | `host-commands` / 新节或 `docs/play-input.md`：Intent、skip/wait；编译错误信息抽样改进 |

#### 明确不做（Q1 非目标）

- ScrollView 虚拟滚动（backlog 用固定容量 + 简单列表/分页即可；完整滚动进 Q3）  
- 槽位截图缩略图（Q3）  
- `trans.dissolve` / scale / 时间轴（Q2）  
- Rollback 到历史行（Q5 候选）  
- 桌面原生存档路径、项目模板（Q4）  
- 语音轨、i18n、编辑器、Live2D  
- 开放 host-string UI action；恢复 `- screen`  
- 将 backlog **全文写入存档**（见 §3.1：默认会话级）

### 1.4 成功标准

1. 冷启动 title → 玩 demo → 回看至少 N 条已显示对白。  
2. 按住 Skip（默认 **Ctrl**）可快速越过已完成打字机的 Yield 行；timed `@flow.wait` 期间仍不可 Advance/Skip。  
3. 写入已占用 slot 弹出 confirm；选 No 不覆盖；选 Yes 覆盖。  
4. Title 确认：game_menu → Title → confirm → Yes 才 `quit_to_title`。  
5. settings 调 master/bgm/se 后，JS/逻辑 mixer 输出增益变化（单测 + 可选手动）。  
6. `moon test` / `moon check` 全绿；文档与行为一致。  
7. 无占位假实现。

---

## 2. 架构与原则

### 2.1 原则（继承 Phase 4）

1. **Stage 叙事权威**；backlog 是旁路日志，不改 VM IP。  
2. **UI 只经 Capabilities**；confirm / backlog / skip 标志不引入开放字符串 action。  
3. **输入门控：** modal 非空 → 只处理栈顶；Playing 才跑叙事 skip。  
4. **存档不变格式优先：** Q1 **不** bump save v3 必选字段；backlog 默认不进档。  
5. **mixer 输出 = 逻辑音量 × prefs 增益**；脚本 `@audio.bgm volume=` 仍是逻辑音量。

### 2.2 逻辑关系

```
Input (host)
  → Intent (+ hold Skip flag)
       │
       ▼
Engine::tick
  ├─ UI active? → tick_ui (confirm / backlog modal / settings)
  ├─ OpenMenu / OpenBacklog
  ├─ gate: wait_remaining > 0 → drop Advance/SkipTyping/Select
  ├─ apply skip burst (complete text → resume Yield)
  ├─ VM / tweens / typewriter
  └─ append backlog when dialogue line completes
       │
       ▼
audio.Mixer  ←── Engine.sync_mixer_prefs(prefs)
std_ui       ←── backlog / confirm / slider trees
```

### 2.3 包边界

| 包 | Q1 职责 |
|----|---------|
| `runtime` | BacklogStore；ConfirmState；Intent 扩展；skip 行为；Capabilities 扩展；slot_label；prefs→mixer 同步钩子 |
| `audio` | `output_*_volume` 乘 prefs；Mixer 持有或接收 prefs gains |
| `std_ui` | backlog modal、confirm modal、settings Slider、game_menu History / 危险操作改走 confirm |
| `host_web` / `js_glue` | Ctrl→Skip hold；可选 H→backlog；prefs 变更后无需改协议若 mixer 侧已乘 |
| `script` / `moonsightc` | 诊断文案改进（抽样）；无新语法必做 |
| `docs` | 输入与 skip/wait 语义；更新 out-of-scope |

---

## 3. 功能设计

### 3.1 Backlog（回看）

#### 数据

```text
BacklogEntry {
  speaker : String?    // 姓名牌；旁白为空
  text    : String     // 该行 full_text（打字机完成后写入）
}

BacklogStore {
  entries : ring buffer, capacity = 100 (constant, documented)
}
```

- **写入时机：** 当 `stage.text` 从「有文本且 `complete=false`」变为 **`complete=true`**（`complete_text` 或 typewriter 跑满），**或** 在清除/替换 `stage.text` 前若上一行已 complete，确保只记录一次。推荐：在 `Stage::complete_text` 与 typewriter 首次置 `complete=true` 时 `engine.backlog.push(...)`。  
- **不记录：** 选项标签本身（可选后续）；系统 modal 文案。  
- **生命周期：** **会话级**。`start_game` / `quit_to_title` / `load_slot` **清空** backlog（避免串档剧透）。不进 `SaveGame`。  
- **容量：** 100；满则丢最旧。

#### UI

- 新 modal 名：`"backlog"`（`std_ui` 注册）。  
- 展示：最近条目自下而上或自上而下列表（固定最多显示 ~12 行 + 「…更早 N 条」计数）；**Q1 不做自由滚动条**（Q3 ScrollView）。  
- 入口：  
  - `game_menu` 增加 **History** → `show_modal("backlog")`  
  - Intent **`OpenBacklog`**（host 默认 **H** 键，Playing 且无 modal 时打开；modal 时 H 可忽略或关闭——**Esc/`return_modal` 关闭**）  
- 只读：无按钮改剧情；**Close** → `return_modal`。

#### Capabilities

```text
fn open_backlog(Self) -> Unit   // show_modal("backlog") 的语义封装可选；或直接 show_modal
```

可不加新方法，仅 `show_modal("backlog")`；若要类型表达，可加 `open_backlog()` 默认实现为 show。

### 3.2 Skip（跳过）

#### Intent / 输入

| 概念 | 定义 |
|------|------|
| 现有 `SkipTyping` | 单次：与 Advance 同路径补全打字机或推进 Yield（保持兼容） |
| 新增 **`skip_held` 状态** | Engine 或 per-tick 参数：`tick(intent, dt, skip_held~)` **或** 新 Intent 变体 |

**推荐：** 扩展 tick 签名：

```text
Engine::tick(self, intent, dt?, skip_held~ : Bool = false)
```

Host：Ctrl **按下期间** 每帧 `skip_held=true`；松开 false。不引入「切换式 skip 模式」prefs（YAGNI；需要时 Q2+）。

#### 语义（必须写入文档）

| 状态 | `skip_held` 行为 |
|------|------------------|
| 打字机未完成 | 等价 `complete_text()`（同 SkipTyping/Advance 第一下） |
| Yield 且文本已完成 | 推进 VM（`wait = Running`），同一帧可再 `run_until_wait`；**每帧最多推进有限步**（见下） |
| `wait_remaining > 0` | **忽略** Advance / SkipTyping / skip_held 推进（已有 gate 保留） |
| 进行中 overlay fade | **不**强制 snap；脚本若未 wait 可能边 fade 边推进——与今日 Advance 一致，不在 Q1 改 fade 门控 |
| Choose 等待选项 | skip_held **不**自动选选项（避免误选）；仅可补全若存在相关文本 |
| UI modal 打开 | skip_held 不穿透叙事 |

**每帧推进上限：** `skip_held` 时在 `run_until_wait` 循环中最多完成 **K=8** 次「Yield 恢复→再跑到 wait」或等价，防止一帧脚本空转打满 CPU。K 为命名常量 `skip_burst_max`。

**与 auto：** auto 仅在 `None_` 时注入 Advance；`skip_held` 优先于 auto 的慢速。

#### Prefs（可选最小）

Q1 **不**强制 `skip_unread` 开关；默认行为 = **跳过当前可见叙事 Yield（含未读）**，因 demo 短且无「已读标记」系统。若实现成本低，可预留 `prefs.skip_unread_only : Bool = false` 但不暴露 UI。

### 3.3 Confirm（确认框）

#### 模型

```text
enum ConfirmKind {
  OverwriteSave(slot : Int)
  QuitToTitle
}

// 挂在 Engine 或 UiRuntime：
pending_confirm : ConfirmKind?
```

**不要**用自由字符串 message 作为唯一真相；message 由 `std_ui` 按 kind 绑定字面量。

#### 流程

1. **Save 占用槽：** `save_slot(i)` 若 `slot_occupied(i)` → 设 `pending_confirm = OverwriteSave(i)` 并 `show_modal("confirm")`，**不立即写**。  
2. Confirm Yes → 执行真正写入 / `quit_to_title`，清 pending，pop confirm。  
3. Confirm No / Esc → 清 pending，pop confirm，**不**执行。  
4. **Title：** game_menu 的 Title 按钮改为请求 confirm，而非直接 `quit_to_title`。  
5. 空槽 Save、Load、Continue 等**不**经 confirm。

#### Capabilities 扩展

```text
fn request_save_slot(Self, Int) -> Unit   // 可替换现 save_slot 按钮绑定
fn request_quit_to_title(Self) -> Unit
fn confirm_yes(Self) -> Unit
fn confirm_no(Self) -> Unit
```

或保留 `save_slot` 内部做占用检查（**推荐：Engine.save_slot 内建检查**，按钮仍调 `save_slot`，减少 std_ui 分叉）。`quit_to_title` 从菜单改为 `request_quit_to_title`；Capabilities 增加 `confirm_yes` / `confirm_no`。

**兼容：** 测试与脚本直接调 `save_slot` 时空槽仍立即存；占用则进 confirm（单测覆盖）。

#### UI

- modal `"confirm"`：标题/正文 Text（Literal 或新 `TextBindSrc::ConfirmMessage`）、Yes / No 按钮。  
- 焦点默认 **No**（防误触）或 Yes——**默认 No**。

### 3.4 Prefs → Mixer

#### 公式

```text
output_bgm = clamp01(logical_bgm_volume * prefs.master_volume * prefs.bgm_volume)
output_se  = clamp01(logical_se_volume  * prefs.master_volume * prefs.se_volume)
```

- `Mixer` 增加可变 `pref_master` / `pref_bgm` / `pref_se`（默认 1.0），或 `apply_prefs(Prefs)`。  
- `output_bgm_volume` / `output_se_volume` 使用上述乘积。  
- 任一 prefs 音量变更、`set_prefs_json`、engine 构造后：调用 `mixer.apply_prefs` 并 **若 BGM 在播则 `backend` 更新音量**（`SetBgmVolume` 事件或等价）。  
- **逻辑** `bgm_volume`（脚本）与 **prefs** 分离；存档仍只存逻辑侧。

#### 测试

- 设 `master_volume=0.5`, `bgm_volume=0.5`, logical=1.0 → 输出 0.25。  
- 改 prefs 后 `global_mixer` 反映新输出。

### 3.5 Settings Slider

#### `UiNode::Slider`

```text
Slider(
  key~ : String,          // prefs key: text_speed | master_volume | bgm_volume | se_volume
  x~, y~, w~, h~,
  visible~ : VisiblePred,
)
```

- **焦点：** 在 focusables 中与 Button 并列；`MenuUp/Down` 移动焦点；**MenuLeft/Right** 或现有 **未使用** 键：  
  - 扩展 Intent：`MenuLeft` / `MenuRight` **或** 在 focused Slider 上用 `adjust_pref(key, ±step)`。  
- **步骤：** volume 0.05 或 0.1；text_speed 0.25（与现 ± 一致可并存）。  
- **绘制：** 轨道矩形 + 填充比例 + 可选数值 Text（Pref bind）。  
- settings modal：**用 Slider 替换** 三路 volume 的双按钮行；text_speed 亦可 Slider。auto_mode 仍用按钮。

Q1 不做鼠标拖拽精细 scrub（可做点击轨道跳百分比若 hit-test 已够）；键盘可调即验收通过。

### 3.6 槽位元数据

- `slot_label`：空 → `"Slot N (empty)"`；占用 → `"Slot N · {saved_at}"`，`saved_at` 空则 `"Slot N · saved"`。  
- `TextBindSrc::SlotLabel` 已走 `slot_label` 能力路径时，确保 bind 用 **Capabilities.slot_label** 或 engine 同步的 label 数组，而非仅 occupied 布尔。  
- 今日 `TextBindSrc::SlotLabel` 在 `ui_types` 内只显示 empty/occupied 简文——改为使用 engine 提供的 labels 数组：

```text
UiBindCtx.slot_labels : Array[String]
```

`sync_ui_bind` 填入每槽 `slot_label(i)`。

### 3.7 诊断与文档（辅北极星，小步）

- 文档新增或扩展：`docs/play-input.md`（Intent 表、skip_held、wait 门控、快捷键默认）。  
- `host-commands.md`：交叉链接；声明 wait 不可 skip。  
- `moonsightc` / parser：至少改进 2–3 条高频错误文案（如 `- screen` 已有迁移；可加强 unknown host、duplicate scene）。  
- **不**做完整源映射 IDE 协议。

---

## 4. 输入默认映射（Web host）

| 键 | Intent / 标志 |
|----|----------------|
| Enter / Space / Z / Click（叙事） | Advance |
| Ctrl（按住） | `skip_held=true` |
| A | ToggleAuto |
| Esc | OpenMenu（现有） |
| H | OpenBacklog（Playing） |
| ↑↓ / W S | MenuUp / MenuDown |
| ←→ | MenuLeft / MenuRight（Slider） |
| 1–9 | Select |
| Ctrl+S / Ctrl+L | 快存快读 slot 0（现有则保留） |

---

## 5. 实现切片（高层次，供 plan）

1. **audio：** prefs 乘子 + apply + 测试  
2. **runtime：** BacklogStore + 写入点 + 清空策略 + 测试  
3. **runtime：** `skip_held` tick 语义 + 测试（wait 不可跳、burst 上限）  
4. **runtime：** ConfirmState + save_slot/title 改道 + Capabilities + 测试  
5. **runtime UI：** Slider 节点 + focus/left-right + paint ops  
6. **std_ui：** backlog / confirm / settings / game_menu 接线  
7. **host：** 键位；`tick` 传 skip_held  
8. **slot labels** + bind  
9. **docs** + demo 轻量提示（可选对白提到 H / Ctrl）  
10. **全量** `moon test` / check / build demo  

---

## 6. 风险与缓解

| 风险 | 缓解 |
|------|------|
| skip 一帧推进过多导致卡顿/逻辑错乱 | `skip_burst_max`；单测 |
| confirm 与 modal 栈深度混乱 | confirm 永远 push 在栈顶；Yes/No 只 pop 一层 |
| backlog 写入重复或丢行 | 单一写入点 + complete 边沿测试 |
| Slider 焦点与按钮列表不同步 | 复用 focusables 收集；单测 settings 树 |
| prefs 改音量无声 | apply 后强制 `SetBgmVolume` 事件 |

---

## 7. 决策记录

| 决策 | 选择 |
|------|------|
| 季度 | Q1 可认真玩 → 门槛 0.5 |
| Backlog 持久化 | 会话级环形 100；进出档/开局清空；不进 SaveGame |
| Skip | Ctrl hold + `skip_held`；不跳 wait_remaining；不自动选 choice |
| Confirm | OverwriteSave + QuitToTitle；默认焦点 No |
| 音量 | mixer 输出乘 master×channel |
| Slider | 新 UiNode；键盘为主 |
| ScrollView / 截图 / dissolve | 非目标 |

---

## 8. 后续

1. 用户审阅本 design。  
2. 通过后写 `docs/superpowers/plans/2026-07-11-moonsight-q1-playable.md`（writing-plans）。  
3. SDD 按任务实现；达 0.5 后更新 README Scope，再开 Q2 design。
