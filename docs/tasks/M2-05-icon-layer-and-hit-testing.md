# M2-05: 保留访达图标——窗口拆分与点击穿透

- **状态**：done
- **里程碑**：M2（方案调整：保留访达桌面图标）
- **依赖**：M2-04（已合并）。与 M2.5-01 互不影响，两者改的文件不重叠，按 Codex 一次做一个的规则先后完成即可。
- **分支**：task/M2-05

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

把每块屏幕的桌面窗口拆成上下两个，把访达的桌面图标夹在中间：图标显示在视频之上，可以正常选中、框选、拖动、双击打开；网页组件仍然在最上面，鼠标在组件上时可以点。

## 背景与约束

- 先读 `AGENTS.md` 的"核心架构""窗口要求"（点击穿透部分）、"省电要求"（遮挡部分）、"Bridge 接口"（`setHitRegions`），以及"技术探针"里"点击穿透"那一行。**做法已经由 Claude Code 用探针验证过**，照着做即可。
- 本机实测层级：访达图标 = `CGWindowLevelForKey(.desktopIconWindow)`（-2147483603）。

### 1. 两种窗口（`DesktopWindow.swift`）

- **`VideoWindow`**：层级 = 图标层 −1；不透明，背景黑色；`ignoresMouseEvents = true`；内容只有 `BackgroundPlayer.makeVideoView()`。
- **`WidgetWindow`**（原 `DesktopWindow` 改名或改造）：层级 = 图标层 +1；`isOpaque = false`、`backgroundColor = .clear`、`hasShadow = false`；内容只有 `WebContainer` 的 WKWebView；**初始 `ignoresMouseEvents = true`**（收到组件区域并且鼠标在区域内时才改为 `false`）。保留 `updateSafeArea(_:)` 和 `safeAreaInsets`。
- 两者的 `collectionBehavior` 都是 `[.canJoinAllSpaces, .stationary, .ignoresCycle]`，`isReleasedWhenClosed = false`，`frame` 等于屏幕的 `frame`。
- 本任务**不重写** `canBecomeKey`（键盘输入在 M4 处理）。

### 2. `ScreenManager.swift`

- 每块屏幕管理一对窗口（按显示器 ID）：先 `orderFront` VideoWindow，再 `orderFront` WidgetWindow。屏幕增删时成对增删，分辨率变化时两个窗口都更新 `frame`。
- `onWindowsChanged` 改为传出当前所有 **VideoWindow**（给 `PowerMonitor` 判断遮挡）。
- 另外提供当前所有 WidgetWindow 的列表，给 `HitTestController` 使用（回调或属性均可）。

### 3. 点击穿透

**纯逻辑 `HitTesting.swift`**（配单元测试）：

```swift
enum HitTesting {
    /// body 是网页 postMessage 的 regions 字段。格式不对返回 nil（整条忽略）。
    static func parseRegions(_ value: Any?, viewport: CGSize) -> [CGRect]?
    /// mouse 是全局屏幕坐标（NSEvent.mouseLocation，原点左下）；windowFrame 是窗口在全局坐标里的 frame；
    /// regions 是网页坐标（原点左上，CSS 像素 = 点）。
    static func isInteractive(mouse: CGPoint, windowFrame: CGRect, regions: [CGRect]) -> Bool
}
```

- `parseRegions`：必须是数组，每项是 4 个数字 `[x, y, w, h]`；任何一个数不是有限数（NaN、无穷大），或 `w <= 0`、`h <= 0`，或数量超过 64 个，都**整条返回 nil**；合法的矩形与 `CGRect(origin: .zero, size: viewport)` 求交集，交集为空的丢掉。空数组是合法的（表示没有可交互区域）。
- `isInteractive`：先换算成网页坐标 `x = mouse.x - windowFrame.minX`、`y = windowFrame.maxY - mouse.y`，落在任何一个区域内（包含左边和上边，不包含右边和下边，即 `CGRect.contains` 的语义）返回 `true`。光标不在这个窗口里时返回 `false`。

**`HitTestController.swift`**（`@MainActor`）：

- 用 `NSEvent.addGlobalMonitorForEvents` 和 `addLocalMonitorForEvents` 监听 `[.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp]`，本地监听要把事件原样返回。
- 每次事件、每次某个窗口的区域更新、每次窗口列表变化时，重新判断**每个** WidgetWindow：`NSEvent.pressedMouseButtons != 0` 时不切换（按住鼠标期间保持原状）；否则 `ignoresMouseEvents = !isInteractive(...)`，只有值变化时才赋值。
- 退出时移除两个监听。
- **不用定时器轮询鼠标位置。**

### 4. Bridge 的第一个动作（`Bridge.swift`）

- 新建 `Bridge.swift`：一个 `WKScriptMessageHandler`，注册名为 **`shell`**（`AGENTS.md` 规定的唯一入口）。每个 WidgetWindow 的 WebContainer 各注册一个实例，绑定到自己的窗口。
- `WKUserContentController` 会**强引用**消息处理器，用一个弱引用的中转对象注册，避免循环引用导致窗口无法释放。
- 消息体必须是字典，`action` 是字符串。本任务只处理 `setHitRegions`：用 `HitTesting.parseRegions(body["regions"], viewport: webView.bounds.size)` 解析，成功就替换这个窗口的区域，并通知 `HitTestController` 重新判断；解析失败就 `NSLog` 记录并保持原有区域不变。
- **其他任何 action 一律忽略，并 `NSLog("DesktopShell bridge: 忽略未知 action %@", ...)`**。M3 再按白名单扩展其他动作。

### 5. 遮挡判断与启动瞬态（`PowerMonitor.swift`）

- 只看 VideoWindow 的遮挡状态（WidgetWindow 是透明的，不参与判断）。
- **修复 M2-04 审查发现的启动瞬态**：窗口刚显示、还没收到它自己的第一次 `didChangeOcclusionStateNotification` 之前，按"可见"处理。启动日志里不应再出现 `paused=true reasons=[occluded]`。
- 其他行为保持不变：全屏应用遮挡时暂停、屏幕睡眠、切换用户、低电量、手动暂停。

### 6. M2 测试页（`web/index.html`）

- 页面加载后、以及窗口尺寸变化时，把测试面板的矩形用 `webkit.messageHandlers.shell.postMessage({action: 'setHitRegions', regions: [[x, y, w, h]]})` 上报（用 `getBoundingClientRect()`）。
- 测试页的其余内容（心形图、ES module、路径穿越、播放测试语音按钮）保持不变。

### 7. 测试（`Tests/DesktopShellTests/HitTestingTests.swift`）

- `parseRegions`：合法输入；空数组；非数组、某项不是 4 个数、含字符串；NaN、无穷大；宽或高 ≤ 0；65 个区域；部分超出视口被裁剪；完全在视口外被丢弃。
- `isInteractive`：区域内、区域外、左上边界（含）、右下边界（不含）；窗口不在原点（例如副屏 `frame` 为 `(1792, -200, 1920, 1080)`）时的坐标换算；光标在窗口外；多个区域。

## 允许修改的文件

- `Sources/DesktopShell/DesktopWindow.swift`（修改）
- `Sources/DesktopShell/ScreenManager.swift`（修改）
- `Sources/DesktopShell/PowerMonitor.swift`（修改）
- `Sources/DesktopShell/WebContainer.swift`（修改：注册 `shell` 消息处理器）
- `Sources/DesktopShell/AppDelegate.swift`（修改：创建并接线 `HitTestController`）
- `Sources/DesktopShell/HitTesting.swift`（新建）
- `Sources/DesktopShell/HitTestController.swift`（新建）
- `Sources/DesktopShell/Bridge.swift`（新建）
- `web/index.html`（修改）
- `Tests/DesktopShellTests/HitTestingTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"，**不修改访达或任何系统设置**（不运行 `defaults write com.apple.finder`、不 `killall Finder`）。
- Bridge 只实现 `setHitRegions`，不实现白名单里的其他动作。
- 不用定时器轮询鼠标位置；不申请辅助功能等系统权限；不使用 `CGEventTap`。
- 不修改 M2-02 的逻辑文件（`AppPaths`、`Config`、`ConfigStore`、`SchemeResolver`）和 `BackgroundPlayer`、`ShellSchemeHandler`。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过，交付记录里列出新增测试的数量
- [ ] `git diff --name-only main...task/M2-05` 只包含"允许修改的文件"
- [ ] `grep -rnE "Timer|asyncAfter|CGEventTap|AXIsProcessTrusted" Sources/DesktopShell/HitTest*.swift Sources/DesktopShell/Bridge.swift` 没有输出
- [ ] 运行后用 `CGWindowListCopyWindowInfo` 检查：每块屏幕有两个 DesktopShell 窗口，层级分别为 −2147483604 和 −2147483602，访达的图标窗口（−2147483603）夹在中间
- [ ] 启动日志里**没有** `paused=true reasons=[occluded]`（启动瞬态已修复）；`DESKTOPSHELL_FAKE_BATTERY=15` 时仍然是 `reasons=[lowBattery]`

**用户手动验证**（运行 `.build/debug/DesktopShell`）：

- [ ] 桌面文件图标显示在爱弥斯视频**上面**
- [ ] 单击图标能选中，空白处能拖出选择框，双击能打开文件，右键空白处能弹出访达的菜单
- [ ] 测试面板仍然可以操作：点"播放测试语音"能听到声音
- [ ] 先让别的应用成为前台，再点一次测试面板的按钮，能立刻生效
- [ ] 从空白处开始拖选择框、拖动时经过测试面板，选择框不会被打断
- [ ] 菜单栏"暂停动画"仍然有效；把一个应用切到全屏时视频仍然会暂停（日志 `reasons=[occluded]`），退出全屏后恢复

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
  - 每块屏幕改为一对窗口：不透明且忽略鼠标的 VideoWindow 位于图标层 −1；透明 WidgetWindow 位于图标层 +1，仅容纳一个 WKWebView，初始点击穿透。保留安全区域，没有提前实现键盘输入。
  - ScreenManager 按显示器 ID 成对创建、更新和关闭窗口，先显示视频、再显示组件，分别回传 VideoWindow 与 WidgetWindow 列表。PowerMonitor 仅观察视频窗口，每个新窗口在收到自己的首次遮挡通知前视为可见；重复列表更新保留已观察状态，移除窗口时清理对应记录。
  - 新增 HitTesting：严格校验至多 64 个四元数值矩形，拒绝布尔值、非有限数及非正尺寸；非法条目使整条消息失效，合法区域裁到视口。全局坐标换算为网页左上原点，窗口和区域边界均按左上包含、右下排除处理。
  - 新增 HitTestController：使用全局及本地鼠标事件监听，事件、区域变化和窗口列表变化都会重新判断全部组件窗口；任一鼠标按钮按住时保持原状态，松开再计算。本地监听原样返回事件，状态值不变时不重复赋值，退出移除监听。
  - 每个 WebContainer 注册唯一的 shell handler，通过弱引用中转连接本窗口的 Bridge；仅实现 setHitRegions，非法消息保持旧区域，未知 action 记录日志后忽略。关闭窗口停止加载并移除 handler，退出断开回调和监听。
  - 测试页在加载、窗口 resize 和面板尺寸变化时上报矩形；ResizeObserver 同时覆盖图片加载及错误提示导致的布局变化。原有图片、模块、路径检查及播放语音逻辑保留。
- **自测结果**（2026-10-17）：
  - 从最新且与 origin/main 一致的 `main`（`6989759`）创建 `task/M2-05`。基线 **49/49**；新增 **14 个 HitTesting 测试声明**，空实现触发 11 条预期断言失败；实现后及最终 `scripts/test.sh` 均 **63/63 通过**，共 7 个 suite。
  - 新测试覆盖合法/空输入、错误结构和类型、布尔桥接、NaN/无穷大、非正尺寸、64/65 数量边界、裁剪及完全越界、极大有限尺寸、区域左右上下边界、副屏负坐标、窗口外光标和多个区域。
  - `swift build` 退出码 0，日志经 `grep -iE 'warning|error'` 检查无输出。规定的 `Timer|asyncAfter|CGEventTap|AXIsProcessTrusted` 扫描无输出；`git diff --check` 通过；受保护的逻辑文件及 AGENTS.md、CLAUDE.md 均未改动。
  - 实际 `.build/debug/DesktopShell` 分别以模拟电量 80 和 15 启动，复用 `/tmp/ds-support`，测试后结束各自进程。`CGWindowListCopyWindowInfo` 在本机一块屏幕上实际读到：WidgetWindow **−2147483602**、Finder 图标 **−2147483603**、VideoWindow **−2147483604**，三者边界均为 1792×1120。
  - 正常启动日志为 `paused=false reasons=[]`，没有启动时的 `paused=true reasons=[occluded]`；15% 启动日志为 `paused=true reasons=[lowBattery]`。
  - 临时原生 `IntegrationChecks.swift`：**16/16 通过**。验证实际窗口对、初始穿透、启动状态、原有模块/404 检查、页面自动上报、真实 WK 消息注册及区域替换、非法/未知消息保留旧状态、菜单暂停调用链和退出关闭。消息边界测试使用独立临时页面，隔离真实页面 ResizeObserver 的异步重报。
  - 临时 `HitStateChecks.swift`：**15/15 通过**。在独立进程内替换 NSEvent 的位置/按键读取并向本地队列投递事件，验证跨窗口重算、事件原样传递、拖动和区域更新期间冻结、多按钮依次松开、窗口替换、停止监听以及弱引用释放。保留 WKUserContentController 而释放窗口也成功；未移动真实鼠标、未操作桌面文件。
  - 复用并扩展 M2-04 的原生省电检查：**23/23 通过**。实际 AppKit 窗口隐藏/显示通知及 AVPlayer 状态验证遮挡暂停/恢复；同时覆盖各暂停原因、首次通知前可见、收到隐藏通知后暂停、列表刷新保留状态、移除后重新加入、停止释放及低电量。睡眠/会话及新增隐藏窗口的通知在测试进程内模拟，没有让系统休眠或切换用户。
  - 独立只读代码检查覆盖全部 11 个修改/新增文件，未发现已确认的 Critical / Important / Minor 缺陷；正式审查由 Claude Code 进行。完整日志、WindowServer 数据和临时检查源文件位于 `/tmp/ds-m2-05-validation/`。
- **疑问 / 偏离**：
  - 无需求或修改范围偏离。仅修改允许的 10 个实现/测试文件及本任务状态、交付记录，没有修改任务需求和审查记录。
  - 本机只验证了一块真实屏幕。实际多屏接入/拔出、分辨率变化、其他应用全屏及首次遮挡通知的时序仍需手动复验。
  - 真实访达图标的选择/框选/拖动/双击/右键、跨应用首次点按钮、语音听感，以及点击组件后移动到空白处能否立即恢复穿透，仍按上方手动清单验收；进程内事件模拟不等于真实系统鼠标路由已验收。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**通过**，已合并到 `main`。用户手动验证全部正常：图标显示在视频之上，可以选中、框选、双击打开、右键；测试语音能播放；从其他应用点一次就生效；框选经过面板不会被打断；手动暂停和全屏遮挡暂停都有效。
- **验收时的观察**：测试那一分半钟里出现了二十多次短暂的 `occluded`（最短 9 毫秒）。Claude Code 用只读观察程序对照后确认，平时切换应用不会触发，这些都发生在全屏切换桌面、打开文件弹窗时，属于桌面真的被盖住以及过渡动画，判断本身正确。为了避免 M3/M5.5 里网页动画和音频捕获被频繁启停，`AGENTS.md` 新增**遮挡防抖**规则（遮挡持续 1 秒以上才暂停，恢复立即生效），在 M3 实现。
- **复验结果**（Claude Code，2026-10-17）：
  - [x] touch 源码后强制重编，零警告零错误；`scripts/test.sh` 63/63 通过（新增 14 个）
  - [x] 改动范围是 10 个允许的文件和本任务单；M2-02 的逻辑文件、`BackgroundPlayer`、`ShellSchemeHandler`、`AGENTS.md`、`CLAUDE.md` 都没有改动
  - [x] `HitTest*.swift`、`Bridge.swift` 里没有 `Timer`、`asyncAfter`、`CGEventTap`、`AXIsProcessTrusted`
  - [x] 运行时窗口层级：DesktopShell 组件窗口 −2147483602 → **访达图标 −2147483603** → DesktopShell 视频窗口 −2147483604，系统小组件 −2147483601 仍在最上面
  - [x] 启动日志只有 `paused=false reasons=[]`，**启动瞬态已修复**
  - [x] CPU（去掉首样本）1.9%，和拆分前持平
- **意见**：
  - `HitTesting` 校验严格（布尔值、非有限数、非正尺寸、数量上限都会让整条消息作废），坐标换算和边界语义正确；`HitTestController` 按住鼠标时冻结状态、只在值变化时才赋值，不轮询。
  - Bridge 用弱引用中转注册，网页在窗口绑定之后才加载，关闭窗口时移除处理器，生命周期处理完整。
  - **写进 M3 任务单的要求**：M3 给 Bridge 加上 `launchApp`、`saveTodos` 这类有实际作用的动作时，要校验消息来自 `shell://app` 的主框架（`message.frameInfo.isMainFrame` 加上 `securityOrigin` 的 scheme 和 host）。现在只有无害的 `setHitRegions`，不阻塞。
  - 边缘情况（不阻塞）：如果启动时已经有全屏应用遮住桌面，系统可能不会发第一次遮挡通知，视频会继续播放，直到下一次遮挡变化（例如退出全屏）才暂停。影响很小，先记下。
