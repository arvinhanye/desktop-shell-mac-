# M7-03: 把文件夹拖到项目卡片上添加（原生拖放）

- **状态**：done
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
  - 基于已合并 M7-01、M7-02 的 `main` / `origin/main`（`d9a3864`）建立 `task/M7-03`。
  - 新增 `FileDropTracking`：按下时的剪贴板版本与文件 URL 联合判断、跨屏区域命中、成功项与首个错误的纯结果汇总；`PageEvent.projectDrop` 仅序列化 id/name/error，不含路径，且不进入重载缓存。
  - `setDropRegions` 严格沿用矩形校验与窗口裁剪，上限 8 个，存入对应 WidgetWindow 并通知鼠标控制器。全局/本地左键按下记录剪贴板版本，文件拖动进入区域才接收，普通拖动仍冻结原状态；隐藏桌面文件分支和 VideoWindow 保持原样。
  - 用 `FileDropWebView` 截获拖放，覆盖进入、更新、离开、准备、执行、结束与取消回调，不调用 WebKit 的 super 拖放行为；仅返回 copy，关闭周期性拖放更新。路径只交给原生 `AppState.addProject`；配置广播沿用 M7-01，结果仅发给本页面；重载、区域移除、关闭及停止监听清除悬停。
  - 复用可配置的区域 reporter，新增 `[data-drop]` 上报，在 main 中启动并响应安全区变化。原点击区域默认选择器、64 项限制、去重及触发机制保留；拖入独立限制 8 项，移除标记会清空旧区域。mock 接入新动作。
- **自测结果**：
  - 基线 PASS：Swift 248/248；web 468/468。
  - RED：先添加测试，Swift 因尚无 FileDropTracking / setDropRegions / projectDrop 实现而编译失败；web 因缺少 drop-regions 模块以及 mock 返回 unknown-action 失败，记录为预期缺失实现，不计为环境或既有产品失败。
  - GREEN：`scripts/test.sh` 254/254 PASS（27 suites）；`scripts/test-web.sh` 474/474 PASS，0 FAIL / 0 SKIP。覆盖检测四组合、缺失按下记录、双屏与负坐标边界、全部/部分/零成功、首错、JSON 投影、9 区域拒绝、非法参数、上报去重/可见性/标记移除，以及真实 main 在 native/mock 模式启动和安全区变化。
  - `swift build` PASS，无编译错误或警告；`scripts/bundle.sh` release PASS，固定 DesktopShell Self-Signed 证书签名、plist 与 designated requirement 验证通过；产物 `build/DesktopShell.app`，未启动。
  - `git diff --check` PASS；`grep -n "\.move" Sources/DesktopShell/WebContainer.swift` 无输出；无 super 拖放调用或新增轮询；VideoWindow 源码与基线一致。
  - 独立只读审查覆盖全部 17 个变更文件，未发现阻塞缺陷；额外执行 drop/hit/mock 82/82、glass 8/8 PASS。最终范围为原任务允许文件加用户批准的一行测试隔离例外。
  - 手动验收尚未执行：真实 Finder 单/多文件夹拖入、文件拒绝、穿过卡片、框选、输入框增删及配置保留/恢复，按本任务单由 Claude Code 备份配置后与用户一起验证。本次未启动应用、未修改真实 config.json、未操作任何被拖文件。
- **疑问 / 偏离**：
  - 2026-10-21 用户明确批准“同意，仅补这一行”：在 `Tests/web/glass-regions.test.mjs` 的入口测试 mock 表增加一行 `drop-regions.js` 隔离，保留全部毛玻璃断言；该文件没有其他改动。此前 web 唯一失败是该旧测试把新的 drop 选择器误当作 glass 选择器；补齐隔离后全量通过。
  - 按任务第 5 节允许的方案复用 hit-regions reporter；未添加依赖、全局调试 API 或新样式。
  - 交付状态为 review；仅提交并推送 task/M7-03，不合并或推送 main。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：通过（2026-10-21，Claude Code），合并到 `main`。M7 的桌面验收（含 M7-01、M7-02）在这里一起完成，M7 完成。
- **可执行的检查**（在 `3e77259` 的临时检出里实际运行）：
  - `swift build`：0 个警告。
  - `scripts/test.sh`：254/254 通过。
  - `scripts/test-web.sh`：474/474 通过。
  - `grep -n "\.move" Sources/DesktopShell/WebContainer.swift`：没有输出。
  - 改动范围：任务单允许的文件，加上用户同意的 `glass-regions.test.mjs` 一行（入口测试里隔离 `drop-regions.js`）。
- **代码核对**：
  - **拖放方法**：`FileDropWebView` 改写了全部拖放方法，不调用 `super`。只有满足三个条件才接受，返回 `.copy`：拖放剪贴板里有文件 URL、目标是本窗口、光标在拖入区域里。路径只交给 `AppState.addProject`，网页只收到 `id` / `name`。
  - **点击穿透**：`HitTestController` 按下时记下 `changeCount`。按住期间只有拖文件才按拖入区域切换，普通拖动和框选保持原状态，没有轮询。
  - **清理**：页面重新加载、窗口关闭、区域被清空时，都会撤掉悬停提示。
- **桌面验收**（主仓库的 `build/DesktopShell.app`，07:44:59 启动；先备份了 `config.json`；用户操作，Claude Code 对照日志、`config.json` 和磁盘）：

  | 验收项 | 证据 | 结果 |
  |---|---|---|
  | 输入框添加 | 08:04:00 `added id=cs61a-master path=~/Desktop/CS61A-master`；`config.json` 多了这一项，`apps` 为 `["cursor"]`、`tags` 为空 | 通过 |
  | 用 Cursor 打开新项目 | 08:04:14 `openProjectWith cs61a-master cursor ok` | 通过 |
  | 输入框报错 | `not-found`、`duplicate`、`not-directory` 都有日志。`/etc`：用户在英文输入法下打，确认显示"只能添加个人文件夹（~）里的文件夹"（Claude Code 另用这次的代码直接核对，`/etc` → `outsideHome`） | 通过 |
  | 一次拖两个文件夹 | 08:20:30 `drop: folders=2 added=2`（`6.096 introduction to c++` → id `6-096-introduction-to-c`；纯中文名 `我的思想报告` → id `project`），"已添加 2 个项目" | 通过 |
  | 拖一个文件夹 | 08:20:53 `added id=2026 path=~/Desktop/2026_糖尿病_项目` | 通过 |
  | 拖一个文件 | 08:20:41 `rejected code=not-directory`，`drop: folders=1 added=0` | 通过 |
  | 被拖的文件夹不动 | 三个被拖的文件夹都还在桌面原处 | 通过 |
  | 穿过卡片、框选 | 用户目测照常 | 通过 |
  | 移除 | 08:23:11 `removed id=project`、08:23:18 `removed id=2026`；`config.json` 里没有了，两个文件夹都还在 | 通过 |
  | 收尾 | 用户决定保留当前配置（DesktopShell、CS61A-master、6.096 introduction to c++），不恢复备份 | — |

- **意见**（都另开了任务，不阻塞本任务）：
  - **复制粘贴**：用户发现输入框不能复制粘贴。原因是应用没有"编辑"菜单，⌘V 等快捷键没有人分派，从 M3-08 起就这样。另开 M7-04 修。
  - **全角符号**：用中文输入法打路径时，容易打出全角的"～""／"，结果提示"找不到这个文件夹"，容易误导。用户同意修：路径开头的全角符号当成半角处理。另开 M7-05。
