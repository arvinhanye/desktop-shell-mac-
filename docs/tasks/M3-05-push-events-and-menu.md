# M3-05: Swift → 网页推送（安全区域、暂停、外观）、遮挡防抖与菜单栏补全

- **状态**：review
- **里程碑**：M3
- **依赖**：M3-04（必须已合并到 `main`）
- **分支**：task/M3-05

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

Swift 主动把 `safeArea`、`paused`、`uiState` 推送给网页：组件布局在真实的安全区域里，暂停时网页动画跟着停，菜单栏切换语音开关时网页立刻知道。遮挡暂停加上 1 秒防抖，全屏切换时不再频繁启停。菜单栏补上"点击语音""重新加载""打开配置文件夹"三项。

## 背景与约束

- 先读 `AGENTS.md`："Bridge 接口"的"Swift → 网页"表和"通信方式"、窗口要求的"安全区域"、省电要求（**遮挡防抖**）、核心架构里的菜单栏。
- M2-05 审查时的观察：全屏切换桌面、打开文件弹窗时，遮挡状态会闪烁（最短 9 毫秒）。防抖规则当时写进了 `AGENTS.md`，在本任务实现。
- 推送事件的格式是平铺的字典，`event` 字段是事件名（M3-01 的 `applyEvent` 按这个格式解析）。
- **不轮询**：防抖用一次性的延迟任务，不用 `Timer` 反复检查。

### 1. 推送通道（`WebContainer.swift`、`DesktopWindow.swift`）

- `WebContainer.send(_ event: [String: Any])`：用
  `webView.callAsyncJavaScript("window.shell?.receive?.(event)", arguments: ["event": event], in: nil, in: .page)`。
  **不要**用 `evaluateJavaScript` 拼接字符串（参数通过 `arguments` 传，不会有注入问题）。失败时记录日志，每次页面加载最多记一次，避免刷屏。
- `WebContainer` 在 `webView(_:didFinish:)` 时调用 `onPageLoaded` 回调（每次加载都调用，包括重新加载）。
- `WebContainer.reload()`：重新加载 `shell://app/index.html`。
- `WidgetWindow` 把 `send`、`reload`、`onPageLoaded` 转给自己的 `WebContainer`。

### 2. 事件内容（`BridgeProtocol.swift`，纯函数）

```swift
enum PageEvent {
    static func safeArea(_ insets: SafeAreaInsets) -> [String: Any]
    static func paused(_ paused: Bool) -> [String: Any]
    static func uiState(_ state: UiState) -> [String: Any]
}
```

| 事件 | 内容 |
|---|---|
| `safeArea` | `{"event": "safeArea", "top": …, "right": …, "bottom": …, "left": …}`（数字，CSS 像素，和 `SafeAreaInsets` 一致） |
| `paused` | `{"event": "paused", "paused": true}` |
| `uiState` | `{"event": "uiState", "avatarId": "12" 或 null, "backgroundId": … 或 null, "voiceEnabled": true}`——为空时写 `NSNull()`，不省略；**不包含** `desktopIconsHidden` |

### 3. 广播与重推（`ScreenManager.swift`）

- `broadcast(_ event: [String: Any])`：发给所有 WidgetWindow。事件名是 `paused`、`uiState`、`systemStats`（M3-06 用）、`todos`（M3-07 用）时，同时按事件名缓存最新的一份。还没有窗口时只缓存。
- 某个窗口的页面加载完成（`onPageLoaded`）时，按顺序给**这个页面**推送：它自己的 `safeArea` → 缓存的 `paused` → `uiState` → `systemStats` → `todos`（有缓存的才推）。这样新接入的屏幕、重新加载后的页面都能拿到当前状态。
- 屏幕参数变化时，某个窗口的安全区域和上次推送的不一样，就给这个窗口推送新的 `safeArea`。
- `reloadPages()`：让所有 WidgetWindow 重新加载页面。

### 4. 暂停推送与遮挡防抖

- `PowerMonitor` 增加 `var onPausedChanged: ((Bool) -> Void)?`：总的暂停状态（`reasons` 是否为空）**第一次确定时调用一次**，之后每次变化调用一次；只有原因变化、暂停与否没变时不调用。`AppDelegate` 在 `monitor.start()` **之前**接好：`broadcast(PageEvent.paused(…))`。
- 新建 `OcclusionDebouncer.swift`：

  ```swift
  @MainActor
  final class OcclusionDebouncer {
      typealias Schedule = (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> () -> Void   // 返回取消函数
      init(delay: TimeInterval = 1.0, schedule: @escaping Schedule = <默认：主队列 asyncAfter + DispatchWorkItem>)
      var onChange: ((Bool) -> Void)?
      private(set) var isOccluded: Bool      // 防抖后的结果，初始为 false
      func update(rawOccluded: Bool)
      func cancel()                          // 取消待执行的任务，并把 isOccluded 重置为 false（不触发 onChange）
  }
  ```

  | 当前状态 | 输入 | 动作 |
  |---|---|---|
  | 未遮挡、没有待执行任务 | `true` | 安排 `delay` 秒后执行 |
  | 未遮挡、已有待执行任务 | `true` | 什么都不做（**不重新计时**） |
  | 未遮挡、已有待执行任务 | `false` | 取消任务 |
  | 待执行任务到期 | — | `isOccluded = true`，`onChange(true)` |
  | 已遮挡 | `false` | **立即** `isOccluded = false`，`onChange(false)` |
  | 已遮挡 | `true` | 什么都不做 |

  取消之后，即使延迟任务仍然被执行，也不能产生任何效果（用代号或标记保证）。
- `PowerMonitor.updateOcclusion()` 现在算出的"全部遮挡"作为原始值交给防抖器，防抖器的 `onChange` 再写 `state.allWindowsOccluded` 并 `applyPolicy()`。"收到第一次遮挡通知之前按可见处理"的现有逻辑不变。`stop()` 时调用 `cancel()`。

### 5. 外观推送

- `AppState` 增加 `var onUiStateChanged: ((UiState) -> Void)?`：`saveUiState` 成功后、语音开关切换后调用（切换"隐藏桌面文件"**不**调用，网页不关心）。`AppDelegate` 把它接到 `broadcast(PageEvent.uiState(…))`。
- 启动时 `AppDelegate` 先广播一次当前 `uiState`（这时还没有窗口，只是写进缓存，页面加载完成后会重推）。

### 6. 菜单栏

```
暂停动画
隐藏桌面文件
点击语音            ← 新增，勾选 = voiceEnabled
──────────
重新加载            ← 新增
打开配置文件夹      ← 新增
──────────
退出 DesktopShell
```

- **点击语音**：启动时按 `uiState.voiceEnabled` 设置勾选。点击时切换、保存 `ui.json`（失败只记日志，不影响切换）、触发 `onUiStateChanged`。日志 `DesktopShell: voice enabled=true/false`。
- **重新加载**：`AppState` 增加 `reloadConfig()`，重新读 `config.json`；读取失败时保留当前配置并 `Log.error`。然后 `reloadPages()`。日志 `DesktopShell: reloaded config and pages`。背景视频不跟着换（改 `background.video` 仍需重启应用，这一点写进日志说明即可）。
- **打开配置文件夹**：支持目录不存在时先创建，然后 `NSWorkspace.shared.open(支持目录)`。

### 7. 测试

- `OcclusionDebouncerTests.swift`：用假的 `schedule`（记下任务，由测试手动触发）验证上表每一行；短暂遮挡（任务到期前就恢复）不触发 `onChange`；连续多次 `true` 只安排一次；被取消的任务即使被触发也没有效果；`cancel()` 之后状态回到未遮挡。
- `PageEventTests.swift`：三个事件的键和值；`uiState` 为空的字段是 `NSNull`；不含 `desktopIconsHidden`。

## 允许修改的文件

- `Sources/DesktopShell/WebContainer.swift`、`DesktopWindow.swift`、`ScreenManager.swift`（修改）
- `Sources/DesktopShell/PowerMonitor.swift`（修改：`onPausedChanged`、接入防抖）
- `Sources/DesktopShell/OcclusionDebouncer.swift`（新建）
- `Sources/DesktopShell/BridgeProtocol.swift`（修改：`PageEvent`）
- `Sources/DesktopShell/AppState.swift`、`AppDelegate.swift`、`Bridge.swift`（修改）
- `Tests/DesktopShellTests/OcclusionDebouncerTests.swift`、`PageEventTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不修改 `PowerPolicy`（暂停原因的计算规则不变）、`HitTesting`、`HitTestController`。
- 不修改 `web/` 下的任何文件。
- 不推送 `audioSpectrum`（M5.5）、`systemStats`（M3-06）和 `todos`（M3-07）。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过，包含上面列出的新测试；`scripts/test-web.sh` 仍然全部通过
- [ ] `git diff --name-only main...task/M3-05` 只包含"允许修改的文件"
- [ ] `grep -n "callAsyncJavaScript" Sources/DesktopShell/WebContainer.swift` 有输出；`grep -rn "evaluateJavaScript" Sources/` 没有输出
- [ ] `grep -n "Timer" Sources/DesktopShell/PowerMonitor.swift Sources/DesktopShell/OcclusionDebouncer.swift` 没有输出
- [ ] `scripts/bundle.sh --open` 启动后 5 秒内，日志里 `DesktopShell power:` 只有一行 `paused=false reasons=[]`，没有 `occluded`

**用户手动验证**（`scripts/bundle.sh --open`，用自检面板）：

- [ ] 自检面板显示的 `safeArea` 上边等于菜单栏高度、下边等于程序坞高度；勾"显示安全区域"，虚线框正好避开菜单栏和程序坞；面板本身不再被菜单栏挡住
- [ ] 改变程序坞大小或打开"自动隐藏"：面板上的数字和虚线框立刻跟着变，不需要重新加载
- [ ] 菜单栏勾"暂停动画"：面板 `paused = true`（黄色）；取消后变回 `false`
- [ ] 打开一个全屏应用停留 3 秒再切回：Claude Code 查日志，能看到 `paused=true reasons=[occluded]`，而且它和切换动作之间至少隔了 1 秒；随后恢复为 `paused=false`。在全屏应用和桌面之间快速来回切换（每次停留不到 1 秒）：不出现 `occluded`
- [ ] 菜单栏"点击语音"：勾选状态和 `ui.json` 一致；点击后面板的 `voiceEnabled` 立刻变化，`ui.json` 跟着变；重启后保持
- [ ] 把 `config.json` 里 `character.name` 改成别的名字 → 菜单栏"重新加载" → 面板显示新名字（验证后改回来）
- [ ] 菜单栏"打开配置文件夹"：访达打开 `~/Library/Application Support/DesktopShell/`
- [ ] 回归：点击穿透、"隐藏桌面文件"、自检面板的按钮都和 M3-04 时一样

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
  - 新增平铺的 `PageEvent`；通过 `callAsyncJavaScript` 的 arguments 推送，页面加载内发送错误最多记录一次，旧页面的异步回调由加载代号隔离。
  - `ScreenManager` 广播并缓存最新状态，首载、重载和新窗口按各自 safeArea → paused → uiState → systemStats → todos 顺序重推；未缓存的事件跳过。安全区域未变化不重复发送。后两类仅预留缓存能力，没有实际生产者或推送。
  - 新增可注入调度器的 `OcclusionDebouncer`：持续遮挡一秒才暂停，恢复立即生效，重复遮挡不重置计时，取消/停止后的旧任务不产生效果。`PowerMonitor` 首次及总暂停状态变化时才通知网页。
  - 成功保存外观及切换语音后广播 `uiState`；隐藏桌面文件只持久化、不通知网页。补齐语音开关、重新读取配置并加载页面、创建并打开配置目录的菜单项。配置读取失败保留当前值，语音写盘失败保留本次开关选择。
- **自测结果**：
  - **RED → GREEN**：新增纯函数/状态测试先以空实现确认事件内容、缓存、防抖、通知、重读配置等行为断言失败，再完成实现。真实 WKWebView 也先复现页面 safeArea 全零（原生为 top=30、bottom=83），最终初始推送与 CSS 变量均通过。
  - **PASS**：`scripts/test.sh` **116/116，14 suites**（新增 14 项）；`scripts/test-web.sh` **138/138**；`swift build` 无 warning/error；`git diff --check` 通过。没有改动网页、暂停策略或点击穿透逻辑。
  - **PASS**：独立只读审查发现 1 项配置缺失重载边界；新增 `missingReloadConfig` 先确认两条断言失败，再修复为保留最后有效配置且不生成示例，完整测试通过。无剩余已知审查问题。
  - **PASS**：临时真实 AppKit/WKWebView 探针 **33/33**：实际菜单顺序和 selector、首次安全区域和 CSS、暂停去重、语音写盘、隐藏图标不广播、配置重读、按顺序重推、页面独立加载、安全区域去重、默认一秒延迟/立即恢复/停止取消/重启初始状态。连续发送失败在两个页面加载周期内恰好记录 2 次，未记录异常携带的内容。
  - **PASS**：`scripts/bundle.sh --open` Release 打包、固定证书签名及严格校验；应用 PID **11791**，2026-10-18 03:17:19 启动，首 5 秒 power 日志仅 `paused=false reasons=[]` 一行，没有 `occluded`。实际读取 30 个头像、63 个背景。
  - **PASS**：`callAsyncJavaScript` 静态检查；Sources 中没有 `evaluateJavaScript`；PowerMonitor/OcclusionDebouncer 中没有 `Timer`；改动文件限定于任务允许列表。
  - **待手动验收**：实际 Dock 大小/自动隐藏与虚线框位置、全屏/快速切屏体验、多屏接入、Finder 打开配置目录、真实鼠标点击穿透/框选，以及菜单视觉与应用重启后的体验。原生 selector 和模拟通知测试不替代这些 GUI 验收。
  - 详细临时证据：`/tmp/ds-m3-05-validation/`（`red-swift.log`、`swift-final.log`、`web-final.log`、`missing-config-red.log`、`native-baseline-red.log`、`native-green.log`、`bundle-final.log`、`app-startup.log`）。
- **疑问 / 偏离**：
  - 实测本机 `shell://` 页面的 `didFinish` 早于 ES module 初始化，立即调用 receive 会静默丢失首批事件。现在该回调先等待现有 `/js/main.js` 的模块导入完成，再通知页面就绪；模块缓存避免重复初始化，无轮询、无网页变更、无新增 Bridge 动作。
  - 无接口扩展；本次只推送 safeArea/paused/uiState，未提前实现 systemStats/todos/audioSpectrum。改背景视频仍需重启，重新加载日志已明确说明。
  - 按用户要求推送 `task/M3-05`，不合并 `main`；本单保留 `review` 等待 Claude Code 复验及用户手动验收。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**代码审查通过，待用户手动验证**（见"用户手动验证"）。用户确认后合并到 `main`。
- **复验结果**（Claude Code，2026-10-18，在 `cfc2d80` 的独立检出上执行）：
  - [x] `swift build` 零警告零错误
  - [x] `scripts/test.sh`：116 项全部通过（14 个 suite）；`scripts/test-web.sh`：138 项全部通过
  - [x] 改动文件都在允许范围内（`Bridge.swift` 没有改动，外观推送通过 `AppState.onUiStateChanged` 完成）；`web/`、`PowerPolicy`、`HitTesting`、`HitTestController` 都没改；`git diff --check` 通过
  - [x] `WebContainer.swift` 里有 `callAsyncJavaScript`；`Sources/` 里没有 `evaluateJavaScript`；`PowerMonitor` 和 `OcclusionDebouncer` 里没有 `Timer`
  - [x] 在主目录（`task/M3-05` = `cfc2d80`）重新 `scripts/bundle.sh --open`：启动后 5 秒内 `DesktopShell power:` 只有一行 `paused=false reasons=[]`，没有 `occluded`，也没有推送失败的日志
- **意见**：
  - 推送用 `arguments` 传参，不拼接 JS；每次页面加载有一个代号，旧页面的异步回调和失败日志互不干扰，失败日志每次加载最多一条且不含内容。
  - **页面就绪的判断**：Codex 实测发现 `shell://` 页面的 `didFinish` 可能早于 ES module 初始化，这时推送的事件会丢。改为在 `didFinish` 后执行 `await import('/js/main.js')`——它会等入口模块（包括顶层 `await`）执行完，不会重复执行，也不需要新的 Bridge 动作。代价是首批推送要等 `main.js` 整个跑完（组件挂载完、`getConfig` 返回之后）。**写进 M4 的要求**：组件的 `mount` 不要等待耗时操作（例如图片加载完成），否则会推迟首批推送（安全区域、暂停状态等）。
  - `PageEventCache` 只缓存四类事件，重推顺序固定为 `safeArea → paused → uiState → systemStats → todos`；安全区域没变化时不重复推送。
  - `OcclusionDebouncer` 和任务单的状态表一致：重复遮挡不重新计时，恢复立即生效，取消后用代号保证旧任务即使被执行也没有效果；`PowerMonitor.stop()` 时取消并重置。暂停通知只在第一次确定和暂停与否真正变化时发出。
  - "重新加载"在配置文件不存在时保留当前配置（不会生成示例覆盖），读取失败只记日志；语音开关写盘失败时保留本次选择。
