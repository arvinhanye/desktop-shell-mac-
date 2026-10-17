# M3-07: 接入系统提醒事项（权限、读取、勾选、新增、变化推送）

- **状态**：todo
- **里程碑**：M3
- **依赖**：M3-06（必须已合并到 `main`；用到 M3-05 的广播和重推）
- **分支**：task/M3-07

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

桌面页面收到系统"提醒事项"里的待办（所有列表的未完成提醒，加上今天完成的），可以勾选、取消勾选、新增；在 iPhone 或 Mac 的"提醒事项"里改动后，桌面自动更新。第一次启动时弹出权限框，之后不再询问。在 `.app` 里用自检面板就能验证。

## 背景与约束

- 先读 `AGENTS.md`：技术选型里的"提醒事项"、**技术探针里的"系统提醒事项探针"**（实测结论，本任务照着做）、Bridge 的 `addTodo` / `setTodoDone` 和推送事件 `todos`、组件清单第 4 条、配置文件示例里的 `remindersList`、"不要做的事"（**不删除提醒事项**）。
- 探针结论里和实现直接相关的几点：
  - `requestFullAccessToReminders` 不阻塞主线程，但**回调在后台线程**，回到主线程再处理；`fetchReminders(matching:)` 的回调同样在后台线程。
  - `EKEventStoreChanged` 常常连着来 2 次，第一次时数据可能还没变，所以要**防抖**：收到后等 0.5 秒（期间再收到就重新计时），再整体重新读取。通知的 `userInfo` 不用看。
  - iPhone 改动同步到 Mac 的时间由系统决定（实测约 1 分钟，有一次 8 分钟没到）。用 `refreshSourcesIfNecessary()` 主动请求同步，并在验收时实测。
  - 提醒的 `calendarItemIdentifier` 和列表的 `calendarIdentifier` 是 UUID，满足 `isValidID`，重启后不变。
- 日志只写数量、项目 id、错误码和状态，**不写提醒标题和列表名**。
- 一个应用只用**一个** `EKEventStore`。

### 1. `Info.plist`（`scripts/bundle.sh`）

- 增加 `NSRemindersFullAccessUsageDescription`：`DesktopShell 在桌面上显示和勾选你的提醒事项，并把在桌面上新增的提醒写进提醒事项；不会删除任何提醒。`

### 2. 纯函数（新建 `TodoItems.swift`，不依赖 EventKit）

```swift
struct ReminderSnapshot: Equatable {          // 从 EKReminder 抄出来的值，方便测试
    var id: String                            // calendarItemIdentifier
    var title: String
    var isCompleted: Bool
    var completionDate: Date?
    var creationDate: Date?
    var due: DateComponents?                  // dueDateComponents
    var listId: String                        // calendar.calendarIdentifier
}
struct TodoItem: Equatable {
    struct Due: Equatable { var date: String; var time: String? }   // "2026-10-18"、"09:00"
    var id: String; var text: String; var done: Bool; var projectId: String?; var due: Due?
}
enum TodoItems {
    static func listToProject(projects: [AppConfig.Project], lists: [(id: String, title: String)]) -> [String: String]
    static func due(_ components: DateComponents?) -> TodoItem.Due?
    static func make(_ reminders: [ReminderSnapshot], listToProject: [String: String], now: Date, calendar: Calendar) -> [TodoItem]
}
```

- **`listToProject`**（列表 id → 项目 id）：项目的 `remindersList` 去掉首尾空白后为空就跳过；按标题**完全相等**匹配列表。找不到 → 跳过并记录日志（只写项目 id）；同名列表有多个 → 按列表 id 排序取第一个并记录日志；两个项目配了同一个列表 → 按配置顺序第一个项目生效并记录日志。
- **`due`**：`year`、`month`、`day` 都有时 `date` 为补零的 `YYYY-MM-DD`，否则返回 `nil`；`hour`、`minute` 都有时 `time` 为补零的 `HH:mm`，否则 `time` 为 `nil`。按组件原样格式化，不做时区换算。
- **`make`**：
  - 保留未完成的提醒，以及 `completionDate` 和 `now` 在 `calendar` 里是同一天的已完成提醒；其他已完成的丢掉。
  - 排序：未完成的在前，按到期时间从早到晚（带时间的按那个时刻；只有日期的按那天的结束；没有到期时间的排最后），相同时再按 `creationDate`、再按 `id`；今天完成的排在后面，按 `completionDate` 从晚到早。
  - `text` 为标题原样（可以为空字符串）；`projectId` 从 `listToProject` 查；最多 500 条，超出时截断并记录日志。

### 3. 请求解析（`BridgeProtocol.swift`）

- `addTodo`：`text` 必须是字符串，去掉首尾空白后不为空、不超过 500 个字符（按 `Character` 计），否则 `invalid`；`projectId` 缺失或为 `NSNull` → 没有项目；是字符串时必须满足 `isValidID`，其他类型 → `invalid`。
- `setTodoDone`：`todoId` 必须是满足 `isValidID` 的字符串；`done` 必须是布尔值（用 `CFBooleanGetTypeID` 排除数字），否则 `invalid`。
- 两个动作都不允许多出参数。

### 4. 推送内容（`BridgeProtocol.swift`）

```swift
extension PageEvent {
    static func todos(access: String, items: [TodoItem]) -> [String: Any]
}
```

```json
{
  "event": "todos",
  "access": "granted",
  "items": [
    { "id": "2DF0F70F-…", "text": "…", "done": false, "projectId": null, "due": { "date": "2026-10-18", "time": "09:00" } }
  ]
}
```

- `access` 取值：`granted`（`.fullAccess`）、`denied`、`notDetermined`、`restricted`、`writeOnly`；未来新增的状态按 `denied` 处理并记录日志。
- `projectId`、`due`、`due.time` 为空时写 `NSNull()`，不省略。不是 `granted` 时 `items` 为空数组。

### 5. `RemindersStore.swift`（新建，EventKit）

```swift
@MainActor
final class RemindersStore {
    var onChange: (([String: Any]) -> Void)?      // 推送 todos 事件
    init(appState: AppState)
    func start()
    func stop()
    func configDidReload()
    func add(text: String, projectId: String?, reply: @escaping (Result<TodoItem, BridgeError>) -> Void)
    func setDone(id: String, done: Bool, reply: @escaping (Result<Void, BridgeError>) -> Void)
}
```

- **启动**（`AppDelegate` 在窗口建好之后调用 `start()`，这样权限框出现时桌面已经显示）：
  - 状态是 `.notDetermined`：先推送一次 `access: notDetermined`、空列表，再调用 `requestFullAccessToReminders`；结果回到主线程后按新状态处理。
  - 状态是 `.fullAccess`：开始监听 `EKEventStoreChanged`，调用一次 `refreshSourcesIfNecessary()`，然后读取并推送。
  - 其他状态：推送对应的 `access` 和空列表，不再请求。
  - 记录一行 `DesktopShell reminders: access=<状态>`。
- **读取**：重新算一遍列表到项目的对应关系（列表可能被改名）；用两个查询（所有列表的未完成提醒；所有列表里今天 0 点之后完成的提醒）读出来，合并成 `ReminderSnapshot`，交给 `TodoItems.make`。结果（`access` 和 `items`）和上次推送的一样就不推送。每次推送记录一行 `DesktopShell reminders: pushed items=<数量>`。
- **变化**：`EKEventStoreChanged` → 防抖 0.5 秒（一次性延迟任务，期间再收到就重新计时）→ 读取。日期变化（`NSNotification.Name.NSCalendarDayChanged`）→ 读取（"今天完成的"范围变了）。
- **主动同步**：收到 `NSWorkspace.screensDidWakeNotification`、`NSWorkspace.sessionDidBecomeActiveNotification` 时，以及每 5 分钟一次（`Timer`，`tolerance = 60`）调用 `refreshSourcesIfNecessary()`；它引起的数据变化会通过 `EKEventStoreChanged` 进来，不需要另外读取。
- **新增**：没有授权 → `failed`。目标列表：没有 `projectId` → 系统默认列表（`defaultCalendarForNewReminders()`，没有 → `failed`）；有 `projectId` → 项目必须在配置里（否则 `not-found`），有对应列表就用它，没有就用默认列表。新建 `EKReminder`，标题是去掉首尾空白后的 `text`，**只设标题和列表**，`save(_:commit: true)`，出错 → `failed`。回复新提醒的 `TodoItem`（`projectId` 按它所在的列表算）。
- **勾选**：没有授权 → `failed`。`calendarItem(withIdentifier:)` 拿不到 `EKReminder` → `not-found`。只改 `isCompleted`，`save(_:commit: true)`，出错 → `failed`。
- **重新加载**：`AppState.reloadConfig()` 之后调用 `configDidReload()`，重新算对应关系并读取。
- **不提供删除**：代码里不调用 `EKEventStore.remove`。
- `stop()`：移除所有监听，停掉定时器和待执行的防抖任务。

### 6. 接线

- `AppState` 持有 `RemindersStore`（或由 `AppDelegate` 创建后交给 `AppState`），`Bridge` 通过 `AppState` 调用 `add` / `setDone`，在回调里回复网页。成功时分别记录 `DesktopShell bridge: addTodo ok`、`DesktopShell bridge: setTodoDone ok`（不写标题）。
- `AppDelegate` 把 `onChange` 接到 `ScreenManager.broadcast`（M3-05 已经会缓存 `todos` 并在页面加载后重推），退出时 `stop()`。

### 7. 测试

- `TodoItemsTests.swift`：
  - `due`：只有日期；日期加时间（补零，例如 `2026-01-05`、`09:05`）；缺 `day` → `nil`；有 `hour` 没有 `minute` → `time` 为 `nil`。
  - `make`：未完成的保留；今天完成的保留；昨天完成的丢掉；排序规则（带时间、只有日期、没有到期时间、今天完成的）；`projectId` 对应；空标题保留；超过 500 条截断。
  - `listToProject`：完全匹配；大小写或空白不同不算匹配；找不到；同名列表取 id 排序第一个；两个项目同一列表取第一个项目；`remindersList` 为空白时跳过。
- `BridgeTests.swift`：`addTodo`（合法；带和不带 `projectId`；`projectId` 为 `NSNull`；空白文本；501 个字符；`text` 是数字；`projectId` 非法；多出参数）、`setTodoDone`（合法；`done` 是数字 `1`；缺 `done`；`todoId` 非法；多出参数）。
- `PageEventTests.swift`：`todos` 事件的键和值；`projectId`、`due`、`due.time` 为空时是 `NSNull`；不是 `granted` 时 `items` 为空。

## 允许修改的文件

- `Sources/DesktopShell/RemindersStore.swift`、`Sources/DesktopShell/TodoItems.swift`（新建）
- `Sources/DesktopShell/BridgeProtocol.swift`、`Bridge.swift`、`AppState.swift`、`AppDelegate.swift`（修改）
- `scripts/bundle.sh`（修改：只加 `NSRemindersFullAccessUsageDescription`）
- `Tests/DesktopShellTests/TodoItemsTests.swift`（新建）、`BridgeTests.swift`、`PageEventTests.swift`（修改）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。**不删除任何提醒或列表**，不新建列表，不修改标题和完成状态以外的字段。
- 不把提醒内容写进文件或日志。
- 不用旧的 `requestAccess(to:)`，用 `requestFullAccessToReminders`。
- 不修改 `web/` 下的任何文件，不修改 `PowerMonitor`、`HitTesting`、`HitTestController`。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过，包含上面列出的新测试；`scripts/test-web.sh` 仍然全部通过
- [ ] `git diff --name-only main...task/M3-07` 只包含"允许修改的文件"
- [ ] `grep -rnE "\.remove\(|removeReminder|saveCalendar|requestAccess\(to:" Sources/` 没有输出
- [ ] `scripts/bundle.sh` 之后，`plutil -p build/DesktopShell.app/Contents/Info.plist | grep NSRemindersFullAccessUsageDescription` 有输出
- [ ] `.app` 启动后，日志里有 `DesktopShell reminders: access=granted` 和 `DesktopShell reminders: pushed items=<数量>`；点完自检面板的"新增测试提醒"之后，`/usr/bin/log show --last 5m --predicate 'subsystem == "local.desktopshell.DesktopShell"' | grep "DesktopShell 自检"` **没有输出**（日志里没有提醒标题）

**用户手动验证**（`scripts/bundle.sh --open`，用自检面板）：

- [ ] 第一次启动弹出"DesktopShell 想访问提醒事项"→ 点"允许"；自检面板显示 `todosAccess = granted`，条数等于所有列表里未完成的提醒加上今天完成的（和 Mac 的"提醒事项"应用对照）；前 5 条显示标题和到期时间
- [ ] 退出后再启动：不再弹权限框
- [ ] 点面板上某条的勾选框：Mac 的"提醒事项"应用里它马上变成已完成，面板上它还在（今天完成的）且显示为已勾选；再点一次恢复
- [ ] 点"新增测试提醒"：面板上立刻多一条；Mac "提醒事项"的默认列表里也有；在"提醒事项"应用里把它删掉 → 面板上 1 秒左右消失
- [ ] iPhone 同步（Mac 的"提醒事项"应用**关闭**）：在 iPhone 上勾选或新增一条，记下它出现在桌面面板上用了多久，做 3 次。Codex 和 Claude Code 把实测时间写进记录；超过 3 分钟的情况由 Claude Code 和用户决定是否另做处理
- [ ] 项目关联：在"提醒事项"里新建一个列表"DesktopShell"并加一条提醒；`config.json` 的 `desktop-shell` 项目加上 `"remindersList": "DesktopShell"`；菜单栏"重新加载" → 面板的按项目统计里出现"desktop-shell 1"。（验证完列表可以留着，M4 用得上）
- [ ] "发送非法请求"：7 条全部 ✓
- [ ] 未授权：在"系统设置 → 隐私与安全性 → 提醒事项"里关掉 DesktopShell，重启应用 → 面板显示 `denied`、0 条，点"新增测试提醒"显示 `failed`，其他功能照常；验证后重新打开权限

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
