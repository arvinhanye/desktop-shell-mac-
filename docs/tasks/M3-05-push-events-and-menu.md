# M3-05: Swift → 网页推送（安全区域、暂停、外观）、遮挡防抖与菜单栏补全

- **状态**：todo
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
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
