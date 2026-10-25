# M9-05: 终端面板、全局快捷键和终端 bridge（Swift）

- **状态**：review
- **里程碑**：M9
- **依赖**：M9-02（`HotKey.swift`、`config.terminal`）、M9-03（`TerminalSession`）、M9-04（`terminal.html`），三个都合并以后再做。M9-01 最好也已合并（终端入口在那里），不合并也能做，手动验证时用快捷键
- **分支**：task/M9-05

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

把终端接起来：

- 按 ⌥\`（或配置的快捷键），或点桌面上的终端入口，终端面板从鼠标所在屏幕的顶部滑下，直接可以打字，前台应用不变；
- 再按一次快捷键，或点面板上的"收起"，面板收起，键盘回到原来的应用；
- 面板里是 M9-04 的 `terminal.html`，跑着 M9-03 的会话。

这是 M9 的最后一个任务，做完后按"用户手动验证"在桌面上整体验一遍。

## 背景与约束

- 先读 AGENTS.md：
  - "核心架构"里的终端面板和例外说明；
  - "窗口要求"里的 **TerminalPanel**；
  - Bridge 接口：`openTerminal`，"终端页 → Swift""Swift → 终端页""终端会话"三块；
  - "安全要求"里终端的几条；
  - "技术探针"的终端面板探针：面板、快捷键两段，照那里验证过的调用顺序写。

### 1. 面板（新建 `TerminalPanel.swift`）

- **`NSPanel` 子类**：
  - `styleMask` 为 `[.borderless, .nonactivatingPanel]`；
  - `canBecomeKey` 为 `true`，`canBecomeMain` 为 `false`；
  - `hidesOnDeactivate = false`；
  - 先设 `isFloatingPanel = true`，**最后**设 `level = .floating`（AGENTS.md"窗口要求"里有 `isFloatingPanel` 会改层级的教训）；
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`；
  - `isOpaque = false`、`backgroundColor = .clear`、`hasShadow = true`。
- **内容视图**：
  - 先放一个 `NSVisualEffectView`：`.hudWindow`、`.behindWindow`、`.active`、`darkAqua`，圆角 2（和 tokens 的 `--radius-lg` 一致，写一个常量并注明来源）；
  - 上面盖一个透明的 WKWebView，铺满。
- **WKWebView 的配置**：
  - 自己一份 `WKWebViewConfiguration`，`shell` scheme 用和组件页同样的 `ShellSchemeHandler` / `SchemeResolver`；
  - 消息处理器名字也叫 `shell`，注册在**这个 WKWebView 自己的** `userContentController` 上；
  - 导航策略和组件页一样，只允许 `shell://app`，见 `WebContainer`；
  - 加载 `shell://app/terminal.html`。
  - 第一次需要时才创建面板和页面。
- **位置**（写成纯函数并测试）：
  - 输入屏幕的 `visibleFrame` 和是否放大，输出面板的 frame；
  - 平时：左右各缩 16、离顶 8、高 = `visibleFrame` 高度的 45%（取整）；
  - 放大：左右各缩 16、上下各留 8。
  - 每次显示时取**鼠标所在的屏幕**（`NSEvent.mouseLocation`），找不到就用 `NSScreen.main`。显示期间屏幕参数变化（`didChangeScreenParametersNotification`）时，按当前屏幕重新摆放。
- **显示**：
  - 摆好位置 → `orderFrontRegardless()` → `makeKey()` → `makeFirstResponder(webView)` → 推送 `terminalState`（`visible: true`）；
  - 滑下动画：约 160 ms，从目标位置上方 24 点、透明度 0 开始，用 `NSAnimationContext`；
  - **不调用 `NSApp.activate`。**
- **收起**：推送 `terminalState`（`visible: false`）→ `orderOut` → 如果 `NSApp.isActive` 就 `NSApp.deactivate()`。可以加一个同样长的淡出，但 `orderOut` 和 `deactivate` 必须在动画结束后执行。
- **放大状态**：存在内存里，收起后保留，重启应用后恢复成不放大。
- 动画进行中又收到显示 / 收起请求：以最后一次为准，不要留下半透明或错位的面板。

### 2. 快捷键（修改 `HotKey.swift`）

- 启动时按 M9-02 解析出的配置，用 `InstallEventHandler` + `RegisterEventHotKey` 注册，收到 `kEventHotKeyPressed` 就切换面板（显示 ↔ 收起）。
- 日志：
  - 注册成功：`terminal hotkey registered <显示文字>`；
  - 注册失败：写错误码，终端入口照样能用。
- 改快捷键要重启应用才生效，菜单的"重新加载"不重新注册。

### 3. 终端 bridge（新建 `TerminalBridge.swift`，请求解析写在 `BridgeProtocol.swift` 或新文件里，要有测试）

- **只处理终端页的消息**：它只注册在终端面板那个 WKWebView 上，所以收到的消息都来自终端页；照样先做 `BridgeOrigin.isTrusted` 的主框架和来源校验，不通过回复 `untrusted`。
- **动作**：照 AGENTS.md 的表，参数不能多，类型和范围不对回复 `invalid`。
  - `terminalReady`：
    - 没有会话（或会话已经退出）就按这个尺寸启动；
    - 会话在运行就改尺寸，并把 `recentOutput` 作为一条 `terminalOutput` 推回去；
    - 然后推一次 `terminalState`。
  - `terminalInput`：
    - 会话在运行就写入；
    - 已经退出：用 `lastSize` 重新启动，这一下按键丢掉；
    - 还没启动过（页面没发过 `terminalReady`）：回复 `failed`。
  - `terminalResize`：改尺寸。
  - `toggleTerminalMaximize`：切换放大，重新摆放面板，回复 `{maximized}`，并推送 `terminalState`。
  - `hideTerminal`：收起面板。
  - 别的动作（包括组件页的动作，比如 `getConfig`）一律回复 `untrusted` 并记日志。
- **组件页的 `Bridge.swift`**：
  - 加 `openTerminal`（没有参数）：显示面板，回复 `null`；
  - 组件页发来上面五个终端动作，回复 `untrusted`，并记日志 `terminal action from widget page rejected`。
- **推送**：用 `callAsyncJavaScript("window.shell?.receive?.(event)", arguments:)`，不拼接字符串。
  - `terminalOutput`：会话的输出，base64；
  - `terminalExited`：`status`；
  - `terminalState`：`visible`、`maximized`、`hotkey`、`shell`（`$SHELL` 的文件名，没有时是 `zsh`）。终端页每次加载完成都推一次。
- **日志**：只写动作名和错误码；**不写 `data`，也不写它的长度。**

### 4. 其他

- `AppDelegate`：
  - 启动时建好终端控制器、注册快捷键；
  - 菜单"重新加载"时也重新加载终端页（面板已经创建过才需要）；
  - 退出时调用会话的 `terminate()`。
- 省电暂停不影响终端。

## 允许修改的文件

- `Sources/DesktopShell/TerminalPanel.swift`、`Sources/DesktopShell/TerminalBridge.swift`（新建）
- `Sources/DesktopShell/HotKey.swift`、`Sources/DesktopShell/Bridge.swift`、`Sources/DesktopShell/BridgeProtocol.swift`、`Sources/DesktopShell/AppDelegate.swift`（修改）
- `Sources/DesktopShell/TerminalSession.swift`（修改，只限接入时确实需要的小改动，在交付记录里说明）
- `Tests/DesktopShellTests/TerminalPanelTests.swift`、`Tests/DesktopShellTests/TerminalBridgeTests.swift`（新建）
- `Tests/DesktopShellTests/BridgeTests.swift`（修改）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改网页（`web/` 下的任何文件）。如果发现 M9-04 的页面和这里的约定对不上，停下来在交付记录里说明。
- 不调用 `NSApp.activate`；不让组件页往终端里写任何东西；日志不写终端内容。
- 不改 VideoWindow / WidgetWindow 的层级和行为。

## 验收标准

**可执行的检查**（实现者自测，审查者复验）：

- [ ] `swift build` 无错误、无警告
- [ ] `scripts/test.sh` 全部通过，新测试至少覆盖：
  - [ ] 面板位置函数：平时和放大两种，用 1792 × 1003 的 `visibleFrame`（原点 (0, 87)）时，平时是 x 16、宽 1760、高 451、顶边离 `visibleFrame` 顶 8；
  - [ ] 终端请求解析：五个动作的合法参数；多余的键、`cols` 为 0 或 1001、`data` 为空或超过 65536 个字符都是 `invalid`；
  - [ ] 组件页发终端动作是 `untrusted`；终端页发 `getConfig` 是 `untrusted`；
  - [ ] `terminalState` 推送的内容。
- [ ] `grep -n "Log\." Sources/DesktopShell/TerminalBridge.swift Sources/DesktopShell/TerminalPanel.swift`：没有一条带上输入输出的内容或长度
- [ ] `grep -rn "NSApp.activate\|activate(ignoringOtherApps" Sources` 没有输出
- [ ] `git diff --name-only main...task/M9-05` 只有上面"允许修改的文件"

**用户手动验证**（`scripts/bundle.sh --open` 打包启动；审查者同时开着 `/usr/bin/log stream --style compact --predicate 'subsystem == "local.desktopshell.DesktopShell"'` 对照日志）：

- [ ] **呼出**：在 Safari 里按 ⌥\` → 面板从顶部滑下，不点它直接敲 `echo 你好` 回车，能输入中文；Safari 仍是前台应用（菜单栏左边还是 Safari）。日志里有 `terminal hotkey registered ⌥``，没有权限弹框。
- [ ] **收起**：再按 ⌥\` → 面板收起，马上打字，字落在 Safari 里。在 Cursor 里重复这两步。
- [ ] **程序**：在面板里跑 `vim`（方向键、Esc、`:q!`）和 `codex`（交互一句，⌃C 退出）。
- [ ] **复制粘贴**：选中输出 ⌘C，再 ⌘V 粘回来。
- [ ] **放大**：点"放大"铺满屏幕，图标变成还原；收起再呼出仍是放大的；点"还原"恢复。
- [ ] **全屏应用**：把 Safari 切到全屏，在里面按 ⌥\`，面板盖在上面。
- [ ] **终端入口**（M9-01 已合并时）：回到桌面点"终端"入口，面板出现。
- [ ] **重开**：输入 `exit`，看到"[shell 已退出，按任意键重新开始]"，按一个键后出现新的提示符，行列数和面板一致（`stty size`）。
- [ ] **重新加载**：菜单栏"重新加载"后再呼出，屏幕上还是之前的内容，shell 没有重开。
- [ ] **多屏**（有外接屏时）：鼠标放在另一块屏幕上按 ⌥\`，面板出现在那块屏幕。
- [ ] 审查者核对日志：没有任何终端内容；面板显示期间点击桌面组件、访达图标照常工作。
- [ ] **补上 M9-01、M9-02 留下的"待确认"**（审查者先备份 `config.json`）：
  - 项目行只有"访达"，点它能在访达里打开；
  - 管理 → 编辑，改一个项目的名字并关联一个提醒事项列表，保存；
  - 审查者核对 `config.json`：名字和 `remindersListId` 写进去了，原有的顶层 `apps` 和项目的 `apps` 都还在；
  - 选中这个项目加一条待办，进了所选的列表。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**（2026-10-25）：
  - 新增惰性创建的全局终端面板与独立 WKWebView：原生毛玻璃、鼠标所在屏幕定位、普通 / 放大布局、160 ms 动画、最后一次显示请求生效、焦点交还及屏幕参数变化重排。
  - 新增终端专属 bridge，校验 WebView 身份、主框架、来源及五个动作的严格参数；组件页仅能无参数 `openTerminal`，终端动作从组件页进入时拒绝。输入限额按网页既有分块的 UTF-16 长度计数。
  - 接通 ready 启动、输出原始字节转 base64、重载期间缓冲和重放、退出后首键只重开、resize、状态推送；AppDelegate 负责快捷键、重载与退出清理，暂停动画不影响终端。
  - Carbon 注册支持失败回滚、重复启停及停止后旧回调失效。未修改 `TerminalSession.swift`、`web/` 或桌面窗口行为。
- **自测结果**：
  - `scripts/test.sh`：最终 **313/313**（32 suites）；新增与相关定向测试 **42/42**，覆盖尺寸 / 非法参数 / 权限隔离 / 事件内容 / ready 前拒绝输入 / 重载重放 / 退出重开 / 启动失败 / 布局和旧动画完成请求失效。
  - `scripts/test-web.sh`：**501/501**。`scripts/bundle.sh --debug` 中 `swift build` 无错误、无警告，固定证书 `DesktopShell Self-Signed` 打包、签名及指定要求验证通过。产物：`build/DesktopShell.app`。
  - 全量测试有一次在原有 `Log.writeStderr` 路径遇到 `NSFileHandleOperationException: Bad file descriptor`；同轮 `TodoItemsTests` 会临时重定向全进程 stderr，可能存在并发竞争。未改动该范围外代码；保留失败记录，随后完整复跑通过。不能把这次异常当作通过或认定已修复。
  - `git diff --check` 通过；新增 bridge / panel 日志仅有动作和错误码，无终端输入输出或长度；全 `Sources` 无 `NSApp.activate` / `activate(ignoringOtherApps`；变更仅在允许列表内。
  - HotKey 独立真实 Carbon API 编译（warnings-as-errors）及临时替身生命周期探针通过；未通过探针抢占真实快捷键。独立子代理完整差异自查未发现可确认的中高优先级问题；这仅属实现自查，不替代下面的正式审查。
  - 已实际启动固定证书新包，运行日志确认正确的包内 webDir、`terminal hotkey registered ⌥\``，桌面窗口层级仍为 widget=icon+3 / video=icon-1。经用户同意，用活动监视器正常退出旧副本（PID 600）；新副本保留运行。
  - 用户反馈“能呼出并正常输出”。但本轮自动化键盘未触发全局快捷键，工具只定位到壁纸窗口，且 Safari 仍有 M9-04 终端预览页；截至记录时未取得对应 PTY 启动日志佐证，故原生呼出 / 中文输入仍待补充核对，未据此勾选验收。其余焦点交还、vim/codex、复制粘贴、放大保留、全屏、原生入口、exit 重开、菜单重载、多屏与 M9-01/02 的 Finder / 提醒事项真实验收仍待正式审查逐项完成。
  - 本地日志与过程记录：`build/m9-validation/M9-05/`（忽略目录，不随源码提交），包括基线、失败全量、通过复跑、定向测试、网页测试、打包和原生应用日志。
- **疑问 / 偏离**：无接口或范围偏离；本次只交付任务分支，未合并 main。真实桌面验收与跨会话正式审查仍未完成。

<!-- ===== 以下由审查者填写（Claude Code，或没参与实现的另一个 Codex 会话） ===== -->

## 审查记录

- **审查者**：
- **结论**：
- **意见**：
