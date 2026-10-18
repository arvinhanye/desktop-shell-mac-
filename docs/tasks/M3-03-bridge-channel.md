# M3-03: Bridge 回复通道、来源校验与 getConfig

- **状态**：review
- **里程碑**：M3
- **依赖**：M3-02（必须已合并到 `main`，手动验证要用它的自检面板）
- **分支**：task/M3-03

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

网页的 `postMessage` 能拿到 Swift 的回复；Swift 只接受 `shell://app` 主框架发来的消息；`getConfig` 返回配置、头像和背景列表、外观状态。在 `.app` 里，自检面板显示真实的配置和素材数量。

## 背景与约束

- 先读 `AGENTS.md`："Bridge 接口（白名单）"（含"通信方式"和"安全要求"）、配置文件示例、运行时素材目录。
- M2-05 审查时定下的要求：给 Bridge 加有实际作用的动作之前，先校验消息来源。本任务先把校验和回复通道做好，有副作用的动作在 M3-04 加。
- WKWebView 窗口相关的集成测试**不**正式纳入仓库（M2-03 遗留的问题，结论：继续用纯函数单元测试 + 交付记录里的临时检查 + 手动验证）。可以测试的逻辑都写成不依赖 AppKit 状态的纯函数。
- 日志一律用 `Log.notice` / `Log.error`，只写 action 名、id、数量和错误码，**不写提醒事项文字等用户内容**。
- 待办改为系统提醒事项（`AGENTS.md` 2026-10-17 改定），在 M3-07 实现；本任务只给项目配置加上 `remindersList` 字段，不碰 EventKit。

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
- `action` 不认识 → `unknown-action`。**白名单里 M3-04 才实现的动作**（`openProject`、`openProjectWith`、`launchApp`、`saveUiState`）、M3-07 才实现的动作（`addTodo`、`setTodoDone`），以及键盘焦点的两个动作（`focusInput`、`blurInput`，M3 之后再做）本任务也回复 `unknown-action`。
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

### 6. 项目的提醒事项列表（`Config.swift`）

- `AppConfig.Project` 增加可选字段 `remindersList: String?`（系统提醒事项里一个列表的名字，见 `AGENTS.md` 配置文件示例）。旧的配置文件没有这个字段，必须照常读取。
- `AppConfig.example` 里 `desktop-shell` 项目**不加**这个字段（用户还没有建对应的列表）。
- 本任务只读取这个字段、在 `getConfig` 里输出 `hasReminders`；按名字找列表在 M3-07 做。

### 7. `getConfig`

回复值（JSON 兼容的字典，由纯函数生成，例如 `ConfigReply` 结构体经 `JSONEncoder` → `JSONSerialization` 转换）：

```json
{
  "config": {
    "character": { "name": "爱弥斯" },
    "greetings": [ { "from": 0, "title": "深夜了", "wish": "…" } ],
    "projects": [ { "id": "desktop-shell", "name": "DesktopShell", "tags": ["dev"], "apps": ["cursor"], "hasReminders": false } ],
    "apps": [ { "id": "cursor", "name": "Cursor" } ]
  },
  "media": {
    "avatars": [ { "id": "1", "url": "/media/avatars/1.png" } ],
    "backgrounds": [ { "id": "folder-01", "url": "/media/backgrounds/folder-01.png" } ]
  },
  "uiState": { "avatarId": null, "backgroundId": null, "voiceEnabled": true }
}
```

- **不包含**：项目的 `path` 和 `remindersList`、应用的 `bundleId`、`background`、`desktopIconsHidden`。网页只需要 id 和显示用的名字。
- 项目的 `tags`、`apps` 在配置里缺失时输出空数组；`hasReminders` 为 `remindersList` 去掉首尾空白后是否非空。值为空的可选字段（`avatarId`、`backgroundId`）可以输出 `null`，也可以省略（网页两种都接受）。
- 每次调用都重新扫描 `media/avatars`、`media/backgrounds`（新放进去的素材重新加载页面就能看到）。
- 每次调用记录一行：`DesktopShell bridge: getConfig avatars=<数量> backgrounds=<数量>`。

### 8. 测试

- `BridgeTests.swift`：`isTrusted`（只有主框架 + `shell` + `app` 通过；子框架、`http`、`file`、`about`、`SHELL`、host 为 `evil` 或空都拒绝）；`parse`（非字典、缺 `action`、`action` 非字符串 → `invalid`；未知动作和 M3-04、M3-07 的动作 → `unknown-action`；`getConfig` 多带参数 → `invalid`；`setHitRegions` 多带参数 → `invalid`；合法的两种请求）；`getConfig` 回复（结构正确；整个回复里没有 `path`、`remindersList`、`bundleId`、`background`、`video`、`desktopIconsHidden`、`todos` 这些键；缺失的 `tags`、`apps` 输出空数组；`hasReminders` 对 `nil`、空字符串、纯空白、正常名字分别是 `false`、`false`、`false`、`true`）；带 `remindersList` 和不带它的配置都能被 `ConfigStore` 读取。
- `MediaLibraryTests.swift`：用临时目录放 `1.png`、`2.PNG`、`10.png`、`.hidden.png`、`CREDITS.txt`、名为 `dir.png` 的子目录、指向某个图片的符号链接、`bad name.png`、`a.png` + `a.jpg`，验证结果的顺序、`url` 和被跳过的项；目录不存在返回空数组。
- 所有测试只用临时目录，不碰真实的用户目录。

## 允许修改的文件

- `Sources/DesktopShell/Bridge.swift`（修改）
- `Sources/DesktopShell/BridgeProtocol.swift`（新建）
- `Sources/DesktopShell/WebContainer.swift`（修改）
- `Sources/DesktopShell/AppState.swift`（新建）
- `Sources/DesktopShell/MediaLibrary.swift`（新建）
- `Sources/DesktopShell/Config.swift`（修改：`Project.remindersList`）
- `Sources/DesktopShell/AppDelegate.swift`（修改：改用 `AppState`）
- `Sources/DesktopShell/ScreenManager.swift`、`Sources/DesktopShell/DesktopWindow.swift`（修改：传递 `AppState`）
- `Tests/DesktopShellTests/BridgeTests.swift`、`MediaLibraryTests.swift`（新建）、`ConfigStoreTests.swift`（修改：`remindersList` 读取）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不实现 `openProject`、`openProjectWith`、`launchApp`、`saveUiState`、`addTodo`、`setTodoDone`、`focusInput`、`blurInput`（回复 `unknown-action`）。不引入 EventKit。
- 不修改 `HitTesting`、`HitTestController`、`PowerMonitor`、`SchemeResolver`、`ShellSchemeHandler` 的逻辑。
- 不修改 `web/` 下的任何文件。
- 不删除、不移动任何文件。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过，包含上面列出的新测试；`scripts/test-web.sh` 仍然全部通过
- [ ] `git diff --name-only main...task/M3-03` 只包含"允许修改的文件"
- [ ] `grep -n "addScriptMessageHandler" Sources/DesktopShell/WebContainer.swift` 有输出；`grep -rn "\.add(WeakScriptMessageHandler" Sources/` 没有输出
- [ ] `grep -nE "isMainFrame|securityOrigin" Sources/DesktopShell/Bridge.swift` 有输出
- [ ] `grep -rnE "removeItem|moveItem|trashItem" Sources/` 没有输出
- [ ] `grep -rn "EventKit" Sources/` 没有输出
- [ ] `scripts/bundle.sh --open` 启动后，下面的命令能看到 `getConfig avatars=30 backgrounds=63`（数量以本机 `media/` 为准）：
  ```bash
  /usr/bin/log show --last 2m --style compact --predicate 'subsystem == "local.desktopshell.DesktopShell"' | grep getConfig
  ```

**用户手动验证**（`scripts/bundle.sh --open`）：

- [ ] 自检面板显示 `native`、`ready = true`、角色名"爱弥斯"、7 条问候、头像 30、背景 63；`ui` 的三个字段和 `ui.json` 一致
- [ ] 点项目和应用的按钮：结果栏显示"✗ …：unknown-action"（预期，M3-04 实现）
- [ ] 点"发送非法请求"：第 1 条 ✓；第 2–6 条显示 `unknown-action`（预期，这几个动作在 M3-04、M3-07 才实现）；**第 7 条（子框架）✓ `untrusted`**
- [ ] 提醒事项部分显示 `todosAccess = unknown`、0 条（预期，M3-07 实现）
- [ ] 点击穿透照常：面板可以点，空白处能选中访达图标
- [ ] 回归："隐藏桌面文件"切换后重启应用，状态保持；`ui.json` 里其他字段没有丢

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：从 `main` 的 `0c20fc1` 建立 `task/M3-03`；完成带回复通道、来源优先校验、严格请求解析、公开配置投影、素材扫描和共享 AppState 接线。未实现后续里程碑动作，未修改网页或指定保持原样的模块。
- **自测结果**：
  - **RED → GREEN** 旧配置模型读取 `remindersList` 的断言先失败；旧原生 Bridge 未返回 getConfig 数据。旧导航规则的原生 srcdoc 检查在 load 前超时；限定例外测试先对原规则产生 1 个断言失败，修正后通过。记录在 `/tmp/ds-m3-03-validation/`。
  - **PASS** `scripts/test.sh` **93/93**（11 suites）、`scripts/test-web.sh` **138/138**（0 fail / skip）；`swift build` 零 warning/error。首次沙盒测试因正常编译缓存写入受限未执行到断言，按权限流程重跑后通过，未修改工具链设置。
  - **PASS** 临时原生 WKWebView 检查 **39/39**：真实公开配置回复、参数错误、延期动作、点击区域裁剪和清空、素材重扫、多页面共用 AppState、外观持久化、移除处理器、弱引用释放、目标释放后的 failed 回复、每条拦截消息恰好一次回复、错误 host 主框架及 srcdoc 子框架返回 untrusted。实际自检面板按钮的 7 条请求全部完成：第 1 条及第 7 条 ✓，第 2–6 条按当前里程碑返回 unknown-action。此前隔离执行的 1 项 SKIP 已由完整检查覆盖，不作为最终通过依据。
  - **PASS** `scripts/bundle.sh --open` release 编译、固定证书签名和严格签名校验通过；指定要求仍绑定证书 `7d0b2eb5…62ce`。用户在本机允许钥匙串访问后，正式 `.app` 启动。应用 PID 8661 在 `2026-10-17 23:32:51` 输出 `getConfig avatars=30 backgrounds=63`；日志为 `/tmp/ds-m3-03-validation/app-getConfig.log`，应用为 `/Users/arvinhan/Desktop/desktop-shell/build/DesktopShell.app`。
  - **PASS** handler 注册/来源校验 grep 命中；旧注册方式、删除/移动 API 和 EventKit 检查无输出；共 13 个变更文件均在允许范围，网页、AGENTS.md、任务需求区及审查区未变，`git diff --check` 通过。
  - **PASS** 内部只读复核未发现 Critical / Important / Minor 代码问题；不替代 Claude Code 的正式审查与合并。
- **用户手动验证待办**：
  - 已启动的正式应用里确认 `native`、`ready = true`、爱弥斯、7 条问候、头像 30、背景 63，UI 三字段与 `ui.json` 一致；提醒事项为 unknown / 0 条。
  - 点项目、应用按钮与“发送非法请求”，核对任务验收区的预期结果，尤其第 7 条 `✓ untrusted`。
  - 面板可点、空白处可选中访达图标；切换“隐藏桌面文件”并重启，确认状态保持且其他 UI 字段未丢。临时原生测试不等同于这些实际 GUI 验收。
- **疑问 / 偏离**：用户已明确允许限定导航例外。`WebNavigationPolicy` 仅在目标 URL 精确等于 `about:srcdoc`、目标明确为子框架、来源 scheme/host 精确为 `shell`/`app` 时放行；现有 shell 导航规则及其他 URL / 主框架限制保持原样，Bridge 仍对全部子框架回复 untrusted。网页文件未变，无未决接口问题。
- **提交 / 发布**：交付保留在 `task/M3-03`，正式审查与合并由 Claude Code 完成；未推送远端。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
