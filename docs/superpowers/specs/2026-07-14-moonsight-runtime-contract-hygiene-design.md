# MoonSight — Runtime Contract Hygiene Design

**日期：** 2026-07-14  
**状态：** Approved for implementation planning  
**仓库：** `moonsight`  
**基线：** 当前 `main`（Formal 1.0 产品面已合入）  
**路径选择：** 方案 A — 单一 Hygiene 规格，五条运行时契约有序收口  
**目标版本：** Hygiene 横切增量（不升主版本号；不宣称 Formal 1.0 外部矩阵 PASS）

**前序与对照：**

| 文档 | 关系 |
|------|------|
| [综合改进审计](../../../.omx/specs/moonsight-comprehensive-improvement-audit-20260712.md) | 源：X4 菜单时钟、X2 atlas、X3 typewriter、X6 budget、X5 音频 |
| [play-input.md](../../play-input.md) | H1 文档权威（菜单不暂停演出） |
| [host-commands.md](../../host-commands.md) | flow.wait / modal 与 host 命令语义 |
| Formal 1.0 / 1.1 native designs | **只读**；本设计不改其证据矩阵与 native 栈合同 |

**规划批准 ≠ 开始实现。** 实现须另开 writing-plans → SDD；默认在 `main` 或自 `main` 拉出的 hygiene 分支，**不以** `.worktrees/1.1-native-desktop` 为基线。

---

## 1. 背景与目标

### 1.1 问题

Formal 1.0 已收口审计中多数 **NOW** 项（存档身份、错误可见、生产 boot 失败闭合、CI 主门禁、动态存档槽等）。`main` 上仍残留 **运行时契约漂移**：文档、Engine 时钟、字图边界、打字机 Unicode、VM 帧预算与音频会话生命周期不一致。这些不是新功能，而是「代码 ↔ 文档 ↔ 测试」对齐，适合作为 **Hygiene** 横切规格一次做完。

### 1.2 一句话目标

在 **main** 上收口五条运行时契约，使 **文档、MoonBit 权威行为、Web Host 消费路径** 一致，并有可回归的自动化证据；**不**宣称 Formal 1.0 外部矩阵 PASS，**不**合并 1.1 native。

### 1.3 产品原则

1. **文档与代码同真** — 冲突时以本设计锁定的策略为准，并同步改文档或代码，禁止长期分叉。  
2. **引擎权威在 MoonBit** — Host 不发明演出时钟；render 只读绘制数据。  
3. **不拿回归换进度** — `moon test`、Web 默认 build、生产 content fail-closed 不回退。  
4. **诚实证据** — 无假完成、无空测、不改写 Formal 1.0 W1/D1/C1 语义。  
5. **兼容优先** — 存档 format 不 bump；字段语义收紧为「合法边界」，非法值 clamp 而非无故拒读。

### 1.4 已确认决策（brainstorming）

| 决策 | 选择 |
|------|------|
| 主线 | Hygiene / 运行时契约对齐 |
| 组织 | 方案 A：单一 design + 有序任务 |
| H1 菜单时钟 | **文档为准**：modal 不暂停 wait / tween / fade / dissolve / typewriter |
| H2 音频 | 回标题 / 新开局 / boot_title：**强制静默并清空逻辑轨**；prefs gains 保留 |
| H3 打字机 | **Grapheme cluster** 步进与可见前缀 |
| H4 atlas | **可增长**（正方形翻倍至 MAX 4096，整表 repack） |
| H5 VM budget | **可观测 + 下帧重试**；不硬 halt |
| 基线 | `main`，非 1.1 worktree |

### 1.5 范围

#### 必做（H1–H5）

| ID | 契约 | 摘要 |
|----|------|------|
| **H1** | 菜单 vs 演出时钟 | Playing + modal：仍推进 wait / transitions / layer tweens / typewriter；叙事 Advance / skip_burst 禁止；Title 保持 UI-only |
| **H2** | 音频会话 | `quit_to_title` / `start_game` / `boot_title` → `Mixer::clear_playback_session`；load 仍走 `apply_logic` |
| **H3** | Grapheme 打字机 | `visible_chars` = grapheme 边界上的 UTF-16 端点；reveal 按 grapheme；共享边界 helper + Host fixture parity |
| **H4** | Glyph atlas 增长 | 溢出时翻倍增长并 generation++、整表失效重传；超 MAX 的单 cell → terminal 0×0 非 pending |
| **H5** | VM instruction budget | 耗尽不 halt；计数与 last-frame 标志；下帧续跑；默认玩家 UI 不弹窗 |

#### 明确不做

- Formal 1.0 W1/D1/C1、benchmark 外部证据、tag / 公开 Release  
- 1.1 native 合并、`host_core` 回灌、native FreeType 路径实现（合并时 follow-up）  
- 新演出（粒子、Live2D、新 trans）、HarfBuzz shaping  
- draw-pack bulk transfer 大改  
- 供应链 pin 全量、docs PostCSS 告警全清（属另一 Hygiene 簇）  
- multi-page atlas、LRU 驱逐、默认 budget 数值变更、编译期预算分析  

### 1.6 成功标准

1. H1–H5 各有自动化测试锚点通过。  
2. `play-input.md` / `host-commands.md` 及相关说明与代码一致（含 typewriter 在 modal 下继续）。  
3. Formal 1.0 证据矩阵与 1.1 native 合同语义未被本轮改写。  
4. 无因本轮引入的 P0 播放阻断；全量回归门禁绿。

---

## 2. 架构

### 2.1 分层与所有权

```
docs (play-input / host-commands / …)
        ▲  合同文字与本 design 对齐
        │
runtime (Engine tick / Stage typewriter / VM budget / grapheme)
        │  H1 H2 H3 H5 权威
render (GlyphAtlas grow + layout 共用前缀边界)
        │  H3 绘制前缀 + H4 几何
audio (Mixer session clear)
        │  H2 逻辑轨
apps/host-web (atlas 纹理重建 / 可选 budget 诊断透出)
        │  H4 消费；H5 可选 export
```

原则不变：**Stage/Engine 叙事权威**；UI 经 Capabilities；Host 不发明时钟；render 只读绘制数据。

### 2.2 建议实现顺序

1. **H1** — `Engine::tick` 结构（纯 runtime，高可见）  
2. **H2** — `clear_playback_session` + title/start 入口  
3. **H3** — grapheme 核心 + typewriter + 存档 clamp + Host fixture  
4. **H4** — atlas grow + wasm export + Host 重建  
5. **H5** — budget 诊断  
6. 文档对齐 + 全量回归  

每条独立可测；前条不依赖后条。

---

## 3. H1 — 菜单与演出时钟

### 3.1 问题

`Engine::tick` 在 `ui_active`（`stack_depth > 0` **或** `Title`）时 early-return，只 `tick_ui` + mixer，不调用 `tick_wait` / `tick_transitions` / `tick_layer_tweens` / `tick_typewriter` / wait 归零后的 `run_until_wait`。文档则声明 modal 下 countdown 与 fade/dissolve 继续。

### 3.2 目标行为

| 状态 | UI | wait | fade/dissolve | layer tween | typewriter | VM `run_until_wait` | 叙事 Advance / skip_burst |
|------|----|------|---------------|-------------|------------|---------------------|---------------------------|
| **Playing + 空栈** | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓（受 wait 门控） |
| **Playing + modal 栈** | ✓ 仅栈顶 | ✓ | ✓ | ✓ | ✓ | ✓（wait 归零可续跑） | **禁止** |
| **Title** | ✓ | 不要求 | 不要求 | 不要求 | 不要求 | 不要求 | 无叙事 |

### 3.3 `tick` 语义结构

```
if Rollback → rollback_latest; return

if Title:
  tick_ui; mixer; drain_ui_ops; return

if modal stack non-empty:
  tick_ui(intent)          // 菜单输入优先
  // 不 apply 叙事 Advance / Select / SkipTyping / skip_burst
  tick_wait(dt)
  if vm.wait is Running: run_until_wait(...)
  relocalize_new_presentation if needed
  enforce_completed_effects
  drain_ui_ops
  tick_transitions(dt)
  stage.tick_layer_tweens(dt)
  tick_typewriter(dt)
  mixer.tick(dt)
  return

// Playing 空栈：现有 full path（含 skip_burst 与 wait 门控）
```

附加规则：

1. **OpenMenu / OpenBacklog 同帧**：落入 modal 分支前/后不得漏 presentation ticks。  
2. **wait 在菜单下归零**：允许 VM 自动续跑到下一 Yield/Choose；新对白可在菜单下 typewriter；玩家仍须关菜单后才能叙事 Advance。  
3. **Choose**：不自动选选项。  
4. **effect barrier**：modal 路径仍 `enforce_completed_effects`。

### 3.4 文档

- 保留「菜单不暂停演出」；**明确 typewriter 在 modal 下继续**。  
- 删除/修正「modal 冻结 narrative presentation」类代码注释。

### 3.5 测试锚点

1. `@flow.wait` 中开菜单 → dt 累加后 wait 归零。  
2. fade/dissolve 中开菜单 → 时钟不冻结。  
3. layer tween 中开菜单 → 插值继续。  
4. typewriter 中开菜单 → `visible_chars` 继续增加。  
5. modal 下 skip_held / 误传 Advance 不推进叙事。  
6. Title 路径稳定。

### 3.6 风险

| 风险 | 缓解 |
|------|------|
| wait 结束触发 `@ui.show` / 跳转 | 允许；测「wait 结束开第二 modal」不崩溃 |
| 作者依赖「开菜单暂停演出」的 bug | changelog 记行为修正 |
| 与 confirm / skip 纠缠 | intent 表单测固定 |

---

## 4. H2 — 音频会话生命周期

### 4.1 问题

`start_game` / `quit_to_title` / `boot_title` 重建 Stage/Vm 但不复位 process-global `Mixer`，旧 BGM 可残留。

### 4.2 目标行为

| 入口 | 音频动作 |
|------|----------|
| `quit_to_title` | 立即停 BGM、取消 fade、清空逻辑 SE；**保留** `pref_*` |
| `start_game` | 同上 |
| `boot_title` | 同上 |
| 存档 `load` 成功 | **不**替代 `apply_logic`；按存档恢复 BGM |
| Host 进程退出 | 既有 teardown；本轮不新增桌面专用协议 |

### 4.3 API

```text
Mixer::clear_playback_session(self) -> Unit
```

语义：

1. `clear_fade()`  
2. `stop_bgm()`  
3. 逻辑 `se = None`，`se_volume` 复位默认；`se_seq` 单调性策略在实现时固定并测（允许 +1 一次表示会话边界）  
4. **不**改 `pref_*`  
5. **不** `reset_global_mixer()` / 不换 backend  

`AudioBackend` **本轮不强制** `stop_se`（SE one-shot）；BGM 必须硬停。

Engine 三处在换 stage 时调用 `clear_playback_session`，并 `sync_mixer_prefs()`。

### 4.4 测试锚点

1. `play_bgm` → `quit_to_title` → `bgm is None` + backend `stop_bgm`。  
2. `play_bgm` → `start_game` → 同上。  
3. pref gains 在 clear 后不变。  
4. load 含 BGM 存档仍恢复。  
5. 进行中 fade-out-stop → quit 立即静默。

### 4.5 风险

| 风险 | 缓解 |
|------|------|
| Title 想播菜单 BGM | 非目标；进 Title 后需再播 |
| load 顺序 | 测 clear 与 `apply_logic` 不打架 |
| 全局 mixer 测例污染 | 测后 `reset_global_mixer` |

---

## 5. H3 — Grapheme 打字机

### 5.1 问题

`reveal_chars` / `visible_text_prefix` 按字符串下标切片，可切开组合字符或 ZWJ emoji。Host locale 热切换已有 `Intl.Segmenter`；运行时打字机未对齐。

### 5.2 字段合同

| 字段 | 语义（本轮后） |
|------|----------------|
| `TextBlock.visible_chars` | **始终为 grapheme 边界上的 UTF-16 端点**（`0 … full_text.length()`） |
| `complete` | 全文可见或显式 complete |
| 存档 JSON | **不 bump format**；读入后 **向下 clamp** 到合法 grapheme 边界 |

速率：`tick_typewriter` 按 **grapheme/秒**（沿用 `40 * text_speed * dt` 数值，单位从码元改为 grapheme）。

### 5.3 算法

- MoonBit（`runtime/grapheme.mbt` 或等价）实现 **Extended Grapheme Cluster 实用子集**（UAX #29）：组合标记、Regional Indicator 成对、ZWJ emoji、CJK 单字 grapheme。  
- **不做** HarfBuzz。Hangul jamo 复杂序列可 best-effort，文档诚实。  
- Host `Intl.Segmenter`：共享 fixture parity；**运行时权威在 MoonBit**。

### 5.4 API

```text
grapheme_boundaries(text) -> Array[Int]
grapheme_count(text) -> Int
advance_visible_utf16(text, current_utf16, grapheme_delta) -> Int
clamp_to_grapheme_boundary(text, utf16) -> Int
visible_text_prefix(full, visible_utf16) -> String  // 仅边界下标

Stage::reveal_graphemes(n)  // 或保留 reveal_chars 名但语义为 grapheme
Stage::complete_text()
```

SkipTyping / complete：一次到全文边界。`relocalize` 的 `partial_visible_utf16` 与 clamp 一致。HUD body 与 render 布局共用同一 helper。

### 5.5 测试锚点

1. ASCII 与旧行为等价。  
2. CJK 步进。  
3. 组合字符不裸露 base。  
4. ZWJ 家庭不切开。  
5. 非法存档边界 load clamp。  
6. MoonBit 边界数组 == Host Segmenter fixtures。  
7. complete / SkipTyping 瞬时全文。

### 5.6 风险

| 风险 | 缓解 |
|------|------|
| 完整 UAX #29 过重 | 子集 + fixture 扩展 |
| 与浏览器 Segmenter 微差 | 引擎边界表为存档权威 |
| 每帧分段成本 | 缓存当前行 boundaries |

---

## 6. H4 — Glyph atlas 可增长

### 6.1 问题

1024×1024 满后 0×0 + pending 可能每帧重入队；Host 跳过非正尺寸且写死 atlas 边长 1024。

### 6.2 增长策略

| 规则 | 值 |
|------|-----|
| 初始 | 1024×1024 |
| 触发 | 下一 cell 放不进当前 shelf |
| 增长 | 正方形 `min(MAX, max(next_pow2(need), width*2))` |
| `MAX` | **4096** |
| 单 cell > MAX | **terminal overflow**：`pending=false`，0×0，永不重入队 |
| 增长时 | 清空 entries + cursor；全部字形重新排队；`generation += 1` |

本轮 **不做** multi-page atlas 或 LRU。

### 6.3 MoonBit / Host API

```text
GlyphAtlas.generation : Int
GlyphAtlas width/height 可变
export: atlas_width / atlas_height / atlas_generation
```

Host：

1. 禁止写死 1024；用 export 尺寸。  
2. `generation` 变化 → 重建 GPU/Canvas 纹理并清空像素，再 flush pending。  
3. 0×0 且非 pending：跳过，不重试。  
4. 成功栅格化才 `mark_glyph_ready`。

### 6.4 测试锚点

1. 填满 1024 → 触发 ≥2048 且 generation+1。  
2. 旧字 repack 后 UV 合法。  
3. cell > 4096 → terminal，不再 pending。  
4. Host 路径：generation 变化触发重建（可抽测）。  
5. 既有 CJK key 测不回归。

### 6.5 风险

| 风险 | 缓解 |
|------|------|
| repack 卡顿 | 仅溢出触发 |
| 4096 仍不够全集 CJK | 诚实限制 + terminal 诊断 |
| 1.1 native 分叉 | 本轮仅 main Web；合并时 follow-up generation API |

---

## 7. H5 — VM instruction budget 可观测

### 7.1 问题

默认 budget 10000 耗尽后静默结束循环并下帧重试——行为合理，但不可观测。

### 7.2 目标行为

| 项 | 合同 |
|----|------|
| 耗尽 | **不** `halted`；保持 `ip`；可续跑 |
| 诊断 | `budget_exhaustions += 1`；`last_budget_exhausted` 本帧 true |
| 下帧 | 再入 `run_until_wait`；正常 Yield/Choose 后清 last 标志 |
| 对外 | 可读计数/标志；**默认玩家 UI 不弹窗** |
| 文档 | 帧预算非全局死限；长脚本可跨帧 |

不改默认 10000；不做编译期分析。

### 7.3 测试锚点

1. 小 budget 强制耗尽 → 未 halt、计数 +1。  
2. 下帧完成 → last 标志清除。  
3. 短脚本计数保持 0。

---

## 8. 错误处理与诚实性

| 场景 | 行为 |
|------|------|
| Atlas terminal overflow | 缺字绘制，不崩溃；内部计数 / 可选 warn |
| Grapheme 非法存档边界 | load clamp，不因此单独 fail closed |
| Budget 耗尽 | 仅诊断，不 soft-halt 叙事 |
| 音频 clear | 幂等 |
| 假完成 | 禁止；不改 Formal 1.0 / production_ready 类声明 |

---

## 9. 测试与验收门禁

### 9.1 回归（实现完成后）

- `moon check --target all`  
- `moon test`  
- `apps/host-web`：`npm test`、`npx tsc --noEmit`、production build（H4 涉及）  
- `moonsightc check/build demo/game` 不回退  
- 文档与代码五条契约一致  

### 9.2 建议 SDD 任务切块（plan 细化）

1. H1 tick 重构 + 测  
2. H2 `clear_playback_session` + 测  
3. H3 grapheme + typewriter + 存档 clamp + Host fixture parity  
4. H4 atlas grow + export + Host 重建  
5. H5 budget 诊断 + 测  
6. 文档对齐 + 全量回归  

---

## 10. 交付物与后续

| 交付 | 路径 / 动作 |
|------|-------------|
| 本设计 | `docs/superpowers/specs/2026-07-14-moonsight-runtime-contract-hygiene-design.md` |
| 实现计划 | writing-plans → `docs/superpowers/plans/2026-07-14-moonsight-runtime-contract-hygiene.md` |
| 实现基线 | `main` 或自 main 的 hygiene 分支 |

**下一步（本 brainstorming 终端态）：** 用户审阅本 spec → 批准后 invoke **writing-plans**（不直接写生产代码）。

---

## 11. 自检记录（spec self-review）

| 检查 | 结果 |
|------|------|
| Placeholder / TBD | 无未决 TBD；`se_seq` 单调性允许实现时二选一并测 |
| 内部一致 | H1 表与 §3 结构一致；H2 不碰 load 合同；H3 不 bump save；H4 MAX 4096 唯一 |
| 范围 | 五条 Hygiene，可单 plan 切片；未混入 1.1 / 外部证据 |
| 歧义 | typewriter 在 modal 下继续 — 已明确；Title UI-only — 已明确 |
