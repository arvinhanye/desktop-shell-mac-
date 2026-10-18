# M3-06: 系统状态推送（电量、CPU、内存，每 5 秒）

- **状态**：review
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
  - 新增 CPU 差值和内存占用纯函数、Mach 读取函数，以及 `PageEvent.systemStats`；计数器回绕、零差值、内存扣减下限/物理内存上限、整数溢出均有测试。相同来源/错误码的读取失败只记录一次。
  - 新增主线程 `SystemStatsMonitor`：启动记录基准，5 秒后首次采样，之后每 5 秒更新，Timer 容差 1 秒；暂停不停止采样。退出时取消定时器，重复启动/停止和过期回调均受保护。
  - `AppDelegate` 接入现有广播与缓存重推。CPU 读取失败后重新建立基准；内存读取失败仍推进 CPU 基准，避免下次成功时混入旧采样区间。
  - 未修改电量读取/解析、暂停规则、网页或其他任务文件；未引入依赖。
- **自测结果**（2026-10-18）：
  - **PASS / RED → GREEN**：原有 Swift 测试 116/116；先补 14 项测试并以最小接口桩确认 14 项失败（23 个行为断言），实现后及交付前复跑均为 **130/130（15 suites）**；网页测试 **138/138**。
  - **PASS / 编译与范围**：`swift build` 成功且无 warning/error；只变更允许的 6 个文件；`git diff --check` 通过；`grep -rnE "Process\(|NSTask" Sources/` 无输出；现有电量函数内容与 main 相同，PowerPolicy/PowerMonitor 无差异。
  - **PASS / 原生集成 16/16**：临时 AppDelegate + 实际 WKWebView/ES module 页面，首次/第二次采样分别为 4.9993/9.9993 秒；实际 Mach 数值及模拟电量 19 到达自检面板；低电量暂停期间仍采样；重新加载在下次 Timer 前立即恢复缓存；退出后无继续推送。
  - **PASS / 读取失败**：仅在临时测试程序链接层注入 Mach 返回错误，18 次读取均返回 nil；两个来源各两种错误只产生 4 行日志。产品代码不包含测试开关。
  - **PASS / 内存实机对照**：本次临时支持目录运行中，用户 03:55:00 的活动监视器截图为已使用 12.75 GB / 物理 16.00 GB = **79.6875%**；同一进程 03:55:00.724 日志为 **79.5%**，差 **0.1875 个百分点**，小于 5。审查时请再对一次。
  - **待复验 / CPU 单核对照**：已执行 15 秒单核负载。首轮受统计脚本筛选区间缺陷和后台负载波动影响，不计通过；修正为按相邻实际采样时间选取完整区间后重测：空闲 30.5/44.1/23.7（均值 32.77），负载 26.2/24.3（均值 25.25），结束后 14.1/16.0/12.9（均值 14.33）；负载进程消耗 14.38 CPU 秒。相对前置基线为 −7.52 个百分点、相对后置基线为 +10.92，前后基线不稳定，尚未确认“比空闲高约 8”验收项。保留两轮原始日志，未关闭其他用户应用，未据此调整产品公式或断言。
  - **PASS / 打包签名**：`scripts/bundle.sh --open` 完成 release 构建、固定证书签名与 strict 校验；指定要求仍为 `local.desktopshell.DesktopShell` + 固定证书 leaf。已启动本次 `build/DesktopShell.app`。默认模式仅记录一次采样启动日志，不记录逐次 cpu/memory；实际页面已加载。
  - **PASS / 独立自查**：一次只读最终检查未发现 Critical/Important/Minor 问题；不替代 Claude Code 的正式审查与复验。
  - 原始日志及临时夹具位于 `/tmp/ds-m3-06-validation/`：`red.log`、`final-swift.log`、`final-web.log`、`final-build.log`、`native-green.log`、`mach-failure.log`、`cpu-load.log`、`cpu-load-corrected-summary.json`、`memory-comparison.json`、`bundle.log`、`signed-app.log`。截图仅保存在本地临时证据目录，不入 Git。
- **疑问 / 偏离**：
  - 无接口或文件范围扩展。CPU 的实机单核增幅仍需在基线较稳定时复验；当前按待复验记录，不计为 PASS。
  - **用户手动验证待完成**：在已打开的签名应用里确认首次约 5 秒显示、之后约每 5 秒更新；对照菜单栏真实电量并插拔电源，确认最多 5 秒内更新；点击菜单栏“重新加载”确认立即显示上次状态。原生自动探针不替代这些真实 GUI/电源操作。
  - 交付到 `task/M3-06`，状态为 `review`；不合并 main、不创建 PR。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
