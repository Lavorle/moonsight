# MoonSight Formal 1.0 发布收口设计

日期：2026-07-13  
目标版本：`v1.0.0`  
状态：Approved (brainstorming)  
类型：执行收口增量设计（不重写产品契约）

## 0. 关系与定位

本文件是 Formal 1.0 **公开发布闭环的执行收口**设计。产品支持范围、证据矩阵语义、候选身份与 Evidence Index / Final Gate 分离等契约，以既有文档为准：

- 产品与门禁契约：[`2026-07-13-moonsight-formal-1.0-public-release-design.md`](./2026-07-13-moonsight-formal-1.0-public-release-design.md)
- 实现计划（Tasks 1–8）：[`../plans/2026-07-13-moonsight-formal-1.0-public-release.md`](../plans/2026-07-13-moonsight-formal-1.0-public-release.md)
- 人工证据模板：[`../../release-1.0-verification.md`](../../release-1.0-verification.md)

**本文件新增的内容**是：在 Tasks 1–5 已于 `feat/formal-1.0-release` 落地的前提下，如何把剩余工作组织到 **annotated `v1.0.0` tag + 公开 GitHub Release**，包括工作流、授权边界、操作员职责与完成定义。

若本文件与既有 Formal 1.0 public-release design 在支持矩阵或证据语义上冲突，**以既有 public-release design 为准**，并修订本文件。

## 1. 目标与成功标准

### 1.1 目标

把 MoonSight 从「Formal 1.0 产品能力已具备、发布状态 `BLOCKED`」推进到可公开声明的 `v1.0.0`：同一不可变源码 SHA 绑定完整发行制品与 13 项真实环境证据，并完成 GitHub 公开发布。

### 1.2 成功标准

全部同时满足：

1. **不可变候选**：干净工作树上的唯一候选 commit SHA；候选身份 manifest 冻结后不可覆盖。
2. **制品齐全**：x86_64 Web ZIP、AppImage、deb、rpm 与 `SHA256SUMS`；可复现比较按既有 normalization policy 通过。
3. **自动化门禁通过**：MoonBit / Host / CLI / 包 / 可复现 / RC 工具 / 文档等既有自动化检查全部 PASS，且绑定同一候选 SHA。
4. **13 项证据全 PASS**：W1（6）+ D1（5）+ C1（2），每条绑定候选 SHA 与匹配制品摘要；公开证据脱敏。
5. **Final Gate PASS**：`technical_release_ready=true`；Evidence Index 与 Final Gate Report 不可变写出。
6. **公开发布完成**：annotated `v1.0.0` tag 精确指向候选 SHA；GitHub Release 经 draft 核验附件与 digests 后公开；公开 Evidence Index / Final Gate 作为 Release 附件或约定路径可复核。

任一正式支持项为 `FAIL`、`BLOCKED`、`NOT_RUN`，或证据与候选/制品不一致，**禁止** tag 与公开 Release。不得静默缩小支持范围。

### 1.3 已确认决策（brainstorming）

| 决策 | 选择 |
|------|------|
| 本轮优先级 | Formal 1.0 发布闭环（非 1.1 原生、非新引擎功能） |
| 成功终点 | 完整 `v1.0.0` 公开发布（含真实证据与 tag/Release） |
| 验证环境 | 操作员本机可覆盖 Ubuntu 24.04、Fedora 当前稳定版、Arch current |
| 组织方式 | 方案 A：续跑既有 plan 剩余任务，不重写总 design |
| 发布授权 | 工具链默认 dry-run；tag 推送与公开 Release 仅在 Final Gate 全 PASS **且操作员显式二次确认**后执行 |

## 2. 范围

### 2.1 包含

- 完成 plan Task 6：`publish_github_release.py`（dry-run 默认；`--execute` 需授权标志）。
- 完成 plan Task 7：CI 与 README / CHANGELOG / verification 文档对齐。
- 完成 plan Task 8：本地全量自动化 dry-run 与候选准备检查。
- 在 `feat/formal-1.0-release`（或其后继干净提交）上冻结候选、构建制品、生成候选身份 manifest。
- 操作员在三发行版上采集 W1 / D1 / C1 证据；agent 可协助模板填充校验与 gate 运行，不伪造 PASS。
- Evidence Index、Final Gate、draft-first 发布、附件 digests 核验、公开 Release。
- 发布后：分支合并策略与「已发布」文档状态更新（**不得**改写已验证 tag 指向的源码内容）。

### 2.2 不包含

- MoonSight 1.1 原生桌面（SDL/wgpu-native 等）。
- 新叙事、演出、UI、脚本或渲染功能。
- Windows / macOS 支持声明。
- GitHub Pages 在线试玩。
- 为通过门禁而降低存档、回滚、本地化或错误处理契约。
- 代码签名、公证、发行版官方仓库提交。
- 改变 13-ID 封闭矩阵或把某正式环境降级为「实验性」。

### 2.3 与 worktree 现状

截至本 design 撰写时：

- 分支：`feat/formal-1.0-release`（worktree：`.worktrees/formal-1.0-release`）。
- **已完成**：Tasks 1–5（release schema、候选身份 v2、evidence 校验与 index、Final Gate、制品构建与可复现边界）；相关 Python 单测本地可绿。
- **未完成**：Task 6 Publisher、Task 7 CI/文档对齐、Task 8 全量 dry-run、真实 W1/D1/C1、tag/Release。
- `main` 上 Formal 1.0 验证记录仍为 **BLOCKED** / `NOT SELECTED`。

实现阶段默认继续在该 worktree 推进，避免在脏 `main` 上混入候选。

## 3. 架构与工作流

### 3.1 端到端流水线

```
feat/formal-1.0-release (Tasks 1–5 done)
        │
        ▼
[Task 6] publish_github_release.py
         dry-run 默认；execute 需 --authorize 与操作员确认
        │
        ▼
[Task 7] CI + 发布文档对齐
         verification 在真实证据前保持 BLOCKED
        │
        ▼
[Task 8] 本地全量自动化 dry-run
         证明「可冻结」路径，不宣称 GUI PASS
        │
        ▼
[Ops-1] 干净树冻结候选 + 构建制品 + manifest
        │
        ▼
[Ops-2] 操作员采集 13 项 W1/D1/C1 证据
        │
        ▼
[Ops-3] Evidence Index → Final Gate
        │
        ▼
[Ops-4] 操作员二次确认后：
         annotated tag → draft Release + 上传
         → 核验远端 digests → 公开 Release
```

### 3.2 组件职责

| 组件 | 拥有 | 不拥有 |
|------|------|--------|
| 运行时 / 编译器 / Host | 游戏与工具语义 | 发布门禁判定 |
| `release_schema` / evidence / gate（已完成） | 13-ID 矩阵、校验、不可变报告 | 运行时行为；发布授权 |
| `build_release_artifacts.sh`（已完成） | 一次产出四制品 + SUMS + 候选身份输入 | 把 W1/D1/C1 写进候选 commit |
| `publish_github_release.py`（待做） | dry-run 摘要；execute 时 tag、draft、上传、可选公开 | 默认推远端；跳过 draft 直接公开 |
| 操作员 | 真机 GUI 证据、二次确认、凭据 | 伪造证据；在 Gate 失败时强行发布 |
| CI | 自动化工具与文档检查 | 将 GUI 结果标为 PASS |

### 3.3 发布授权模型

1. **技术就绪**与**发布授权**分离。Final Gate 最多证明 `technical_release_ready`；`publication_authorized` 默认为 false，不由自动化单独置 true。
2. Publisher **默认 dry-run**：打印将执行的 tag 名、目标 SHA、附件列表与 digests，零远端副作用。
3. **`--execute` 路径**还须显式授权参数（例如与版本字符串绑定的 `--authorize v1.0.0`），且仅在会话中操作员书面确认后由执行者调用。
4. 顺序固定：annotated tag（指向候选 SHA）→ draft GitHub Release → 上传全部制品与公开证据附件 → 核验远端附件 SHA-256 → 再公开 draft。
5. 远端已存在冲突 tag/Release：停止，交操作员决策；禁止 force 移动公开历史。

## 4. 数据流与证据

### 4.1 三类不可变产物

1. **候选身份 manifest**（构建时冻结）  
   版本、候选编号、commit SHA、clean-tree 证明、工具链、四制品路径/大小/SHA-256、自动化结果引用。**不含** W1/D1/C1 结果。

2. **证据记录**（候选提交之外）  
   每 evidence ID 一份 JSON：候选 SHA、制品 path/digest、环境、测试者、UTC 时间、有序步骤与逐步结果、日志/截图引用、存档/localStorage 脱敏检查、状态 `PASS|FAIL|BLOCKED|NOT_RUN`。公开版脱敏；原始证据本地留存并与公开 digest 关联。

3. **Evidence Index + Final Gate Report**  
   引用候选与 13 条记录；聚合 PASS 仅当全部 PASS 且 digests 一致。以 `O_EXCL` 语义写出，禁止覆盖。

### 4.2 封闭证据矩阵

与 public-release design 一致，**恰好 13 个 ID**。权威顺序以 `scripts/release_schema.py` 中 `REQUIRED_EVIDENCE_IDS` 为准（`feat/formal-1.0-release` 已实现）：

| 组 | IDs |
|----|-----|
| W1（6） | `W1-ubuntu-chromium`, `W1-ubuntu-firefox`, `W1-fedora-chromium`, `W1-fedora-firefox`, `W1-arch-chromium`, `W1-arch-firefox` |
| D1（5） | `D1-ubuntu-appimage`, `D1-ubuntu-deb`, `D1-fedora-appimage`, `D1-fedora-rpm`, `D1-arch-appimage` |
| C1（2） | `C1-web`, `C1-desktop` |

- W1 针对 Web ZIP；浏览器产品为 Chromium stable 与 Firefox stable。
- D1：Ubuntu 验证 AppImage+deb；Fedora 验证 AppImage+rpm；Arch 验证 AppImage；桌面 appData 持久化。
- C1：Web ZIP 与桌面制品各一次完整 demo 通关。

WebGPU adapter 不可用记为环境失败（`FAIL` 或 `BLOCKED`），不是可忽略警告。

### 4.3 候选失效

修复产品或发布关键缺陷后：

1. 旧候选身份与证据保留为历史，不覆盖。
2. 新提交获得新候选编号。
3. 重建全部制品与 digests。
4. 旧证据不得复用。
5. 自动化与人工矩阵从头执行。

## 5. 错误处理

| 失败类 | 处理 |
|--------|------|
| Task 6–8 实现/单测失败 | 修代码并重跑测试；尚未冻结候选则不必换候选号 |
| 制品构建或可复现失败 | 不冻结；修复后重建 |
| 单环境 W1/D1 失败 | 如实记录；禁止将该环境降级为非支持；修复后新候选全量重跑，或停止发布 |
| Final Gate 不通过 | 禁止 tag 与 Release |
| `v1.0.0` tag 已存在或远端冲突 | 停止；人工决策；不 force 改写公开历史 |
| Release 上传不完整 | 保持 draft；补齐并核验后再公开 |
| 凭据 / 网络失败 | dry-run 仍可成功；execute 失败并停止，不留下半公开状态作为成功 |
| tag 创建成功但推送失败 | 保留本地事实；解决远端后核验 SHA；禁止改指向其他提交 |

## 6. 测试与验收

### 6.1 自动化（实现阶段）

- Publisher 单测：dry-run 无副作用；缺少授权拒绝 execute；draft-first 顺序；错误 tag/SHA 拒绝。
- 既有 schema / evidence / gate / 可复现比较回归全绿。
- CI 运行发布工具 Python 测试与文档 typecheck；**不**在 CI 中声称 W1/D1/C1 PASS。
- Task 8 dry-run：干净树路径上构建制品、比较可复现、候选 guard，证明可冻结。

### 6.2 人工（发布前）

- 按 `docs/release-1.0-verification.md` 与 evidence 模板在每正式环境执行。
- C1：Web ZIP 与选定桌面制品各完整通关 demo 一次（无调试捷径）。
- Final Gate 只读通过后，向操作员展示不可逆操作摘要（tag 名、SHA、附件列表与 digests）。

### 6.3 完成定义（DoD）

- 远端 annotated `v1.0.0` = 候选 SHA。
- GitHub Release 已公开；附件 digests 与 `SHA256SUMS` 及候选 manifest 一致。
- 公开 Evidence Index 与 Final Gate Report 可复核，且 13 ID 均为 PASS。
- 仓库文档声明的支持矩阵与本轮证据一致；verification 流程文档不再暗示「未选候选即可发布」。

## 7. 实现切片

实现计划应沿用既有 plan 任务编号，并追加操作步骤：

| 切片 | 内容 | 产出 |
|------|------|------|
| Task 6 | `publish_github_release.py` + 测试 | dry-run / execute 路径 |
| Task 7 | CI 与 README、CHANGELOG、verification 对齐 | 文档与流水线一致 |
| Task 8 | 全量本地 dry-run 与检查清单 | 「可冻结」证明 |
| Ops-1 | 冻结候选、制品、manifest | 候选身份 |
| Ops-2 | 采集 13 证据 | 证据记录 + 原始留存 |
| Ops-3 | Index + Final Gate | 技术就绪报告 |
| Ops-4 | 二次确认后 tag、draft、核验、公开 | `v1.0.0` 公开发布 |
| Ops-5 | 合并 `feat/formal-1.0-release` 策略与发布后文档状态 | 历史干净；不改 tag 树内容 |

详细 checkbox 步骤由后续 **writing-plans** 产出；本 design 不绑定具体脚本内部函数名，除非其已成为 plan 中的稳定接口。

## 8. 风险与缓解

| 风险 | 缓解 |
|------|------|
| Linux Firefox WebGPU 不稳定 | 如实记 FAIL/BLOCKED；不降级；优先修复环境 flags 或产品问题后重候选 |
| 多发行版证据耗时 | 操作员环境已确认可覆盖三发行版；证据模板与校验脚本降低格式返工 |
| 半公开 Release | draft-first + 附件 digest 核验后才公开 |
| 工作树/SHA 漂移 | gate 校验 HEAD=候选、干净树、无既有 `v1.0.0` tag |
| 与 1.1 原生工作混淆 | 本轮范围明确排除；1.1 仅在独立 worktree/分支 |

## 9. 设计约束小结

- 不新增运行时产品 API；发布控制面属于仓库工具与流程。
- 候选身份永不包含事后 W1/D1/C1 结果。
- 证据工具只记录事实，不改变存档/本地化/回滚语义。
- 支持矩阵与 13 ID 封闭集合不可在本轮单方面修改。
- 操作员二次确认是发布的硬门禁，不是礼貌性提示。
