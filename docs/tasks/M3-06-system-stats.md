# M3-06: 系统状态推送（电量、CPU、内存，每 5 秒）

- **状态**：todo
- **里程碑**：M3
- **依赖**：M3-05（必须已合并到 `main`，用它的广播和重推）
- **分支**：task/M3-06

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

Swift 每 5 秒采样一次电量、CPU 占用和内存占用，推送 `systemStats` 给所有页面。自检面板上能看到这些数字每 5 秒变化一次，并且和"活动监视器"大致对得上。

## 背景与约束

- 先读 `AGENTS.md`："Swift → 网页"表里的 `systemStats`、省电要求。
- 电量沿用现有的 `SystemStats.readBattery()`（会读 `DESKTOPSHELL_FAKE_BATTERY`）。低电量暂停已经由 `PowerMonitor` 负责，本任务不改暂停规则。
- CPU 和内存用 `host_statistics` / `host_statistics64`，采样逻辑写成纯函数，方便测试。
- 定时推送是 `AGENTS.md` 规定的"每 5 秒"，这里允许用 `Timer`（设置 `tolerance = 1`，让系统合并唤醒）。暂停时也继续推送（系统状态组件要显示省电提示）。

### 1. 采样（`SystemStats.swift`，纯函数 + 读取函数）

```swift
struct CPUTicks: Equatable { var user: UInt32; var system: UInt32; var idle: UInt32; var nice: UInt32 }
struct MemoryUsage: Equatable { var usedBytes: UInt64; var totalBytes: UInt64; var percent: Double }

extension SystemStats {
    static func cpuUsage(from: CPUTicks, to: CPUTicks) -> Double?
    static func readCPUTicks() -> CPUTicks?            // host_statistics(HOST_CPU_LOAD_INFO)
    static func memoryUsage(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64,
                            compressedPages: UInt64, pageSize: UInt64, totalBytes: UInt64) -> MemoryUsage
    static func readMemory() -> MemoryUsage?           // host_statistics64(HOST_VM_INFO64) + vm_kernel_page_size + ProcessInfo.physicalMemory
}
```

- **CPU**：各状态的差值用**回绕减法**（`&-`）计算，这样计数器溢出回绕也是对的。占用 = (Δuser + Δsystem + Δnice) / (四项差值之和) × 100，保留一位小数；四项差值之和为 0 时返回 `nil`。
- **内存**（和"活动监视器"的"已使用内存"口径一致）：已用 = (`internal` − `purgeable`（不小于 0）+ `wired` + `compressor`) × 页大小，不超过总内存；`percent` = 已用 / 总内存 × 100，保留一位小数；总内存为 0 时 `percent` 为 0。
- 读取失败（`KERN_SUCCESS` 以外）返回 `nil` 并记录日志（同一种错误只记一次）。

### 2. 定时推送（新建 `SystemStatsMonitor.swift`）

```swift
@MainActor
final class SystemStatsMonitor {
    var onSample: (([String: Any]) -> Void)?
    func start()    // 记下 CPU 基准，之后每 5 秒采样并调用 onSample
    func stop()
}
```

- 第一次推送在启动 5 秒后（CPU 需要两次采样之间的差值）。CPU 或内存读取失败的那一次不推送。
- `AppDelegate` 把 `onSample` 接到 `ScreenManager.broadcast`（M3-05 已经会缓存 `systemStats` 并在页面加载后重推），退出时 `stop()`。
- 环境变量 `DESKTOPSHELL_DEBUG_STATS=1` 时，每次采样记录一行 `DesktopShell stats: cpu=<数> memory=<数>% battery=<数或nil> charging=<true/false> onBattery=<true/false>`；平时只在启动时记录一行 `DesktopShell stats: sampling every 5s`。

### 3. 事件内容（`BridgeProtocol.swift`，纯函数）

```swift
extension PageEvent {
    static func systemStats(battery: BatteryStatus, cpu: Double, memory: MemoryUsage) -> [String: Any]
}
```

```json
{
  "event": "systemStats",
  "battery": { "level": 85, "charging": false, "onBattery": true },
  "cpu": 12.3,
  "memory": { "usedBytes": 9876543210, "totalBytes": 17179869184, "percent": 57.5 }
}
```

- `battery.level` 为空时写 `NSNull()`，不省略。数字都是有限数（M3-01 的 `applyEvent` 会校验范围：`level` 0–100 的整数，`cpu`、`percent` 0–100）。

### 4. 测试

- 在 `BatteryParseTests.swift` 旁新建 `SystemStatsTests.swift`：
  - `cpuUsage`：正常差值；只有 `idle` 增加 → 0；只有 `user` 增加 → 100；某一项计数器回绕（例如 `UInt32.max - 10` → `5`）仍算对；差值全为 0 → `nil`；一位小数取整。
  - `memoryUsage`：正常情况；`purgeable` 大于 `internal` 时不出现负数；算出来超过总内存时封顶；总内存为 0。
  - `PageEvent.systemStats`：键和值正确；`level` 为空时是 `NSNull`。

## 允许修改的文件

- `Sources/DesktopShell/SystemStats.swift`（修改：增加 CPU 和内存）
- `Sources/DesktopShell/SystemStatsMonitor.swift`（新建）
- `Sources/DesktopShell/BridgeProtocol.swift`（修改：`PageEvent.systemStats`）
- `Sources/DesktopShell/AppDelegate.swift`（修改：启动和停止监视器）
- `Tests/DesktopShellTests/SystemStatsTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不修改 `parseBattery`、`readBattery`、`PowerPolicy`、`PowerMonitor` 的逻辑。
- 不执行外部命令获取数据（不用 `Process` 调 `top`、`vm_stat`）。
- 不修改 `web/` 下的任何文件。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过，包含上面列出的新测试；`scripts/test-web.sh` 仍然全部通过
- [ ] `git diff --name-only main...task/M3-06` 只包含"允许修改的文件"
- [ ] `grep -rnE "Process\(|NSTask" Sources/` 没有输出
- [ ] CPU 采样对得上：先退出正在运行的 DesktopShell，再用临时支持目录直接运行可执行文件，同时开一个占满单核的进程，日志里的 `cpu` 比空闲时高出大约 8（本机 12 个逻辑核，单核约 8.3%）：
  ```bash
  mkdir -p /tmp/ds-m3-06 && ln -sfn ~/Library/Application\ Support/DesktopShell/media /tmp/ds-m3-06/media
  DESKTOPSHELL_SUPPORT_DIR=/tmp/ds-m3-06 DESKTOPSHELL_DEBUG_STATS=1 .build/debug/DesktopShell 2>&1 | grep "DesktopShell stats"
  # 另一个终端：yes > /dev/null  （15 秒后 Ctrl-C）
  ```
- [ ] 同一次运行里，`memory` 的百分比和"活动监视器 → 内存"底部"已使用内存 / 物理内存"相差不超过 5 个百分点（Codex 写进交付记录，Claude Code 复验时再对一次）

**用户手动验证**（`scripts/bundle.sh --open`，用自检面板）：

- [ ] 启动约 5 秒后，面板的"系统状态"从"未收到"变成具体数字，之后每 5 秒更新一次
- [ ] 电量和菜单栏电池图标的百分比一致；插拔电源后最多 5 秒内"是否充电""是否用电池"跟着变
- [ ] 菜单栏"重新加载"后，面板马上显示上一次的系统状态，不需要再等 5 秒（验证重推）

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
