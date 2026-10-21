# M7-01: 增删项目（Swift：核对路径、改写配置、Bridge 动作）

- **状态**：todo
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
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
