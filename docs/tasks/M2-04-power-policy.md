# M2-04: 省电暂停规则

- **状态**：done
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
  - 新增可复用的 `PowerState`、`PauseReason` 和纯函数 `pauseReasons`，五种暂停原因独立累积；仅在使用电池且已知电量严格小于 20 时加入 `lowBattery`。
  - 新增 `BatteryStatus` 和电量读取：仅解析内置电池，容量换算后四舍五入；未知、非法容量保留为 nil，避免除零或溢出。支持 0–100 的模拟电量，非法覆盖值记录日志后读取实际电量。
  - `PowerMonitor` 监听 workspace 睡眠/会话通知、逐窗遮挡通知和主 run loop 的 IOKit 电源 source；没有定时轮询。ScreenManager 在同步及清空窗口后回传当前列表，任一窗口可见即继续，无窗口时暂停。
  - 原因集合变化时输出按字母排序的日志；首次应用及暂停布尔值变化时才调用播放器，解除单个原因不会覆盖其他暂停条件。
  - 菜单新增“暂停动画”和分隔线，勾选仅代表手动暂停。退出先断开窗口变化回调、移除通知并 invalidate 电源 source，再关闭窗口、暂停播放器；deinit 同样清理 source，保护未持有引用的 C context。
  - 仅改动允许的 7 个 Swift 文件及本任务状态、交付记录；未修改既有播放器/网页或加入 bridge、CPU/内存采集、系统设置修改。
- **自测结果**（2026-10-17）：
  - 从已合并 M2-03 的最新 `main`（`df9a3f3`）创建 `task/M2-04`。基线 34/34 通过；新增 **15 个测试声明**：PowerPolicyTests 5 个、BatteryParseTests 10 个。空实现首先触发 35 条预期断言失败；实现后及最终 `scripts/test.sh` 均 **49/49 通过**，退出码 0。
  - 新测试覆盖五原因、19/20 边界、接电源/未知电量、多原因及分别解除；内置电池/UPS 筛选、充电标记、4000/5000 比例、四舍五入、容量缺失、布尔/负数/非有限数/零分母和 NSNumber 桥接。
  - 最终 `swift build` 退出码 0；构建日志经 `grep -iE 'warning|error'` 检查无输出。`grep -rnE 'Timer|asyncAfter' Sources/DesktopShell/PowerMonitor.swift Sources/DesktopShell/SystemStats.swift` 无输出；bridge 关键词扫描无输出，`git diff --check` 通过。
  - `/tmp/ds-m2-04-validation/MonitorChecks.swift` 编译实际生产源文件，使用真实 AppKit 事件循环、两个原生窗口及共享播放器：**19/19 通过**。验证手动暂停、原因叠加及恢复、单窗可见/全部隐藏、增删窗口后重算、空列表、初始低电量、重复 start 和停止释放。睡眠/会话通知只在测试进程内模拟，没有让系统休眠或切换账户；遮挡检查等待实际通知，避免固定等待时间导致误报。
  - 临时 `MenuChecks.swift`：**7/7 通过**，核对实际菜单顺序、调用其 action 后的勾选/原因、手动解除时保留自动暂停，以及退出清理。临时 `BatteryReadChecks.swift`：**10/10 通过**，验证模拟值 0/15/20/80/100 和 5 种非法覆盖值；实际 IOKit 读取为电量 100%、接电源、未充电。
  - 复用 M2-03 已准备好的 `/tmp/ds-support`，未重新转码。分别用模拟电量 80 和 15 启动同一二进制，等待 5 秒后各执行 `top -l 6 -s 2 -pid <测试进程> -stats pid,command,cpu`，采样完成后结束各自测试进程。15% 日志实际出现 `paused=true reasons=[lowBattery]`；80% 出现 `paused=false reasons=[]`。
  - CPU 六样本：播放 `[0.0, 1.4, 2.2, 2.1, 2.2, 2.3]`，平均 **1.70%**；低电量暂停 `[0.0, 0.0, 0.0, 0.0, 0.0, 0.0]`，平均 **0.00%**。剔除首个初始化样本分别为 **2.04% / 0.00%**。暂停明显更低；0.00% 是此次 top 采样精度下的结果，不表示绝对零开销。两次采样依次进行，没有同时运行构建或测试。
  - 独立只读检查未发现 Critical / Important / Minor 代码缺陷；正式审查仍由 Claude Code 完成。完整日志、CPU 原始采样及临时集成检查源文件保存在 `/tmp/ds-m2-04-validation/`。
- **疑问 / 偏离**：
  - 无范围偏离。真实菜单点击后的视觉效果、其他应用全屏遮挡、实际显示器睡眠/唤醒、快速用户切换，以及物理电源变化通知仍按手动步骤复验；本进程模拟通知不等于系统实际投递已验收。
  - 当前调用链仅在应用启动时启动 monitor、退出时停止；没有中途停用后重启入口。若后续增加该入口，需要重新核对停用期间错过的睡眠/会话状态，避免恢复时使用旧状态。网页动画、音频捕获暂停及已有播放器的媒体错误处理保持本任务范围之外。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**通过**，已合并到 `main`。用户手动验证（Claude Code 读终端日志核对）：手动暂停 `reasons=[manual]` 后恢复；全屏 `reasons=[occluded]` 退出后恢复；`pmset displaysleepnow` 时 `reasons=[screensAsleep]`，唤醒后恢复（唤醒后锁屏界面遮挡约 2 秒，记为 `occluded`，属于正确行为）。
- **复验结果**（Claude Code，2026-10-17）：
  - [x] touch 源码后强制重编，零警告零错误；`scripts/test.sh` 49/49 通过（新增 15 个）
  - [x] 改动范围是 7 个 Swift 文件和本任务单，都在允许范围内
  - [x] `PowerMonitor.swift`、`SystemStats.swift` 里没有 `Timer`、`asyncAfter`；源码里没有 `pmset`、`Process(`、`NSTask`、`posix_spawn`
  - [x] `DESKTOPSHELL_FAKE_BATTERY=15`：日志最终为 `paused=true reasons=[lowBattery]`，CPU（去掉首样本）**0.0%**
  - [x] `DESKTOPSHELL_FAKE_BATTERY=80`：日志最终为 `paused=false reasons=[]`，CPU **1.9%**
  - [x] SIGTERM 后正常退出
- **意见**：
  - 实现质量高：全部用通知驱动；屏幕唤醒、会话恢复时会重新计算遮挡状态，不用过期的旧值；只有"暂停与否"变化时才调用播放器；IOKit 回调的 C 上下文在退出和 deinit 时都会先失效，不会出现悬空访问；电量解析对缺失值、布尔值、零分母都做了防御。
  - **后续事项（不阻塞，写进 M3 任务单）**：启动时窗口刚显示，系统还没算出可见状态，`occlusionState` 暂时不含 `.visible`，日志会先出现一次 `paused=true reasons=[occluded]`，**23 毫秒后**恢复为 `paused=false`。现在只影响视频，肉眼看不出来；但 M3 把 `paused` 推给网页、M5.5 接上音频捕获后，启动时会多出一次"停止再恢复"。M3 修改 `PowerMonitor` 时一并处理：在收到第一次遮挡通知之前，把窗口当作可见。
  - Codex 提到"目前没有中途停用后重新启动的入口"，认可，现在不需要。
