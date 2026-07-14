# MoonSight Formal 1.0 — Fedora 首批证据与候选冻结设计

**日期：** 2026-07-14  
**状态：** Approved (brainstorming)  
**类型：** 执行增量设计（不改产品契约 / 不授权公开发布）  
**方案：** A — 在现有 Formal 1.0 契约上完成 Fedora 可达矩阵 + 候选冻结  

## 0. 关系与定位

本文件是 Formal 1.0 **公开发布闭环**上的阶段性执行设计。产品支持范围、13-ID 封闭矩阵、候选身份与 Evidence Index / Final Gate 分离等契约，以下列为权威，本文件不得与之冲突：

| 权威文档 | 角色 |
|----------|------|
| [`2026-07-13-moonsight-formal-1.0-public-release-design.md`](./2026-07-13-moonsight-formal-1.0-public-release-design.md) | 支持矩阵、13 ID、制品集合、禁止静默降级 |
| [`2026-07-13-moonsight-formal-1.0-release-closure-design.md`](./2026-07-13-moonsight-formal-1.0-release-closure-design.md) | 完整 v1.0.0 终点（tag + GitHub Release） |
| [`../../release-1.0-verification.md`](../../release-1.0-verification.md) | W1 / D1 / C1 逐步操作模板 |
| [`../../formal-1.0-rc-tooling.md`](../../formal-1.0-rc-tooling.md) | 基准、可复现、RC manifest、index、gate、publisher |

**本文件新增的内容**是：在操作员环境仅完整覆盖 **Fedora 当前 stable + WebGPU 浏览器 + 桌面制品安装** 的前提下，如何完成「可冻结候选 + Fedora 证据全绿 + 诚实 BLOCKED 全局状态 + Ubuntu/Arch 交接」，且**不**创建 `v1.0.0` tag、**不**执行公开 Release。

若与 public-release design 在支持矩阵或证据语义上冲突，**以 public-release design 为准**，并修订本文件。

完整发布（13/13 PASS → Final Gate 技术就绪 → 操作员二次确认 → tag/Release）仍由 release-closure design 的 Ops-4 定义；本轮**不**执行该切片。

---

## 1. 目标与成功标准

### 1.1 目标

在干净仓库树（优先已合并 Formal 1.0 工具链与 AppImage/可复现修复的 `main` tip）上：

1. 冻结一个不可变候选 SHA 与四制品集合；  
2. 在 Fedora 上把**可达**的真机证据做到诚实 `PASS`；  
3. 对 Ubuntu / Arch 保持 `NOT_RUN` 并写出可交接 Ops 清单；  
4. 全仓库文档与 Final Gate 继续声明整体 release **BLOCKED**。

### 1.2 成功标准（DoD）

全部同时满足：

1. **干净候选：** 唯一候选 commit SHA；工作树无 tracked 脏文件；`rc_manifest.py guard --candidate <SHA> --repo .` 通过。  
2. **制品齐全：** 自该 SHA 产出  
   `moonsight-web-x86_64-v1.0.0.zip`、  
   `moonsight-linux-x86_64-v1.0.0.AppImage`、  
   `moonsight-linux-x86_64-v1.0.0.deb`、  
   `moonsight-linux-x86_64-v1.0.0.rpm`、  
   `SHA256SUMS`。  
3. **可复现：** 双构建比较按 `scripts/reproducibility-normalization-v1.json` 通过；失败则**不**宣称可冻结候选用于后续 13/13 发布（本轮可记录 BLOCKED 原因并停止在 Art，不得伪造 PASS）。  
4. **自动化门禁：** 对该候选执行 Formal 1.0 自动化矩阵（`moon fmt --check`、`moon check --target all`、`moon test`、host wasm 构建、`apps/host-web` 测试/类型检查/构建、CLI check/build/package smoke、`python3 -m unittest discover -s scripts -p 'test_*.py'`、desktop Rust fmt/check/test 等，与 `release-1.0-verification.md` 自动化表一致）全部 exit 0；结果路径写入 RC 元数据。  
5. **Fedora 六证 PASS：** 外部证据目录中下列 ID 均为 `PASS`，且绑定同一候选 SHA 与匹配制品 digest：  
   - `W1-fedora-chromium`  
   - `W1-fedora-firefox`  
   - `D1-fedora-appimage`  
   - `D1-fedora-rpm`  
   - `C1-web`  
   - `C1-desktop`  
6. **其余七证诚实空位：**  
   `W1-ubuntu-chromium`、`W1-ubuntu-firefox`、`D1-ubuntu-appimage`、`D1-ubuntu-deb`、  
   `W1-arch-chromium`、`W1-arch-firefox`、`D1-arch-appimage`  
   均为 `NOT_RUN`（环境明确不可达且短期无法安排时可用 `BLOCKED`，**禁止** `PASS`）。  
7. **Index + Gate：** `release_evidence.py build-index` 与 `verify_release_evidence.py` 可运行；**预期** `technical_release_ready=false`，聚合状态非 PASS。该负向结果是本轮**成功信号**（工具未放水）。  
8. **交接：** 存在 `HANDOFF-ubuntu-arch.md`（见 §4），使后续操作员无需重读本 design 历史即可续跑。  
9. **禁止发布动作：** 不创建 annotated `v1.0.0` tag；不调用 `publish_github_release.py --execute`；不把 `release-1.0-verification.md` Overall 改为 PASS；不把 CHANGELOG 写成已发布。

### 1.3 已确认决策（brainstorming）

| 决策 | 选择 |
|------|------|
| 主战场 | Formal 1.0 发布闭环（非 1.1 原生、非新引擎功能） |
| 组织方式 | 方案 A：现有契约上的 Ops 执行，不扩 partial-progress 工具 |
| 环境覆盖 | 仅 Fedora 当前 stable + WebGPU 可玩 + 桌面制品 GUI 确定可达 |
| Ubuntu / Arch | 本轮不采证；交接清单；全局仍 BLOCKED |
| 发布终点 | **不是** v1.0.0 公开；是「可冻结 + Fedora 绿 + 诚实未就绪」 |

### 1.4 非目标

- MoonSight 1.1 原生桌面（SDL/wgpu 等）及 `feat/native-1.1-desktop` 合并。  
- 书面缩窄 13-ID 正式支持矩阵。  
- Windows / macOS 支持声明。  
- GitHub Pages 在线试玩。  
- 为通过门禁而削弱存档、回滚、本地化或错误处理契约。  
- 代码签名、公证、发行版官方仓库提交。  
- 可视化编辑器、语音轨、Live2D、粒子等 Q5+ 产品能力。  
- 新增发布 API 或「分阶段仪表盘」类工具功能（现有 per-ID `NOT_RUN` 足够）。

---

## 2. 范围：证据 ID 与制品绑定

### 2.1 本轮必 PASS

| ID | 表面 | 制品绑定 |
|----|------|----------|
| `W1-fedora-chromium` | Fedora + Chromium stable + WebGPU 游玩与 web 持久化 | Web ZIP |
| `W1-fedora-firefox` | Fedora + Firefox stable + WebGPU | Web ZIP |
| `D1-fedora-appimage` | Fedora + AppImage + 全退出后 appData 存读 | AppImage |
| `D1-fedora-rpm` | Fedora + rpm + 全退出后 appData 存读 | rpm |
| `C1-web` | 代表 demo 完整通关（web） | Web ZIP |
| `C1-desktop` | 代表 demo 完整通关（desktop） | 本轮以 **AppImage** 为桌面代表制品（与 schema 中 desktop 路径一致；若记录字段要求包类型枚举，使用工具已批准的 desktop 组合） |

W1 / D1 / C1 的**逐步操作与期望结果**不重复定义，一律执行 [`release-1.0-verification.md`](../../release-1.0-verification.md) 中对应章节。

### 2.2 本轮必留空

七条 Ubuntu/Arch ID：字段完整、`status=NOT_RUN`（或诚实 `BLOCKED`）、`candidate_sha` 与冻结 SHA 一致、不填伪造截图路径。

### 2.3 封闭矩阵不变

权威 ID 列表与顺序以 `scripts/release_schema.py` 中 `REQUIRED_EVIDENCE_IDS` 为准。本轮**不**增删 ID、**不**把某正式环境降级为「实验性」。

---

## 3. 架构与工作流

### 3.1 端到端流水线

```
干净 main tip（含 Formal 1.0 工具链）
        │
        ▼
[Prep]  自动化矩阵全绿；工作树 clean
        │
        ▼
[Art]   build_release_artifacts.sh
        双构建 + compare_reproducible_builds.py
        │
        ▼
[Freeze] candidate 身份 + rc_manifest.py generate
         此后每次采证前：rc_manifest.py guard
        │
        ▼
[Fedora-W1] Chromium + Firefox × Web ZIP
        │
        ▼
[Fedora-D1] AppImage + rpm × appData 持久化
        │
        ▼
[C1]    C1-web + C1-desktop（可与 W1/D1 同会话体验，但须独立 JSON 记录）
        │
        ▼
[Index] release_evidence.py build-index
        （6 PASS + 7 NOT_RUN）
        │
        ▼
[Gate]  verify_release_evidence.py
        期望 technical_release_ready=false
        │
        ▼
[Handoff] HANDOFF-ubuntu-arch.md + verification 诚实更新
        ✗  禁止 tag / publisher --execute
```

### 3.2 组件职责

| 角色 | 拥有 | 不拥有 |
|------|------|--------|
| 引擎 / Host / CLI | 产品语义；Prep 失败时的缺陷修复 | 发布门禁判定 |
| `build_release_artifacts.sh` / 可复现工具 | 四制品 + SUMS + 双构建比较 | 把 W1/D1/C1 写进候选 commit |
| `rc_manifest.py` / candidate 身份 | 冻结时事实；guard 防 SHA 漂移 | W1/D1/C1 结果 |
| 操作员（GUI） | 真机证据、截图/日志留存、二次确认「未授权发布」 | 伪造 PASS；在 Gate 失败时强行发布 |
| Agent | 跑自动化、校验 JSON/schema、写 handoff、填模板草稿 | 在无 GUI 证据时宣称 W1/D1/C1 PASS |
| CI | 自动化与工具单测 | 将 GUI 标为 PASS |
| Publisher | 本轮仅允许 dry-run 自检（可选） | `--execute` 与真实远端 tag/Release |

### 3.3 候选失效规则

与 public-release / closure design 一致：

1. 修复**产品**或**打包语义**缺陷后：新 commit、新候选编号、重建全部制品 digests、**作废**全部已采证据（含已 PASS 的 Fedora 项）。  
2. 仅修复操作员环境（浏览器 flags、驱动）且候选树未变：可对同一候选重跑失败的证据项。  
3. 旧候选目录保留为历史，不覆盖不可变 JSON（create-only / O_EXCL 语义保持）。

### 3.4 与 1.1 / 其他 worktree

- 冻结与 guard 只针对**候选仓库路径**（通常是干净 `main` clone 或 clean checkout）。  
- `.worktrees/native-1.1` 等并行工作**不得**混入候选树的 tracked 变更。  
- 本轮不合并、不验收 1.1 native。

---

## 4. 外部证据目录

证据在**候选提交之外**。推荐布局（路径可置于仓库外或 gitignored 根；**禁止**把原始隐私日志 force-add 进候选 commit）：

```text
evidence/formal-1.0/<candidate_short_sha>/
  candidate.json
  rc-manifest.json
  artifacts/                 # 或指向 RELEASE_OUT/first 的约定链接
  repro-report.json
  benchmark-report.json      # 若 RC 生成要求基准摘要：按 formal-1.0-rc-tooling 提供合法输入；缺则阻塞 Freeze 而非伪造
  records/
    W1-fedora-chromium.json
    W1-fedora-firefox.json
    D1-fedora-appimage.json
    D1-fedora-rpm.json
    C1-web.json
    C1-desktop.json
    W1-ubuntu-chromium.json    # NOT_RUN stub
    W1-ubuntu-firefox.json
    D1-ubuntu-appimage.json
    D1-ubuntu-deb.json
    W1-arch-chromium.json
    W1-arch-firefox.json
    D1-arch-appimage.json
  raw/                       # 控制台日志、截图、脱敏 localStorage / appData 检查记录
  evidence-index.json
  final-gate.json
  HANDOFF-ubuntu-arch.md
```

### 4.1 记录诚实规则

1. 未执行的步骤不得写 `PASS`。  
2. WebGPU adapter 不可用 → `FAIL` 或 `BLOCKED`（环境失败），不是可忽略警告。  
3. 每条 PASS 记录必须含：候选 SHA、制品 path + SHA-256、OS/浏览器或包装格式与版本、测试者、UTC 时间、有序步骤结果、原始证据引用。  
4. 公开脱敏与原始留存的关系遵循 public-release design；本轮若无公开发布，原始证据仍须本地可复核。

### 4.2 Handoff 最低内容

`HANDOFF-ubuntu-arch.md` 必须包含：

- 候选完整 SHA、制品文件名与 `SHA256SUMS` 摘要；  
- 证据根路径约定；  
- 已 PASS 的 6 个 ID 列表；  
- Ubuntu 24.04 与 Arch 上剩余 7 个 ID 的逐步清单（引用 verification 文档章节）；  
- guard 命令与「改树则全作废」提醒；  
- 明确：**在 13/13 之前禁止 tag 与 GitHub Release execute**。

---

## 5. 文档与仓库状态更新

本轮允许且应当更新的**诚实**文档面：

| 文档 | 允许的更新 |
|------|------------|
| `docs/release-1.0-verification.md` | 填入候选 SHA、Fedora 相关 ID 结果、自动化结果引用；Overall 保持 **BLOCKED** |
| `CHANGELOG.md` | 可注明工具链就绪与「未发布 / 矩阵未满」；禁止宣称 matrix PASS 或已 tag |
| `README.md` / `README.en.md` / `README.mbt.md` | 支持矩阵声明不变；可链到本阶段进度说明，仍写 BLOCKED |

禁止：把 13 条全部标 PASS、把 verification 写成可发布、静默删除 Ubuntu/Arch 行。

---

## 6. 错误处理

| 失败类 | 处理 |
|--------|------|
| Prep 自动化失败 | 修缺陷 → 新 commit → 重跑 Prep；尚未 Freeze 则无候选号债务 |
| AppImage / linuxdeploy / deb / rpm 构建失败 | 不 Freeze；修环境或打包脚本；**不**从正式制品集中删除 AppImage |
| 可复现比较失败 | 不宣称可发布候选；分析是否 allowlist 政策变更（需独立评审）或非确定性 bug |
| 仅 Firefox WebGPU 失败 | 如实 FAIL/BLOCKED；尝试文档中的 flags；同树可重跑；禁止用 Chromium 结果冒充 Firefox |
| Fedora 产品行为 FAIL | 修复 → **新候选** → 作废旧证据 → 全量重跑 Fedora 六证 |
| Index 缺记录 / digest 不匹配 | 修记录后重建 index（遵守不可覆盖策略：使用新输出路径或新候选目录） |
| Final Gate 技术未就绪 | **预期**；写入 handoff；禁止 publisher execute |
| 误创建 tag 或半公开 Release | 立即停止；操作员按 closure design 处理冲突；禁止 force 改写已推送历史并当作成功 |
| 与 1.1 树混淆 | 重新确认 cwd 与 `git rev-parse HEAD`；仅在候选路径 guard |

---

## 7. 测试与验收

### 7.1 自动化

- 现有发布工具单测保持绿：`python3 -m unittest discover -s scripts -p 'test_*.py'`。  
- 本轮**不**要求新增 publisher/schema 功能。  
- Prep 矩阵命令以 verification 文档自动化表为准；全部 exit 0 才进入 Art。

### 7.2 人工

- 六条 Fedora/C1 证据按 verification 模板逐步执行。  
- C1 必须完整 demo 通关，禁止「只点到标题」或调试捷径冒充。  
- Agent 可校验 JSON 字段与 digest 一致性，不可在无 raw 证据时签 PASS。

### 7.3 负向 Gate 验收

对含 7×`NOT_RUN` 的 index 运行 Final Gate：

- 必须得到 `technical_release_ready=false`（或工具等价失败）；  
- 该结果记入 `final-gate.json` 并作为本轮完成证据之一。

### 7.4 完成定义（对照 §1.2）

- 六证 PASS + 七证空位 + 候选冻结 + 负向 Gate + handoff + 文档 Overall BLOCKED + 无 tag/无 execute。  
- **不**要求远端 GitHub Release 或 13/13。

---

## 8. 实现切片（供 writing-plans）

实现计划应展开为可 checkbox 的步骤，建议切片：

| 切片 | 内容 | 主要执行者 |
|------|------|------------|
| T1 Prep | 干净树、全量自动化、记录日志路径 | agent + 操作员确认 |
| T2 Art | 四制品 + 双构建可复现 | agent / 操作员 |
| T3 Freeze | candidate + RC manifest + guard 纪律 | 操作员确认 SHA |
| T4 Fedora W1 | Chromium + Firefox 记录 | 操作员 GUI；agent 校验 |
| T5 Fedora D1 | AppImage + rpm 记录 | 操作员 GUI；agent 校验 |
| T6 C1 | web + desktop 通关记录 | 操作员 GUI；agent 校验 |
| T7 Index/Gate | build-index + verify；期望未就绪 | agent |
| T8 Handoff/Docs | HANDOFF、verification/CHANGELOG/README 诚实更新 | agent；操作员审阅 |
| T9 Stop line | 确认无 `v1.0.0` tag、无 execute、Overall BLOCKED | 双方 |

详细命令、路径与 fixture 由 **writing-plans** 产出；本 design 不绑定未稳定的内部函数名，稳定 CLI 入口以 `docs/formal-1.0-rc-tooling.md` 为准。

---

## 9. 风险与缓解

| 风险 | 缓解 |
|------|------|
| AppImage 在部分主机仍因 linuxdeploy 失败 | Art 失败则停止；沿用近期 packaging 修复；不删制品类型 |
| Linux Firefox WebGPU 不稳定 | 如实记录；flags 重试；不降级矩阵 |
| 操作员把「Fedora 全绿」误认为可发布 | DoD 与 handoff 显式禁止；Gate 负向验收 |
| 候选 SHA 在采证中漂移 | 每次 guard；改树则新候选 |
| 与 1.1 并行分心 | 范围排除；独立 worktree |
| 证据进 git 污染候选 | 外部证据根 + untracked 忽略策略 |

---

## 10. 设计约束小结

1. 不新增运行时产品 API；不扩发布控制面功能。  
2. 13-ID 封闭集合与 Linux x86_64 支持声明不变。  
3. 候选身份不含事后 W1/D1/C1 结果。  
4. 本轮终点是 **Fedora 六证 + 冻结 + 诚实 BLOCKED**，不是 v1.0.0 公开。  
5. Agent 不伪造 GUI PASS；操作员是真机证据权威。  
6. Final Gate 技术未就绪是预期成功，不是实施失败。
