# M1-01: 工程骨架、菜单栏退出、每屏桌面层窗口

- **状态**：done
- **里程碑**：M1
- **依赖**：无
- **分支**：task/M1-01

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

运行 `.build/debug/DesktopShell` 后：菜单栏出现一个图标，可以从菜单退出；每块屏幕上出现一个深灰色的全屏桌面层窗口，位于普通窗口之下，中间显示该屏幕的名称和尺寸。

## 背景与约束

- 先读 `AGENTS.md` 的"核心架构""开发环境""窗口要求"。
- 本任务**只做原生外壳**：不加 WKWebView、不加视频、不算安全区域（安全区域是 M1-02）。
- `Package.swift`：
  - `// swift-tools-version:6.0`
  - 包名和可执行 target 名都是 `DesktopShell`，源码在 `Sources/DesktopShell/`
  - `platforms: [.macOS(.v14)]`
  - `swiftLanguageModes: [.v5]`
  - 不引入任何第三方依赖
  - 本任务不加 test target（M1-02 再加）
- `main.swift`：创建 `NSApplication`，设置 delegate，调用 `setActivationPolicy(.accessory)`（不在 Dock 里显示图标，相当于以后 `.app` 里的 `LSUIElement`），然后 `run()`。
- `AppDelegate.swift`（标注 `@MainActor`）：
  - `NSStatusItem`，图标用 SF Symbol `square.grid.2x2`，`isTemplate = true`（跟随菜单栏深浅色）。
  - 菜单只有一项："退出 DesktopShell"，快捷键 ⌘Q，调用 `NSApp.terminate(nil)`。其他菜单项（暂停、重新加载、打开配置文件夹）属于后续里程碑，现在不加。
  - 启动时创建 `ScreenManager` 并开始工作。
- `DesktopWindow.swift`：`NSWindow` 子类。
  - `styleMask = .borderless`，`frame` 等于所在屏幕的 `screen.frame`。
  - `level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)`
  - `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`
  - `ignoresMouseEvents = false`，`hasShadow = false`，`isReleasedWhenClosed = false`。
  - **本任务不要重写 `canBecomeKey`**，键盘焦点在 M4 待办组件里处理。
  - 内容：一个纯色占位视图，背景色 `NSColor(calibratedWhite: 0.12, alpha: 1)`；中间用白色文字显示 `"<屏幕 localizedName>  <宽>×<高>"`（单位为点）。这里是 Swift 原生调试界面，"CSS 不许写死颜色"的规则不适用。
- `ScreenManager.swift`（标注 `@MainActor`）：
  - 启动时为 `NSScreen.screens` 中的每块屏幕创建一个 `DesktopWindow` 并 `orderFront`。
  - 用屏幕的显示器 ID（`deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`，即 `CGDirectDisplayID`）作为 key 记录窗口。
  - 监听 `NSApplication.didChangeScreenParametersNotification`，按显示器 ID 对比：新增的屏幕建窗口，消失的屏幕关窗口，仍在的屏幕把窗口 `setFrame` 到新的 `screen.frame`（处理分辨率变化），并刷新中间的文字。
  - 退出时（`deinit` 或 `applicationWillTerminate`）移除通知监听。

## 允许修改的文件

- `Package.swift`（新建）
- `Sources/DesktopShell/main.swift`（新建）
- `Sources/DesktopShell/AppDelegate.swift`（新建）
- `Sources/DesktopShell/DesktopWindow.swift`（新建）
- `Sources/DesktopShell/ScreenManager.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不加 WKWebView、AVPlayer、配置文件读写、安全区域计算，这些属于后续任务。
- 不重写 `canBecomeKey` / `canBecomeMain`。
- 不使用 Storyboard、XIB、Asset Catalog、`.xcodeproj`。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出（零警告零错误）
- [ ] `git diff --name-only main...task/M1-01` 只包含上面"允许修改的文件"里列出的文件
- [ ] `grep -rnE "canBecomeKey|WKWebView|AVPlayer" Sources/` 没有输出
- [ ] 运行 `.build/debug/DesktopShell &`，等 2 秒后 `pgrep -x DesktopShell` 能找到进程；然后 `kill %1` 能正常结束

**用户手动验证**（运行 `.build/debug/DesktopShell`）：

- [ ] 菜单栏出现一个四宫格图标；**Dock 里没有**新图标
- [ ] 桌面变成深灰色，中间显示屏幕名称和尺寸
- [ ] Finder、Safari 等普通窗口都**在深灰色之上**，能正常使用
- [ ] 点击深灰色空白处，什么都不发生，也不会盖到其他窗口上面
- [ ] 按 Ctrl+→ 切换到其他桌面空间，深灰色背景仍然在
- [ ] 打开调度中心（F3 或三指上滑），深灰色背景不会被当成一个窗口缩小
- [ ] 菜单栏图标 → "退出 DesktopShell"，进程结束，桌面恢复原样；⌘Q 在菜单打开时同样有效
- [ ] （有外接显示器时）每块屏幕各有一个深灰色窗口，各自显示自己的名称；拔掉外接显示器，对应窗口消失；再插上，窗口重新出现

说明：如果还没有执行隐藏 Finder 桌面图标的命令，桌面图标会被深灰色盖住，这是预期行为。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
  - 从本地 `main`（`a1c4bb5`）创建 `task/M1-01`；添加用户提供的仓库为 `origin`。远端引用查询为空，本次仅作本地提交，尚未推送或合并。
  - 新增 SwiftPM 可执行工程：macOS 14、Swift 5 语言模式、零第三方依赖；按任务要求暂不添加 test target。
  - 入口以 `.accessory` 策略运行；同步主线程入口通过 `MainActor.assumeIsolated` 进入 UI 隔离域，并在事件循环期间保持 delegate 存活。
  - 菜单栏使用模板四宫格图标，仅包含“退出 DesktopShell”（⌘Q）；退出时停止屏幕管理并移除菜单栏图标。
  - 每屏创建深灰色、无边框的桌面层窗口，居中显示屏幕名称和点尺寸；使用指定层级及 collectionBehavior，不覆盖键盘焦点能力。
  - 按显示器 ID 维护窗口；屏幕参数变化时新增、关闭或更新窗口及文字；应用退出时移除通知监听并关闭窗口。
- **自测结果**：
  - `swift build`：最终构建退出码 0；对输出执行 `grep -iE "warning|error"` 无匹配（grep 退出码 1），零警告、零错误。产物确认为 `Mach-O 64-bit executable x86_64`。
  - `grep -rnE "canBecomeKey|WKWebView|AVPlayer" Sources/`：无输出。额外检查未引入 `canBecomeMain`、SwiftUI、shell 执行或安全区域计算。
  - 启动 `.build/debug/DesktopShell &`，等待 2 秒后 `pgrep -x DesktopShell` 找到本次 PID `38933`；`kill %1` 后 `wait` 返回 143（SIGTERM），确认该 PID 已结束；运行日志为空。这项只验证进程生命周期，不替代菜单退出验证。
  - `git diff --check`：通过；`AGENTS.md`、`CLAUDE.md` 和 M1-02 任务单保持不变；交付差异限定为本任务允许的 6 个文件。
  - GUI 项尚待用户手动验证：在项目目录运行 `.build/debug/DesktopShell`，依次检查四宫格菜单且无 Dock 图标、灰色背景及屏幕文字、普通窗口位于其上、点击空白处无动作、Ctrl+→ 跨空间、调度中心不缩小背景、菜单退出及菜单打开时的 ⌘Q；有外接屏时再检查独立文字、拔插增删及分辨率变化后的尺寸刷新。退出后确认原桌面恢复。
- **疑问 / 偏离**：
  - 无需求或文件范围偏离；本任务按明确约束暂不建立单元测试 target，安全区域仍留给 M1-02。
  - 首次沙盒内构建因 SwiftPM/Clang 缓存写入权限失败；经权限审批重跑。源码首轮编译发现 NSWindow 便利初始化器与主线程隔离入口问题，已分别改为指定初始化器和同步主线程隔离入口，随后构建与启动检查通过。
  - 自动化检查通过不代表 GUI 验收通过；审查记录保留给 Claude Code，尚未合并到 `main`。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**通过**，已合并到 `main`。用户手动验证全部正常（菜单栏图标、深灰色桌面层、窗口层级、点击空白处、切换桌面空间、调度中心、菜单退出），远端 `origin` 也已由用户确认。
- **复验结果**（Claude Code，2026-10-16，本机 macOS 26.6.2）：
  - [x] touch 全部源码后强制重编，`swift build` 零警告零错误。
  - [x] `git diff --name-only main...task/M1-01`：5 个源码文件加本任务单，没有越界；任务单只改了状态和交付记录。
  - [x] `grep` 没有找到 `canBecomeKey/canBecomeMain/WKWebView/AVPlayer`，也没有找到 `Process(`、`NSTask`、`posix_spawn`。
  - [x] 运行后 `pgrep` 能找到进程，SIGTERM 后正常退出（143），运行日志为空。
  - [x] 补充检查（用 `CGWindowListCopyWindowInfo` 读系统窗口列表）：每块屏幕一个窗口，层级为 `-2147483602`，等于 desktopIcon+1；在屏幕上可见，bounds 为 `(0,0,1792,1120)`，与屏幕 frame 一致；有 6 个普通窗口在它之上。
  - [x] 菜单栏图标：macOS 26 的菜单栏图标由"控制中心"进程托管，按窗口列表查不到；已由用户目测确认。
- **意见**（不阻塞合并）：
  - 代码结构清楚，严格按任务单实现；用 `setFrame(screen.frame)` 处理非主屏坐标，用显示器 ID 管理窗口增删，都是正确做法。
  - Codex 新增了 git 远端 `origin`（据交付记录，是用户提供的仓库），没有推送。这不是文件改动，但超出了任务范围，请用户确认是否需要。
  - 需要用户留意：点击深灰色空白处时，当前前台应用会不会失去焦点（窗口标题栏变灰）。如果会，这是桌面窗口能接收点击带来的系统行为，留到 M4 处理键盘焦点时一起解决，不算本任务的缺陷。
