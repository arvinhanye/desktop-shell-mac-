# M7-03: 把文件夹拖到项目卡片上添加（原生拖放）

- **状态**：todo
- **里程碑**：M7
- **依赖**：M7-01（`AppState.addProject`、`PageEvent` 的写法）和 M7-02（`data-drop`、`projectDrop` 的网页处理）都合并到 `main` 之后再开始
- **分支**：task/M7-03

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

在桌面（或访达）里拖一个或几个文件夹到项目卡片上：

- 拖到卡片上方时，卡片出现"松开，添加为项目"；
- 松开后，这些文件夹被加成项目，被拖的文件夹留在原处不动；
- 拖着图标穿过卡片、放到桌面别处，或者框选经过卡片，都和以前一样。

## 背景与约束

- 先读 AGENTS.md 里标着 M7 的部分：
  - "窗口要求"里"例外：拖文件时"一条，包括探针结论；
  - "Bridge 接口"的 `setDropRegions`、推送事件 `projectDrop`；
  - "安全要求"里"拖入文件夹时路径不经过网页"。
- **Claude Code 的拖入探针**（2026-10-21，一个和 WidgetWindow 设置相同的全屏面板，加一个 WKWebView 子类）：
  - **判断是不是在拖文件**：按下鼠标时记下 `NSPasteboard(name: .drag).changeCount`。拖文件时，它会在拖出几像素后变化，并含有 `public.file-url`。框选、普通按住拖动时它不变。
  - **全局事件够用**：按住鼠标期间，全局监听照常收到 `leftMouseDragged`（每次拖动 28–86 个），够用，不需要定时器。
  - **原生接住拖放**：光标进入目标区域时设 `ignoresMouseEvents = false`，WKWebView 子类改写的 `draggingEntered` 会被调到，`performDragOperation` 读到文件夹 URL。返回 `.copy`，访达没有移动文件夹。
  - **其他拖动不受影响**：框选、普通拖动都没有被打断。
- **WKWebView 自己也处理拖放**：把文件拖进去，它会试图打开那个文件。现在的导航策略只允许 `shell://`，所以打不开，但不能依赖这个兜底。拖放方法要在子类里改写，**不调用 `super`**。

### 1. 纯函数（新建 `Sources/DesktopShell/FileDropTracking.swift`）

- `isFileDrag(changeCountAtMouseDown:currentChangeCount:hasFileURLs:) -> Bool`。
- `isInDropRegion(mouse:windowFrame:regions:) -> Bool`：坐标换算和 `HitTesting.isInteractive` 一样，可以直接复用它。
- `dropOutcome(results:)`：把逐个添加的结果汇总成 `projectDrop` 的 `result`，即 `{added: [{id, name}], error}`，`error` 取第一个失败的错误码。

### 2. 拖入区域（`BridgeProtocol.swift`、`Bridge.swift`、`DesktopWindow.swift`）

- 新动作 `setDropRegions`：校验同 `setHitRegions`，最多 8 个。存进 `WidgetWindow.dropRegions`，变化时通知 `HitTestController`。

### 3. 切换接收鼠标（`HitTestController.swift`）

- 全局和本地监听都加上 `leftMouseDown`，按下时记下拖放剪贴板的 `changeCount`。
- 按住期间：
  - 如果 `isFileDrag` 为真，光标在某个窗口的拖入区域里时，这个窗口 `ignoresMouseEvents = false`，否则为 `true`；
  - 如果不是拖文件，保持现在的规则（不切换）。
- 松开后回到现在的判断。
- "隐藏桌面文件"时窗口本来就全部接收鼠标，这个逻辑不动它。

### 4. 接住拖放（`WebContainer.swift`）

- WKWebView 换成一个子类，改写 `draggingEntered`、`draggingUpdated`、`draggingExited`、`prepareForDragOperation`、`performDragOperation`、`concludeDragOperation`，都不调用 `super`。
- 只有满足两个条件才接受，返回 `.copy`：拖放剪贴板里有文件 URL，并且光标在本窗口的拖入区域里。其余情况一律返回 `[]`。
- `draggingEntered`（接受时）给本窗口的页面推送 `projectDrop {over: true, result: null}`。`draggingExited` 推送 `{over: false, result: null}`。
- `performDragOperation`：
  1. 用 `readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])` 读出 URL。
  2. 逐个调用 `AppState.addProject(path: url.path)`。文件不是文件夹时，那里会回 `not-directory`。
  3. 汇总后推送 `projectDrop {over: false, result: …}`。
  4. 返回 `true`。
- 添加成功时，`config` 推送由 M7-01 的逻辑照常发给所有页面；`projectDrop` 只发给被拖入的那个页面。
- 日志：
  - 一次拖放一行：`DesktopShell drop: folders=<个数> added=<个数> rejected=<个数>`；
  - 每个被拒的原因由 M7-01 的 `add rejected code=…` 记录。
  - 不写文件夹名。

### 5. 网页上报拖入区域

- 新建 `web/js/drop-regions.js`：自动上报所有 `[data-drop]` 元素的矩形，发 `setDropRegions`。触发上报的时机和去重方式照 `hit-regions.js`。
- 可以把 `hit-regions.js` 改成能传选择器和动作名的通用写法再复用；如果这样做，`hit-regions.js` 原有的行为和测试都不能变。
- `web/js/main.js` 里启动它。
- `mock.js` 的动作表加 `['setDropRegions', ['regions']]`，处理方式同 `setHitRegions`。

### 6. 测试

- `Tests/DesktopShellTests/FileDropTrackingTests.swift`（新建）：
  - `isFileDrag` 的四种组合；
  - `isInDropRegion` 的坐标换算：窗口在第二块屏幕上时，区域边界的里面和外面；
  - `dropOutcome`：全部成功、部分失败、全部失败、空列表。
- `BridgeTests`：`setDropRegions` 合法和不合法的输入，第 9 个区域要被拒。
- `PageEventTests`：`projectDrop` 两种形态的键，能被 `JSONSerialization` 接受。
- `Tests/web/drop-regions.test.mjs`（新建）：只上报 `[data-drop]`；变化时重新上报；同样的区域不重复发送。
- `Tests/web/mock.test.mjs`：`setDropRegions`。

## 允许修改的文件

- `Sources/DesktopShell/FileDropTracking.swift`（新建）
- `Sources/DesktopShell/HitTestController.swift`、`Sources/DesktopShell/WebContainer.swift`、`Sources/DesktopShell/DesktopWindow.swift`、`Sources/DesktopShell/Bridge.swift`、`Sources/DesktopShell/BridgeProtocol.swift`（修改）
- `web/js/drop-regions.js`（新建）、`web/js/main.js`、`web/js/mock.js`、`web/js/hit-regions.js`（只在第 5 节说的情况下改）
- `Tests/DesktopShellTests/FileDropTrackingTests.swift`、`Tests/web/drop-regions.test.mjs`（新建）
- `Tests/DesktopShellTests/BridgeTests.swift`、`Tests/DesktopShellTests/PageEventTests.swift`、`Tests/web/mock.test.mjs`、`Tests/web/hit-regions.test.mjs`（修改）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"：
  - 拖放操作只用 `.copy`，不用 `.move`；
  - 不对被拖的文件或文件夹做任何文件操作。
- 不把文件路径传给网页。网页只收到 `projectDrop` 里的 `id` 和 `name`。
- 不轮询（探针证明全局事件够用）。
- 不改 `VideoWindow`（它永远不接收鼠标），不改"隐藏桌面文件"的行为。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build` 无错误、无警告
- [ ] `scripts/test.sh`、`scripts/test-web.sh` 全部通过
- [ ] `scripts/bundle.sh` 成功
- [ ] `grep -n "\.move" Sources/DesktopShell/WebContainer.swift` 没有输出
- [ ] `git diff --name-only main...task/M7-03` 只有上面"允许修改的文件"

**用户手动验证**（M7 的整体验收，M7-01、M7-02 的桌面验证也在这里一起做）：

准备工作由 Claude Code 做：备份 `config.json`；用主仓库的 `build/DesktopShell.app` 启动；对照日志、`config.json` 和磁盘。

- [ ] **输入框添加**：粘贴 `~/Desktop/<某个文件夹>` 回车，列表末尾出现这个项目，"已添加「…」"。`config.json` 里多了一项：`path` 是 `~/…`，`apps` 是 `["cursor"]`。点它的"Cursor"按钮能用 Cursor 打开。
- [ ] **输入框报错**：
  - `/etc` → "只能添加个人文件夹（~）里的文件夹"；
  - 一个不存在的路径 → "找不到这个文件夹"；
  - 一个文件的路径 → "这不是文件夹"；
  - 同一个文件夹再加一次 → "这个文件夹已经是项目了"。
- [ ] **拖入一个文件夹**：从桌面拖到项目卡片上，卡片出现"松开，添加为项目"；松开后加进列表。**桌面上的文件夹还在原处。**
- [ ] **一次拖两个文件夹** → "已添加 2 个项目"。
- [ ] **拖一个文件**（不是文件夹）→ "这不是文件夹"，什么都没加。
- [ ] **不受影响的操作**：
  - 拖着桌面图标穿过卡片、放到桌面空白处，图标照常移过去，没有加成项目；
  - 框选经过卡片，照常框选。
- [ ] **移除**：× 点两次 → 从列表消失，"已移除「…」，文件夹没有动"。`config.json` 里没有这一项了，磁盘上的文件夹还在。
- [ ] **移除选中的项目**：移除当前选中的项目后，待办回到"全部列表"。
- [ ] **收尾**：最后保留哪些项目由用户决定。Claude Code 按用户的意思恢复备份，或者保留当前配置。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
