# MoonSight Formal 1.0 公开发布闭环设计

日期：2026-07-13  
目标版本：`v1.0.0`  
状态：待用户审阅

## 1. 目标与成功标准

本轮把当前已经具备主要产品能力、但发布状态仍为 `BLOCKED` 的 MoonSight，推进为可公开发布的 Formal 1.0。重点不是增加引擎功能，而是证明同一份不可变源码和同一组发行制品在声明支持的环境中真实可用，并把证明结果绑定到最终 Git tag 与 GitHub Release。

成功必须同时满足：

1. `v1.0.0` 对应一个干净、不可变且经过验证的提交 SHA。
2. 自动化检查、可复现构建检查和发行包检查全部通过。
3. x86_64 Web ZIP、AppImage、deb、rpm 来自同一候选提交并记录 SHA-256。
4. Ubuntu 24.04、Fedora 当前稳定版、Arch current 全部完成规定的真实 GUI/WebGPU 验证。
5. Chromium stable 和 Firefox stable 都作为正式支持浏览器通过 Web 验证。
6. W1、D1、C1 的所有必需记录均为 `PASS`，且引用相同候选 SHA 和匹配的制品摘要。
7. 只有完整门禁通过后，才创建 annotated `v1.0.0` tag、GitHub Release 并上传制品。

任一正式支持项出现 `FAIL`、`BLOCKED`、`NOT RUN` 或证据不一致，整个 `v1.0.0` 发布保持阻塞，不允许静默降级支持范围。

## 2. 范围

### 2.1 包含

- 不可变候选提交和候选 manifest。
- Web ZIP、Linux AppImage、deb、rpm 的构建和校验。
- Ubuntu、Fedora、Arch 的真实验证矩阵。
- Chromium stable 和 Firefox stable 的 WebGPU 验证。
- Web 存档、桌面 appData 持久化、完整样章通关验证。
- 自动化门禁、人工证据采集、证据一致性检查。
- annotated Git tag、GitHub Release、制品和校验和上传。
- 与最终支持矩阵一致的 README、发布说明和验证文档更新。

### 2.2 不包含

- 语音轨、动画时间轴、旋转、锚点、Live2D、3D 或后处理。
- 可视化编辑器、成就、云存档或 Web/桌面存档迁移。
- GitHub Pages 在线试玩；Web 版仅作为 Release ZIP 交付。
- Windows 或 macOS 支持声明。
- 为通过发布门禁而降低现有存档、回滚、本地化或错误处理契约。
- 代码签名、公证和发行版官方软件仓库提交。

发现产品缺陷时可以修复，但修复会产生新的候选提交，并使旧候选的全部发布证据失效。

## 3. 支持声明

### 3.1 Web

- 交付物：版本化 Web ZIP，可部署到 HTTPS 或通过 localhost 提供服务。
- CPU 架构：x86_64。
- 正式支持的浏览器产品：Chromium stable 与 Mozilla Firefox stable；Google Chrome、Brave、Edge 等其他 Chromium 衍生浏览器属于尽力支持，不进入 1.0 阻断矩阵。
- 操作系统验证环境：Ubuntu 24.04、Fedora 当前稳定版、Arch current。
- WebGPU adapter 不可用属于环境验证失败，而不是可忽略警告。

### 3.2 Desktop

- 正式支持：Linux。
- CPU 架构：x86_64。
- 制品：AppImage、deb、rpm。
- Ubuntu：验证 AppImage 和 deb。
- Fedora：验证 AppImage 和 rpm。
- Arch：验证 AppImage。
- 桌面存档继续使用 Tauri appData；不改变 Web 与 Desktop 槽位互不相通的产品契约。

## 4. 发布控制面

发布控制面属于仓库工具与发布流程，不成为运行时产品 API。

### 4.1 Candidate Manifest

候选身份 manifest 是一次发布尝试在构建完成时冻结的身份记录。它使用版本化 schema，生成后不可覆盖，且只包含冻结时已经存在的事实：

- 版本和候选编号；
- Git commit SHA；
- clean-tree 证明；
- 构建时间与构建主机信息；
- MoonBit、Node、Rust、Tauri 及系统工具版本；
- Web ZIP、AppImage、deb、rpm 的文件名、大小和 SHA-256；
- 可复现构建或规范化比较结果；
- 自动化门禁结果引用；
- 必需证据矩阵的条目 ID 与预期 schema version，但不包含尚未产生的结果。

Manifest 描述事实，不决定运行时行为。最终 tag 必须精确指向 manifest 中的 commit SHA。

真实验证完成后，单独生成版本化的 **Evidence Index** 和 **Final Gate Report**。它们引用不可变候选身份 manifest、各证据文件及摘要，但不修改候选提交。公开脱敏版本作为 GitHub Release 附件；完整原始证据保存在发布操作者控制的留存位置，至少保留到 1.0 支持周期结束。公开 Evidence Index 记录每份公开证据与对应原始证据的摘要关联，但不暴露原始路径或隐私内容。最终验证结果不通过候选后的源码提交写回 tag 内容，因此不会产生“验证 A、发布 B”的 SHA 漂移。

### 4.2 Artifact Builder

发行构建必须从干净工作树开始，并一次性产出候选制品集：

- `moonsight-web-x86_64-v1.0.0.zip`
- `moonsight-linux-x86_64-v1.0.0.AppImage`
- `moonsight-linux-x86_64-v1.0.0.deb`
- `moonsight-linux-x86_64-v1.0.0.rpm`
- `SHA256SUMS`
- candidate manifest

具体内部路径或脚本名不是长期产品契约；实施计划可复用现有 `publish-web.sh`、`publish-desktop.sh` 和 RC 工具，也可在保持单一入口与一致证据语义的前提下收窄它们。

### 4.3 Evidence Bundles

每个证据记录必须能由人复核，并包含：

- 候选 SHA 与制品 SHA-256；
- OS、内核、桌面环境、浏览器/WebView、GPU 和驱动；
- 测试者与 UTC 时间；
- 执行步骤和逐项结果；
- 控制台、应用或系统日志；
- 必要截图或视频；
- 存档文件或 localStorage 的脱敏检查结果；
- 最终 `PASS`、`FAIL`、`BLOCKED` 或 `NOT RUN` 状态。

截图和日志用于证明，不控制产品行为，也不进入运行时发行包。公开证据必须脱敏用户名、主目录、设备序列号、凭据、完整 appData 内容及其他个人信息；原始证据与公开证据分别计算摘要。

必需证据项是封闭集合：

| ID | 必需环境/制品 |
|---|---|
| `W1-ubuntu-chromium` | Ubuntu 24.04 + Chromium stable + Web ZIP |
| `W1-ubuntu-firefox` | Ubuntu 24.04 + Firefox stable + Web ZIP |
| `W1-fedora-chromium` | 冻结的 Fedora stable 版本 + Chromium stable + Web ZIP |
| `W1-fedora-firefox` | 同一 Fedora 版本 + Firefox stable + Web ZIP |
| `W1-arch-chromium` | 冻结日期的 Arch 快照 + Chromium stable + Web ZIP |
| `W1-arch-firefox` | 同一 Arch 快照 + Firefox stable + Web ZIP |
| `D1-ubuntu-appimage` | Ubuntu 24.04 + AppImage，含启动、持久化与完整退出 |
| `D1-ubuntu-deb` | Ubuntu 24.04 + deb，含安装、启动、持久化与完整退出 |
| `D1-fedora-appimage` | 冻结的 Fedora 版本 + AppImage，含启动、持久化与完整退出 |
| `D1-fedora-rpm` | 同一 Fedora 版本 + rpm，含安装、启动、持久化与完整退出 |
| `D1-arch-appimage` | 冻结日期的 Arch 快照 + AppImage，含启动、持久化与完整退出 |
| `C1-web` | 任一正式支持 Web 环境使用最终 Web ZIP 完整通关 |
| `C1-desktop` | 任一正式支持桌面组合使用最终桌面制品完整通关 |

安装/启动检查并入对应 D1；不存在可替代 D1 的独立模糊 smoke 状态。Evidence Index 必须恰好聚合上述 13 个唯一 ID；重复记录可以留存，但不能弥补任何缺失 ID。Release Gate 仅在 13 项全部为 `PASS` 时通过。

### 4.4 Release Gate

Release Gate 读取 candidate manifest 和证据记录，检查：

1. 所有必需条目存在且为 `PASS`；
2. 所有记录引用相同候选 SHA；
3. 所有制品摘要与 manifest 一致；
4. 上述 13 个必需证据 ID 唯一、完整且全部为 `PASS`；
5. tag 尚不存在，且目标 commit 与候选 SHA 相同；
6. 工作树没有会改变发布内容的未提交修改。

Final Gate Report 只表示“技术门禁允许发布”，不等同于外部发布授权。门禁只给出“允许发布”或明确拒绝原因，不自动降低支持声明，不自动把失败项标记为实验性。

### 4.5 Publisher

Publisher 只在 Release Gate 成功后运行：

1. 再次显示版本、SHA、制品摘要和通过的支持矩阵；
2. 等待发布操作者对外部不可逆操作作最终确认；
3. 创建 annotated `v1.0.0` tag；
4. 推送 tag；
5. 创建 **draft** GitHub Release；
6. 上传四类制品、`SHA256SUMS`、候选身份 manifest、公开 Evidence Index、公开 Final Gate Report 和发布说明；
7. 重新读取远端 tag、draft Release 和附件并校验摘要；
8. 只有远端内容完整且一致时才把 draft 切换为公开 Release。

GitHub 凭据不得写入仓库、manifest、日志或证据包。

## 5. 验证矩阵

| 环境 | Web W1 | Desktop D1 | 安装/启动制品 |
|---|---|---|---|
| Ubuntu 24.04 | Chromium stable + Firefox stable | AppImage + deb | AppImage、deb |
| Fedora stable | Chromium stable + Firefox stable | AppImage + rpm | AppImage、rpm |
| Arch current | Chromium stable + Firefox stable | AppImage | AppImage |

候选冻结时，manifest 必须记录 Fedora 的精确版本、Arch 验证快照日期、Chromium 与 Firefox 的精确版本。对外支持声明使用上表的发行版通道；本次发布证据只证明 manifest 中冻结的具体版本。Ubuntu 固定为 24.04 LTS。

C1 至少执行两次：

- 一次使用最终 Web ZIP；
- 一次使用最终 Desktop 制品。

两次 C1 可以位于不同正式支持发行版，但必须使用同一候选提交的制品，并覆盖 demo 的代表性故事弧和两个结局中的至少一个。其他矩阵项不要求重复完整通关。

## 6. 行为评估

### 6.1 W1：WebGPU 浏览器可玩与 Web 存档

**示例：** 从 Web ZIP 启动游戏，在 Chromium 与 Firefox 中进入标题、开始游戏、推进到选择、存档、刷新页面、读档并切换语言。

**预期结果：**

- 标题、输入、选择、菜单、履历、设置和错误面板行为符合现有文档；
- `localStorage` 存档恢复场景、文本、变量、图层、UI 和音频状态；
- `en` 与 `zh-Hans-CN` 原子切换，无显示文本 fallback；
- rollback、补偿性 BGM 和 barrier 行为符合 Formal 1.0 契约；
- 缺失、空或损坏的 `game.msb` 显示生产错误且不进入 demo。负向包从最终 Web ZIP 按固定夹具规则派生，分别记录来源制品摘要、变换类型和派生包摘要；它们不是候选发行制品，也不会上传为正常游戏包。

**失败信号：** WebGPU adapter 申请失败、黑屏、输入路径失效、状态恢复不完整、语言切换部分生效、barrier 后发生逻辑或后端突变。

**不变量：** 浏览器验证使用最终 Web ZIP；Web 槽位键和存档格式不因发布工具改变。

**证据/oracle：** 可见 UI、控制台日志、localStorage 脱敏检查、候选和制品摘要。

### 6.2 D1：桌面完整退出持久化

**示例：** 使用目标格式安装或启动桌面包，保存槽位并修改偏好，彻底退出并确认无 MoonSight 进程，再次启动和读档。

**预期结果：**

- `prefs.json` 和 `saves/0.json` 位于预期 appData；
- 完整退出后数据仍存在；
- 重启后偏好与叙事状态正确恢复；
- 不遗留会覆盖有效数据的 `.tmp`；
- 若执行损坏夹具，last-good/backup 恢复行为与现有契约一致。

**失败信号：** 进程未退出、文件位置错误、保存后丢失、格式间使用不同存档语义、临时文件破坏有效存档。

**不变量：** Desktop SaveStore 仍由 appData 持久化，且不自动迁移 Web 槽位。

**证据/oracle：** 进程检查、脱敏 appData 列表和摘要、桌面日志、重启后的可见状态。

### 6.3 C1：代表性样章完成

**示例：** 从全新会话完整游玩 `demo/game`，实际使用选项、菜单存读、快捷存读、偏好、履历、本地化、rollback/barrier 和返回标题。

**预期结果：** 到达一个明确结局，无阻断性错误，期间产生的存档能恢复到预期剧情点。

**失败信号：** 无法完成故事弧、分支状态错误、必须使用调试捷径、存档导致剧情或呈现漂移、用户可见错误未被记录。

**不变量：** C1 使用候选发行包而非开发服务器或未打包源码路径。

**证据/oracle：** 结局、耗时、关键步骤截图/视频、日志和问题清单。

### 6.4 制品安装与启动

**示例：** Ubuntu 安装 deb、Fedora 安装 rpm、三发行版直接运行 AppImage。

**预期结果：** 安装或启动成功，应用身份和版本正确，可进入与 Web ZIP 相同的游戏内容。

**失败信号：** 缺失运行库、错误架构、包管理器拒绝、桌面入口错误、WebView/WebGPU 初始化失败。

**不变量：** 所有格式包含相同版本的 Web 游戏负载和 host wasm。

**证据/oracle：** 包管理器输出、应用版本、进程/窗口、内部关键制品摘要或等价包检查。

## 7. 自动化门禁

自动化门禁至少覆盖现有 Formal 1.0 矩阵：

- MoonBit format/check/test；
- native 与 wasm-gc 构建；
- Host 测试、类型检查和生产构建；
- CLI 正负 fixtures、`new`、`check`、`build`；
- package smoke 与资源完整性检查；
- 文档站类型检查和构建；
- Tauri Rust 检查/测试/构建；
- 可复现构建与 release evidence 校验工具测试。

自动化成功不能替代 W1、D1、C1。无真实 GPU 或 GUI 的 CI 不得生成伪造的人工 `PASS`。

### 7.1 可复现构建边界

可复现门禁不假定所有桌面容器文件逐字节相同：

- Web ZIP：使用规范化时间戳、顺序和权限后要求 ZIP SHA-256 一致；
- AppImage、deb、rpm：分别进行两次干净构建，解包并规范化允许变化的打包元数据后，要求应用负载、host wasm、`game.msb`、资源、版本和可执行内容摘要一致；
- 对打包器注入且无法稳定化的签名区、构建时间或容器元数据，必须列入版本化 normalization policy，禁止用宽泛目录排除隐藏产品负载差异；
- 最终候选制品是 manifest 明确标记的第一组构建输出；第二组只用于比较，不能混入 Release；
- oracle 是比较工具的结构化 `PASS`、两次构建环境记录和逐项摘要。任何未解释差异阻止发布。

## 8. 错误处理与候选失效

### 8.1 一般失败

任何失败都必须记录环境、步骤、日志和候选身份。修复提交后：

1. 旧候选保持历史状态，不覆盖其身份 manifest、Evidence Index 或 Final Gate Report；
2. 新提交获得新的候选编号；
3. 重新生成全部制品和 SHA-256；
4. 旧候选证据不得复用于新候选；
5. 完整自动化和人工矩阵从头执行。

### 8.2 环境能力失败

若某正式支持环境无法获得 WebGPU adapter 或满足运行依赖，结果仍是 `FAIL` 或 `BLOCKED`，并阻止 `v1.0.0`。不得在本轮自行将该环境降级为实验性；改变支持范围必须回到用户设计决策。

### 8.3 外部发布失败

- tag 创建成功但推送失败：保留本地事实，解决远端问题后核验 SHA，禁止重新指向其他提交；
- Release 创建失败：不改变 tag，重试创建同版本 draft Release；
- 附件上传不完整：Release 必须保持 draft，补齐并核验后再公开；
- 远端已存在冲突 tag/Release：停止并交由人工决定，不删除或移动公开历史。

## 9. 文档与发布说明

发布前同步：

- README 中的正式支持平台、浏览器和制品格式；
- `CHANGELOG.md` 的 Formal 1.0 摘要；
- `docs/release-1.0-verification.md` 在候选冻结前只记录流程、必需证据 ID、候选外部证据位置和当前阻塞状态；最终结果由 Release 附带的公开 Evidence Index 与 Final Gate Report 承载，避免修改已验证 tag 的源码；
- Web ZIP 的部署要求：HTTPS 或 localhost、WebGPU 必需；
- Linux 包的安装/运行方法和 appData 位置；
- Firefox 与 Chromium 均为正式支持，Windows/macOS 不在 1.0 支持范围；
- 已知非阻断问题，不得把失败门禁包装成已知限制。

## 10. 测试策略

1. 先测试 manifest、摘要比对和 release gate 的纯逻辑，包括缺项、错误 SHA、错误摘要和 `NOT RUN` 拒绝。
2. 用临时候选目录执行构建/打包 smoke，验证命名、内容和重复执行行为。
3. 在不触及远端的 dry-run 中验证 Publisher 将执行的 tag/Release 参数。
4. 执行完整自动化矩阵。
5. 冻结候选后执行真实 W1、D1、C1。
6. 发布前重新运行只读 gate，发布后核验远端 tag、Release 和附件摘要。

## 11. 发布顺序与停止条件

1. 更新版本与最终发布文档。
2. 在干净提交上运行完整自动化门禁。
3. 生成候选 manifest 和全部制品。
4. 完成 Ubuntu、Fedora、Arch 验证矩阵。
5. 完成 Web 与 Desktop C1。
6. 汇总证据并运行 Release Gate。
7. Gate 通过后，向发布操作者展示最终不可逆操作摘要。
8. 创建并推送 `v1.0.0` annotated tag。
9. 创建 draft GitHub Release 并上传制品。
10. 核验远端 SHA、附件和 SHA-256 后公开 Release，保存最终发布记录。

停止条件只有三种：

- 公开 Release 已核验完成；
- 用户取消发布；
- 出现必须由用户决定的支持范围变化、远端历史冲突或凭据/权限阻塞。

## 12. 设计约束与所有权

- 运行时继续拥有游戏行为、存档、本地化、回滚和错误语义。
- 现有构建脚本或新增发布工具只拥有构建、事实记录和门禁，不重新解释产品语义。
- `docs/release-1.0-verification.md` 与 candidate manifest 是发布证据契约；截图目录、脚本文件名和 CI job 名不是产品契约。
- 候选身份 manifest、Evidence Index、Final Gate Report 分别拥有独立 schema version；前者冻结构建身份，后两者冻结验证聚合与最终授权判定。
- Release Gate 不替代人工判断外部权限和远端冲突，但必须阻止证据不完整的正常发布路径。
- 不建立第二套发布状态数据库；Git、manifest、证据文件和 GitHub Release 是足够的事实源。
