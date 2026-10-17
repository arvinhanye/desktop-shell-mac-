# M2-04: 省电暂停规则

- **状态**：todo
- **里程碑**：M2
- **依赖**：M2-03（必须已合并到 `main`）
- **分支**：task/M2-04

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

按 `AGENTS.md`"省电要求"，在下列情况自动暂停背景视频，条件解除后自动恢复：窗口全部被遮挡、屏幕睡眠、用户切换走、使用电池且电量低于 20%、菜单栏手动暂停。每次状态变化都打印日志，说明暂停原因。

## 背景与约束

- 先读 `AGENTS.md` 的"省电要求"和"开发环境"（单元测试部分），以及 M2-03 的 `BackgroundPlayer`。
- 本任务只控制**背景视频**。通知网页（`store.paused`）属于 M3 的 bridge，现在不做；系统音频捕获属于 M5.5。但判断逻辑要写成能直接复用的形式。

### 1. 判断逻辑（纯函数，`PowerPolicy.swift`）

```swift
struct PowerState: Equatable {
    var allWindowsOccluded = false
    var screensAsleep = false
    var sessionInactive = false
    var battery = BatteryStatus.unknown
    var manualPause = false
}
enum PauseReason: String, CaseIterable { case occluded, screensAsleep, sessionInactive, lowBattery, manual }
func pauseReasons(for state: PowerState) -> Set<PauseReason>   // 为空表示不暂停
```

`lowBattery` 的条件：`battery.onBattery && battery.level != nil && battery.level! < 20`。

### 2. 电量读取（`SystemStats.swift`，本任务只做电量部分；CPU 和内存在后续里程碑加）

```swift
struct BatteryStatus: Equatable {
    var level: Int?        // 0–100；没有电池时为 nil
    var isCharging: Bool
    var onBattery: Bool    // 正在使用电池供电
    static let unknown = BatteryStatus(level: nil, isCharging: false, onBattery: false)
}
enum SystemStats {
    static func parseBattery(_ sources: [[String: Any]]) -> BatteryStatus   // 纯函数，供测试
    static func readBattery() -> BatteryStatus                               // 调用 IOPSCopyPowerSourcesInfo，再交给 parseBattery
}
```

- 只看 `kIOPSTypeKey == kIOPSInternalBatteryType` 的电源；`level = 当前容量 * 100 / 最大容量`（四舍五入）；`onBattery` 看 `kIOPSPowerSourceStateKey == kIOPSBatteryPowerValue`。
- **测试用的覆盖开关**：环境变量 `DESKTOPSHELL_FAKE_BATTERY=<0–100>` 存在时，`readBattery()` 直接返回 `level=该值, isCharging=false, onBattery=true`，方便手动验证低电量规则。

### 3. 监听（`PowerMonitor.swift`，`@MainActor`）

- 屏幕睡眠和唤醒：`NSWorkspace.shared.notificationCenter` 的 `screensDidSleepNotification` / `screensDidWakeNotification`。
- 用户切换：同一个通知中心的 `sessionDidResignActiveNotification` / `sessionDidBecomeActiveNotification`。
- 遮挡：监听每个 `DesktopWindow` 的 `NSWindow.didChangeOcclusionStateNotification`；**所有**桌面窗口的 `occlusionState` 都不含 `.visible` 时，`allWindowsOccluded = true`（只要还有一块屏幕看得见，就继续播放）。屏幕增删后要重新计算。`ScreenManager` 需要提供当前窗口列表或变化回调。
- 电量：用 `IOPSNotificationCreateRunLoopSource` 在电源变化时更新，加到主 run loop；启动时先读一次。
- 状态变化时重新计算 `pauseReasons`。暂停与否发生变化时调用 `BackgroundPlayer.pause()` / `play()`，并打印 `NSLog("DesktopShell power: paused=%@ reasons=%@", ...)`，原因按字母排序输出。原因集合变了但暂停与否没变时，也打印一行，方便验证。

### 4. 菜单栏

- 在"退出 DesktopShell"上方加一项"暂停动画"，点击切换 `manualPause`，用勾选状态（`state = .on/.off`）表示当前是否手动暂停；两项之间加分隔线。

### 5. 测试

- **PowerPolicyTests**：没有任何条件时不暂停；五种原因各自单独触发；电量 19% 且用电池时暂停，20% 时不暂停；15% 但接着电源（`onBattery=false`）时不暂停；`level == nil` 时不暂停；多个原因同时存在时全部列出。
- **BatteryParseTests**：内置电池放电 50%；接电源充电中 80%；没有电池（空数组）→ `unknown`；只有 UPS 类型的电源时忽略；当前容量和最大容量不是 100 制时（例如 4000/5000）换算成 80。

## 允许修改的文件

- `Sources/DesktopShell/PowerPolicy.swift`（新建）
- `Sources/DesktopShell/PowerMonitor.swift`（新建）
- `Sources/DesktopShell/SystemStats.swift`（新建）
- `Sources/DesktopShell/AppDelegate.swift`（修改：菜单项、创建 `PowerMonitor`）
- `Sources/DesktopShell/ScreenManager.swift`（修改：提供窗口列表或变化回调）
- `Tests/DesktopShellTests/PowerPolicyTests.swift`（新建）
- `Tests/DesktopShellTests/BatteryParseTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"，特别是不修改系统设置（不调用 `pmset` 之类的命令改电源设置）。
- 不用定时器轮询遮挡状态或电量，全部用通知。
- 不做 bridge、不通知网页、不做 CPU 和内存统计。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过，交付记录里列出新增测试的数量
- [ ] `git diff --name-only main...task/M2-04` 只包含"允许修改的文件"
- [ ] `grep -rnE "Timer|asyncAfter" Sources/DesktopShell/PowerMonitor.swift Sources/DesktopShell/SystemStats.swift` 没有输出
- [ ] `DESKTOPSHELL_SUPPORT_DIR=/tmp/ds-support DESKTOPSHELL_FAKE_BATTERY=15 .build/debug/DesktopShell` 启动后，日志出现 `paused=true reasons=[lowBattery]`（或等价的格式）
- [ ] 记录播放时和低电量暂停时 DesktopShell 进程的 CPU（`top -l 6 -s 2`，取平均），暂停时应明显更低

**用户手动验证**（在终端运行 `.build/debug/DesktopShell`，观察终端里的日志）：

- [ ] 菜单栏 →"暂停动画"：视频定格，菜单项打勾，日志显示 `reasons=[manual]`；再点一次恢复播放
- [ ] 把任意一个应用切到全屏（窗口左上角绿色按钮），日志显示 `reasons=[occluded]`；退出全屏后恢复播放
- [ ] 在另一个终端窗口运行 `pmset displaysleepnow` 让显示器睡眠，再按任意键唤醒：日志先显示 `screensAsleep`，唤醒后恢复播放
- [ ] 运行 `DESKTOPSHELL_FAKE_BATTERY=15 .build/debug/DesktopShell`：一启动视频就是暂停的，日志显示 `lowBattery`
- [ ] （可选）用"快速用户切换"切到其他账户再切回来：日志显示 `sessionInactive`，切回后恢复

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
