# M3-03: Bridge 回复通道、来源校验与 getConfig

- **状态**：todo
- **里程碑**：M3
- **依赖**：M3-02（必须已合并到 `main`，手动验证要用它的自检面板）
- **分支**：task/M3-03

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

网页的 `postMessage` 能拿到 Swift 的回复；Swift 只接受 `shell://app` 主框架发来的消息；`getConfig` 返回配置、头像和背景列表、外观状态和待办。在 `.app` 里，自检面板显示真实的配置和素材数量。

## 背景与约束

- 先读 `AGENTS.md`："Bridge 接口（白名单）"（含"通信方式"和"安全要求"）、配置文件示例、运行时素材目录。
- M2-05 审查时定下的要求：给 Bridge 加有实际作用的动作之前，先校验消息来源。本任务先把校验和回复通道做好，有副作用的动作在 M3-04 加。
- WKWebView 窗口相关的集成测试**不**正式纳入仓库（M2-03 遗留的问题，结论：继续用纯函数单元测试 + 交付记录里的临时检查 + 手动验证）。可以测试的逻辑都写成不依赖 AppKit 状态的纯函数。
- 日志一律用 `Log.notice` / `Log.error`，只写 action 名、id、数量和错误码，**不写待办文字等用户内容**。

### 1. 回复通道（`WebContainer.swift`、`Bridge.swift`）

- 改用 `WKScriptMessageHandlerWithReply`：用 `userContentController.addScriptMessageHandler(_:contentWorld: .page, name: "shell")` 注册；`stop()` 里用 `removeScriptMessageHandler(forName: "shell", contentWorld: .page)` 移除。`WeakScriptMessageHandler` 代理也改为实现带回复的协议，仍然弱引用 `Bridge`。
- 实现带 `replyHandler` 的方法或 `async` 的方法都可以，但**每条消息必须且只能回复一次**：成功 `replyHandler(值, nil)`，失败 `replyHandler(nil, 错误码)`。没有回复值的动作回复 `nil`。
- 错误码只用这五个：`untrusted`、`invalid`、`unknown-action`、`not-found`、`failed`（含义见 `AGENTS.md`）。
- 每次拒绝记录一行：`DesktopShell bridge: <action 或 ?> rejected: <错误码>`，后面可以附简短原因（不含用户内容）。
- `Bridge` 需要读配置和状态，构造时传入 `AppState`（见第 4 节）。

### 2. 来源校验（新建 `BridgeProtocol.swift`，纯函数）

```swift
enum BridgeOrigin {
    static func isTrusted(isMainFrame: Bool, scheme: String, host: String) -> Bool
}
```

- 只有 `isMainFrame == true`、`scheme == "shell"`、`host == "app"`（完全相等，区分大小写）时为 `true`。
- `Bridge` 收到消息后**先校验来源**（`message.frameInfo.isMainFrame`、`message.frameInfo.securityOrigin.protocol`、`.host`），不通过就回复 `untrusted`，不再解析内容。

### 3. 请求解析（`BridgeProtocol.swift`，纯函数）

```swift
enum BridgeError: String, Error { case untrusted, invalid, unknownAction = "unknown-action", notFound = "not-found", failed }
enum BridgeRequest: Equatable {
    case getConfig
    case setHitRegions(...)   // 关联值的形式自定，坐标校验仍由 HitTesting.parseRegions 负责
    static func parse(_ body: Any) -> Result<BridgeRequest, BridgeError>
}
```

- `body` 不是字典、没有 `action`、`action` 不是字符串 → `invalid`。
- `action` 不认识 → `unknown-action`。**白名单里 M3-04 才实现的动作**（`openProject`、`openProjectWith`、`launchApp`、`saveTodos`、`saveUiState`）和键盘焦点的两个动作（`focusInput`、`blurInput`，M3 之后再做）本任务也回复 `unknown-action`。
- **除 `action` 外只允许该动作列出的参数**，多出任何键 → `invalid`。`getConfig` 没有参数；`setHitRegions` 只有 `regions`。
- `setHitRegions`：行为与现在一致（`HitTesting.parseRegions` 失败 → `invalid`），成功回复 `nil`。

### 4. `AppState.swift`（新建）

把现在散在 `AppDelegate` 里的配置和外观状态收拢到一处，`AppDelegate` 和 `Bridge` 共用同一个实例（避免网页保存外观和菜单栏切换互相覆盖）：

```swift
@MainActor
final class AppState {
    let paths: AppPaths
    private(set) var config: AppConfig
    var uiState: UiState
    let uiStateStore: UiStateStore
    let todoStore: TodoStore
    init(paths: AppPaths)         // 读取 config.json（失败时用 AppConfig.example 并记录日志，沿用现在 AppDelegate 的逻辑）和 ui.json
    func saveUiState() throws     // 保存当前 uiState
}
```

- `AppDelegate`：去掉自己的 `uiState`、`uiStateStore` 和配置加载，改用 `AppState`；"隐藏桌面文件"的行为（切换、保存、失败只记日志）完全不变。
- `ScreenManager`、`WidgetWindow`、`WebContainer` 把 `AppState` 一路传给 `Bridge`（替代现在传的 `AppPaths`，路径从 `appState.paths` 取）。

### 5. 素材列表（新建 `MediaLibrary.swift`，纯函数）

```swift
struct MediaItem: Codable, Equatable { let id: String; let url: String }
enum MediaLibrary {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]
    static func scan(mediaDir: URL, subdirectory: String) -> [MediaItem]
}
```

- 只看 `mediaDir/subdirectory` 这一层。跳过：目录、符号链接、以 `.` 开头的文件、扩展名（不区分大小写）不在 `imageExtensions` 里的文件（例如 `CREDITS.txt`）、去掉扩展名后不满足 `isValidID` 的文件（记录日志）。
- 同一个 id 有多个文件（例如 `a.png` 和 `a.jpg`）：按文件名排序后保留第一个，记录日志。
- 按 id 用 `localizedStandardCompare` 排序（`1, 2, …, 10`，和访达一致）。
- `url` 为 `/media/<subdirectory>/<文件名>`（文件名原样，含扩展名）。
- 目录不存在 → 空数组。

### 6. 待办存储（新建 `TodoStore.swift`）

```swift
struct Todo: Codable, Equatable { var id: String; var text: String; var done: Bool; var projectId: String? }
extension Todo { static func isValidList(_ todos: [Todo]) -> Bool }
struct TodoStore {
    let supportDir: URL
    func load() -> [Todo]          // 不抛错
    func save(_ todos: [Todo]) throws
}
```

- 校验规则（`isValidList`，M3-04 的 `saveTodos` 也用它）：最多 500 条；`id` 满足 `isValidID`、UTF-8 不超过 64 字节、列表内不重复；`text` 去掉首尾空白后不为空、不超过 500 个字符（按 `Character` 计）；`projectId` 为 `nil` 或满足 `isValidID`（**不要求**在配置里存在）。
- 文件是 `supportDir/todos.json`，顶层是 JSON 数组。
- `load()`：文件不存在 → `[]`；JSON 损坏、结构不对或者不满足 `isValidList` → `Log.error`（只写路径和错误，不写内容），**把原文件复制一份**为同目录下的 `todos.corrupt.json`（这个备份已经存在时不覆盖），返回 `[]`。原文件保持不动（项目规定不做删除或移动文件的功能）。复制失败只记录日志。
- `save`：创建 `supportDir`（含中间目录），`prettyPrinted` + `sortedKeys` + `withoutEscapingSlashes`，`.atomic` 写入。`save` 本身不校验，由调用方负责。

### 7. `getConfig`

回复值（JSON 兼容的字典，由纯函数生成，例如 `ConfigReply` 结构体经 `JSONEncoder` → `JSONSerialization` 转换）：

```json
{
  "config": {
    "character": { "name": "爱弥斯" },
    "greetings": [ { "from": 0, "title": "深夜了", "wish": "…" } ],
    "projects": [ { "id": "desktop-shell", "name": "DesktopShell", "tags": ["dev"], "apps": ["cursor"] } ],
    "apps": [ { "id": "cursor", "name": "Cursor" } ]
  },
  "media": {
    "avatars": [ { "id": "1", "url": "/media/avatars/1.png" } ],
    "backgrounds": [ { "id": "folder-01", "url": "/media/backgrounds/folder-01.png" } ]
  },
  "uiState": { "avatarId": null, "backgroundId": null, "voiceEnabled": true },
  "todos": [ { "id": "t1", "text": "…", "done": false, "projectId": "desktop-shell" } ]
}
```

- **不包含**：项目的 `path`、应用的 `bundleId`、`background`、`desktopIconsHidden`。网页只需要 id 和显示用的名字。
- 项目的 `tags`、`apps` 在配置里缺失时输出空数组。值为空的可选字段（`avatarId`、`backgroundId`、`projectId`）可以输出 `null`，也可以省略（网页两种都接受）。
- 每次调用都重新扫描 `media/avatars`、`media/backgrounds` 并读取 `todos.json`（新放进去的素材重新加载页面就能看到）。
- 每次调用记录一行：`DesktopShell bridge: getConfig avatars=<数量> backgrounds=<数量> todos=<数量>`。

### 8. 测试

- `BridgeTests.swift`：`isTrusted`（只有主框架 + `shell` + `app` 通过；子框架、`http`、`file`、`about`、`SHELL`、host 为 `evil` 或空都拒绝）；`parse`（非字典、缺 `action`、`action` 非字符串 → `invalid`；未知动作和 M3-04 的动作 → `unknown-action`；`getConfig` 多带参数 → `invalid`；`setHitRegions` 多带参数 → `invalid`；合法的两种请求）；`getConfig` 回复（结构正确；整个回复里没有 `path`、`bundleId`、`background`、`video`、`desktopIconsHidden` 这些键；缺失的 `tags`、`apps` 输出空数组）。
- `MediaLibraryTests.swift`：用临时目录放 `1.png`、`2.PNG`、`10.png`、`.hidden.png`、`CREDITS.txt`、名为 `dir.png` 的子目录、指向某个图片的符号链接、`bad name.png`、`a.png` + `a.jpg`，验证结果的顺序、`url` 和被跳过的项；目录不存在返回空数组。
- `TodoStoreTests.swift`：文件不存在；读写往返；输出格式（排序键、缩进）；`save` 能创建不存在的目录；JSON 损坏 → 返回空数组、原文件内容不变、生成内容相同的 `todos.corrupt.json`；备份已存在时不覆盖；`isValidList` 的各条规则（501 条、重复 id、非法 id、65 字节 id、空白文本、501 个字符、非法 `projectId`）各至少一例，以及刚好在上限（500 条、64 字节、500 个字符）时通过。
- 所有测试只用临时目录，不碰真实的用户目录。

## 允许修改的文件

- `Sources/DesktopShell/Bridge.swift`（修改）
- `Sources/DesktopShell/BridgeProtocol.swift`（新建）
- `Sources/DesktopShell/WebContainer.swift`（修改）
- `Sources/DesktopShell/AppState.swift`（新建）
- `Sources/DesktopShell/MediaLibrary.swift`（新建）
- `Sources/DesktopShell/TodoStore.swift`（新建）
- `Sources/DesktopShell/AppDelegate.swift`（修改：改用 `AppState`）
- `Sources/DesktopShell/ScreenManager.swift`、`Sources/DesktopShell/DesktopWindow.swift`（修改：传递 `AppState`）
- `Tests/DesktopShellTests/BridgeTests.swift`、`MediaLibraryTests.swift`、`TodoStoreTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不实现 `openProject`、`openProjectWith`、`launchApp`、`saveTodos`、`saveUiState`、`focusInput`、`blurInput`（回复 `unknown-action`）。
- 不修改 `HitTesting`、`HitTestController`、`PowerMonitor`、`SchemeResolver`、`ShellSchemeHandler` 的逻辑。
- 不修改 `web/` 下的任何文件。
- 不删除、不移动任何文件（`todos.json` 损坏时只复制备份）。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过，包含上面列出的新测试；`scripts/test-web.sh` 仍然全部通过
- [ ] `git diff --name-only main...task/M3-03` 只包含"允许修改的文件"
- [ ] `grep -n "addScriptMessageHandler" Sources/DesktopShell/WebContainer.swift` 有输出；`grep -rn "\.add(WeakScriptMessageHandler" Sources/` 没有输出
- [ ] `grep -nE "isMainFrame|securityOrigin" Sources/DesktopShell/Bridge.swift` 有输出
- [ ] `grep -rnE "removeItem|moveItem|trashItem" Sources/` 没有输出
- [ ] `scripts/bundle.sh --open` 启动后，下面的命令能看到 `getConfig avatars=30 backgrounds=63 todos=<数量>`（数量以本机 `media/` 为准）：
  ```bash
  /usr/bin/log show --last 2m --style compact --predicate 'subsystem == "local.desktopshell.DesktopShell"' | grep getConfig
  ```

**用户手动验证**（`scripts/bundle.sh --open`）：

- [ ] 自检面板显示 `native`、`ready = true`、角色名"爱弥斯"、7 条问候、头像 30、背景 63；`ui` 的三个字段和 `ui.json` 一致
- [ ] 点项目和应用的按钮：结果栏显示"✗ …：unknown-action"（预期，M3-04 实现）
- [ ] 点"发送非法请求"：第 1 条 ✓；第 2–5 条显示 `unknown-action`（预期，这几个动作 M3-04 才实现，之后应全部 ✓）；**第 6 条（子框架）✓ `untrusted`**
- [ ] 点击穿透照常：面板可以点，空白处能选中访达图标
- [ ] 回归："隐藏桌面文件"切换后重启应用，状态保持；`ui.json` 里其他字段没有丢

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
