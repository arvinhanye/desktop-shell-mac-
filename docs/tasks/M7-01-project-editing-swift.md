# M7-01: 增删项目（Swift：核对路径、改写配置、Bridge 动作）

- **状态**：review
- **里程碑**：M7
- **依赖**：无（M6 已合并）。和 M7-02 互不依赖（M7-02 用 mock 开发），可以先做任意一个；M7-03 依赖本任务和 M7-02
- **分支**：task/M7-01

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

Swift 端支持两个新的 Bridge 动作：`addProject`（按路径把一个文件夹加成项目）和 `removeProject`（从配置里去掉一个项目），改写 `config.json` 后向所有页面推送 `config`，提醒事项按新的对应关系重新推送。拖入（M7-03）会复用这里的"添加"函数。

## 背景与约束

- 先读 AGENTS.md 里标着 M7 的部分：
  - "配置文件示例"的"在桌面上增删项目"：改写规则、id 生成、新项目的默认值。
  - "Bridge 接口"：
    - `addProject` / `removeProject` 两行；
    - 错误码多了 `not-directory`、`outside-home`、`duplicate`；
    - 推送事件 `config`；
    - "安全要求"里 `addProject` 的例外。
  - "不要做的事"：移除只改配置，不碰文件夹。
- 现在 `ConfigStore.load()` 会过滤非法 id、排序问候语，注释写着"不改写已有配置"。改写配置时**不能用过滤过的结果写回**，否则会把用户手写的、被过滤掉的项目和顺序弄丢。所以要另写一个"原样读出、只改 `projects`、写回"的路径。
- 新项目的 `apps` 是 `["cursor"]`。如果配置的 `apps` 里没有 `cursor`，就写成空数组。用户 2026-10-21 定。

### 1. 纯函数（新建 `Sources/DesktopShell/ProjectEditing.swift`）

```swift
enum ProjectEditing {
    enum AddError: Error, Equatable { case notFound, notDirectory, outsideHome, duplicate }
    /// 把用户给的路径解析成真实文件夹：展开 ~、标准化、解析符号链接，再按顺序核对
    /// 存在 → 是文件夹 → 在 home 里且不是 home 本身 → 不和 existing 里任何一项（同样解析后）重复。
    /// fileExists / isDirectory 通过参数注入，测试里不碰真实磁盘。
    static func resolve(_ input: String, home: URL, existing: [String], fileSystem: ProjectFileSystem) -> Result<URL, AddError>
    /// home 里的路径写成 "~/…"，否则原样
    static func storedPath(_ url: URL, home: URL) -> String
    /// 见 AGENTS.md：ASCII 字母数字转小写，其余变 "-"，合并、去首尾；空就用 "project"；重复加 -2、-3…
    static func makeID(name: String, existing: Set<String>) -> String
    /// 新项目：name 是文件夹名，tags 为空，apps 按 config.apps 里有没有 cursor 决定，没有 remindersList
    static func newProject(folder: URL, home: URL, config: AppConfig) -> AppConfig.Project
}
```

- `ProjectFileSystem` 是一个小协议（`exists(_:)`、`isDirectory(_:)`、`resolvingSymlinks(_:)`），真实实现用 `FileManager` 和 `URL.resolvingSymlinksInPath()`。
- 判断"在 home 里"：用解析后的路径按路径组件比较，**不用字符串前缀**。`/Users/arvinhan2` 不能算在 `/Users/arvinhan` 里。

### 2. 读写配置（`ConfigStore.swift`）

- 新增 `func loadUnfiltered() throws -> AppConfig`：只解码，不过滤、不排序；文件不存在就抛错，**不生成示例配置**。
- 新增 `func save(_ config: AppConfig) throws`：编码设置和首次生成示例时一样（`prettyPrinted`、`sortedKeys`、`withoutEscapingSlashes`），`.atomic` 写入。
- `load()` 的行为不变。

### 3. 增删（`AppState.swift`）

- `func addProject(path: String) -> Result<AppConfig.Project, BridgeError>`：
  1. 用 `loadUnfiltered()` 从磁盘读最新配置，读不出来 → `failed`，不写文件。
  2. 用 `ProjectEditing.resolve` 核对，`existing` 是配置里**所有**项目的 `path`。
  3. 生成新项目、追加到 `projects` 末尾，`save`。写失败 → `failed`。
  4. 成功后：
     - 重新用 `load()` 读一遍，更新内存里的 `config`，这样启动时的过滤规则照样生效；
     - 调用 `remindersStore?.configDidReload()`；
     - 通过新的回调 `onConfigChanged` 通知外面推送 `config`。
- `func removeProject(id: String) -> Result<Void, BridgeError>`：同样先读磁盘；找不到这个 id → `not-found`；去掉后 `save`，后续步骤同上。**不对磁盘上的文件夹做任何操作。**
- 日志：
  - 添加成功：`DesktopShell project: added id=<id> path=<存储的路径>`；
  - 移除成功：`DesktopShell project: removed id=<id>`；
  - 失败：`DesktopShell project: add rejected code=<错误码>` / `remove rejected code=<错误码>`；
  - 被拒时不写用户输入的路径。

### 4. Bridge（`BridgeProtocol.swift`、`Bridge.swift`、`AppDelegate.swift`）

- `BridgeError` 加 `notDirectory = "not-directory"`、`outsideHome = "outside-home"`、`duplicate`，`ProjectEditing.AddError` 映射到这几个，以及 `not-found`。
- `BridgeRequest` 加 `.addProject(path: String)` 和 `.removeProject(String)`，解析规则：
  - `addProject` 只允许 `path` 一个参数，非空字符串、最多 1024 个字符，否则 `invalid`；
  - `removeProject` 只允许 `projectId`，id 规则同其他动作。
- `addProject` 成功时回复新项目，格式和 `getConfig` 回复里 `config.projects` 的一项完全一样（`id`、`name`、`tags`、`apps`、`hasReminders`），不含路径。可以从 `ConfigReply.make` 里把"一个项目怎么转成字典"提出来复用。
- `removeProject` 成功时回复 `null`。
- 新增 `PageEvent.config(...)`：`{event: "config", config: <同 getConfig 回复里的 config>}`。应用图标的 `iconUrl` 要和 `getConfig` 一致，用 `appState.withAppIcons` 拿到图标 id。
- `AppDelegate`：`appState.onConfigChanged` 接到 `manager.broadcast(PageEvent.config(...))`。`config` **不加进** `PageEventCache` 的重推列表：页面重新加载时 `getConfig` 本来就会拿到最新配置。

### 5. 测试

- `Tests/DesktopShellTests/ProjectEditingTests.swift`（新建），用假的文件系统：
  - `resolve`：
    - `~` 展开；`/Users/<me>/x/..` 标准化；
    - 符号链接解析后落在 home 外 → `outsideHome`；
    - home 本身 → `outsideHome`；
    - `/Users/<me>2/x` → `outsideHome`；
    - 不存在 → `notFound`；是文件不是文件夹 → `notDirectory`；
    - 和已有的 `~/a`、`/Users/<me>/a/` 重复 → `duplicate`；
    - 核对顺序和第 1 节一致。
  - `storedPath`：home 里的写成 `~/…`，home 外的原样。
  - `makeID`：
    - `"CS61A-master"` → `cs61a-master`；
    - `"My App"` → `my-app`；
    - `"操作系统原理实验"` → `project`；
    - `"--a__b--"` → `a-b`（`_` 也按"其余字符"变成 `-`）；
    - 和已有 id 重复依次得到 `-2`、`-3`。
  - `newProject`：配置里有 `cursor` 和没有时的 `apps`；`tags` 为空；没有 `remindersList`。
- `ConfigStore`：`loadUnfiltered` 保留非法 id 的项目和原始顺序；`save` 再 `loadUnfiltered` 得到相同的值；`save` 用的是原子写入（临时目录里测）。
- `BridgeTests`：
  - `addProject` 和 `removeProject` 的合法、非法参数（多余的键、空路径、超长路径、非法 id）；
  - 新错误码的字符串值。
- `PageEventTests`：`config` 事件的键；项目里不含 `path`；能被 `JSONSerialization` 接受；`PageEventCache` 不缓存它。
- `AppState` 的增删流程不强求单元测试（要真实目录和文件）。如果写，就用临时目录，不碰用户真实的 `~/Library/Application Support/DesktopShell`。

## 允许修改的文件

- `Sources/DesktopShell/ProjectEditing.swift`（新建）
- `Sources/DesktopShell/ConfigStore.swift`、`Sources/DesktopShell/AppState.swift`、`Sources/DesktopShell/BridgeProtocol.swift`、`Sources/DesktopShell/Bridge.swift`、`Sources/DesktopShell/AppDelegate.swift`（修改）
- `Tests/DesktopShellTests/ProjectEditingTests.swift`（新建）
- `Tests/DesktopShellTests/ConfigStoreTests.swift`、`Tests/DesktopShellTests/BridgeTests.swift`、`Tests/DesktopShellTests/PageEventTests.swift`（修改）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"：不删除、不移动、不创建任何文件夹，`removeProject` 只改 `config.json`。
- 不改网页（M7-02）、不做拖入（M7-03）。
- 不改 `load()` 的过滤规则，不在启动时改写配置。
- 测试和自测都不碰用户真实的配置目录；手动验证由用户在打包的应用里做。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build` 无错误、无警告
- [ ] `scripts/test.sh` 全部通过，包括第 5 节的测试
- [ ] `scripts/test-web.sh` 全部通过（网页没改）
- [ ] `scripts/bundle.sh` 成功
- [ ] `git diff --name-only main...task/M7-01` 只有上面"允许修改的文件"

**用户手动验证**：网页的输入框在 M7-02 才有。本任务的桌面验证并到 M7-02 合并后一起做：Claude Code 先备份 `config.json`，再用应用实际增删一次，对照日志和文件内容。本任务只需要确认：打包启动后桌面一切照旧，日志里没有新的错误。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
  - 从最新 `main`（`922684e`，已 fetch 确认与 `origin/main` 一致）建立 `task/M7-01`。
  - 新增 `ProjectEditing` 与可注入文件系统：展开 `~`、标准化、解析链接，依次核对存在 / 文件夹 / home 内部 / 重复；按路径组件比较边界；生成唯一 ASCII id 与新项目默认值。
  - `ConfigStore.loadUnfiltered()` 原样解码，`save()` 以既定格式原子写入；保留启动时过滤和排序行为。增删每次读取磁盘最新配置，只修改一个项目；成功后更新内存、通知提醒事项重映射并广播公共 `config`。
  - 接入 `addProject` / `removeProject`、固定错误码、共享公共项目与配置投影；回复和事件不含路径等私有字段，图标 id 经 `withAppIcons` 获取，`config` 不进入重载缓存。
  - 未改网页、拖入逻辑、设计定稿、AGENTS.md 或 CLAUDE.md；未启动应用，未操作真实配置、提醒事项或登录项。
- **自测结果**：
  - **RED**：实现前完整 Swift 套件运行 226 项，原有 225 项通过；新增 `projectEditingRequestsRecognized` 的两条合法动作均因 `unknown-action` 失败。随后新增路径 / 配置 / 事件 / 持久化测试在所需 API 缺失时编译失败，与首轮行为 RED 分开记录。
  - **PASS Swift**：`scripts/test.sh` 最终 248/248（26 suites）；覆盖路径边界和链接、校验顺序、默认值和 id 冲突、未过滤读写、外部配置变动、失败保留、重复检测、移除后目录内容不变、通知时机及真实 `RemindersStore` 搭配内存后端的增删重映射。
  - **PASS 原子写入**：临时目录的旧硬链接仍保留旧字节，配置文件已换为新 JSON；验证是替换文件而非原地截断；写入失败保留内容。
  - **PASS web**：`scripts/test-web.sh` 421/421，0 failed / skipped。
  - **PASS build**：`swift build` 无编译错误、无警告。
  - **PASS bundle**：`scripts/bundle.sh` release 成功；`/Users/arvinhan/Desktop/desktop-shell/build/DesktopShell.app` 已生成；最终路径 `codesign --verify --strict --verbose=2` 和 `plutil -lint` 通过，指定要求仍绑定 `DesktopShell Self-Signed` 证书。
  - **PASS 范围 / 格式**：`git diff --check` 通过；11 个改动文件均在允许清单内，任务需求与审查记录保持原样。最终提交范围限定为这些文件，提交后复核 `main...task/M7-01`。
  - **环境说明**：初次沙盒测试在 Swift/Clang 缓存写入阶段失败，尚未执行测试；经权限流程原样重跑后通过，未更改工具链或检查规则。沙盒内单独签名复验返回 `CSSMERR_TP_NOT_TRUSTED`，在打包所用的相同权限环境复验通过，未改证书信任设置。
  - **PASS 独立复核**：子代理只读覆盖全部 11/11 文件，未发现确定缺陷；OCR 仅用 delegate preview/rule，不调用外部 LLM。临时目录独立 Swift 探针确认大小写不同的同一文件夹规范化后返回 `duplicate`，3/3 通过；未启动应用或接触真实数据。该复核不替代 Claude 正式审查。
  - **SKIP 实机**：未启动打包应用，因此“桌面照旧、启动无新错误”待用户检查；实际输入框增删、跨页面更新和真实提醒事项联动按任务安排留到 M7-02 合并后，先备份配置再验证。自动化测试只使用临时目录或内存后端。
- **疑问 / 偏离**：
  - **推送授权已确认**：首次推送被自动权限审查拦下后，用户于 2026-10-21 明确确认该仓库归其所有，并允许推送 `task/M7-01`，不合并 `main`。本次交付仅推送到 `origin`（`https://github.com/arvinhanye/desktop-shell-mac-.git`）的同名任务分支；不推送或合并 `main`。
  - 无需求或允许文件范围偏离。为隔离集成测试，`AppState` 初始化增加 `projectHome` 可注入参数，默认仍为当前用户 home；不新增配置项或 Bridge 接口。
  - 额外将含 NUL 的路径归为 `not-found`，避免底层文件 API 截断后指向另一个文件夹；其余输入不擅自修剪，路径长度仍按任务要求的字符数校验。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
