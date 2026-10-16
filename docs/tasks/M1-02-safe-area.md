# M1-02: 安全区域计算与调试框

- **状态**：todo
- **里程碑**：M1
- **依赖**：M1-01（必须已合并到 `main`）
- **分支**：task/M1-02

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

每块屏幕的桌面窗口上画出一个半透明框，标出"安全区域"，也就是排除 Dock 和菜单栏后的区域，并显示四个方向的边距数值。Dock 位置或大小变化时，框会自动更新。同时建立单元测试的基础设施。

## 背景与约束

- 先读 `AGENTS.md` 的"窗口要求"（安全区域部分）和"开发环境"（单元测试部分）。
- 安全区域的计算写成**纯函数**，放在 `SafeArea.swift`，不依赖 `NSScreen` 对象，方便测试：

  ```swift
  struct SafeAreaInsets: Equatable {
      var top: CGFloat
      var right: CGFloat
      var bottom: CGFloat
      var left: CGFloat
  }

  extension SafeAreaInsets {
      /// screenFrame 和 visibleFrame 都是 AppKit 全局坐标（原点在主屏左下角，y 向上）。
      static func compute(screenFrame: CGRect, visibleFrame: CGRect) -> SafeAreaInsets
  }
  ```

  计算方法（结果小于 0 时取 0）：
  - `top    = screenFrame.maxY - visibleFrame.maxY`
  - `bottom = visibleFrame.minY - screenFrame.minY`
  - `left   = visibleFrame.minX - screenFrame.minX`
  - `right  = screenFrame.maxX - visibleFrame.maxX`

  字段名固定为 `top/right/bottom/left`，M2 会原样序列化后推送给网页。
- `ScreenManager`：创建窗口时，以及每次收到 `didChangeScreenParametersNotification` 时，用 `screen.frame` 和 `screen.visibleFrame` 算出 insets，再交给对应窗口。
- `DesktopWindow`：新增 `func updateSafeArea(_ insets: SafeAreaInsets)`。在占位视图上叠一个调试视图：
  - 视图的 bounds 按 insets 内缩后得到安全区域矩形（AppKit 视图原点在左下：`x = left`，`y = bottom`，`width = W - left - right`，`height = H - top - bottom`）。
  - 用半透明填充加 2pt 实线边框画出这个矩形（颜色自选，能看清即可，例如 `systemTeal` 填充 alpha 0.15、边框 alpha 0.9）。
  - 在框内左上角显示 `top 25 · right 0 · bottom 80 · left 0` 这样的文字。
  - 保留 M1-01 中间显示的屏幕名称和尺寸。
- 测试基础设施：
  - `Package.swift` 增加 `.testTarget(name: "DesktopShellTests", dependencies: ["DesktopShell"])`。
  - 测试用 swift-testing（`import Testing`、`@Test`、`#expect`），**不用 XCTest**；在测试里 `@testable import DesktopShell`。
  - 新建 `scripts/test.sh`，内容**原样照抄**下面这段（Claude Code 已在本机验证可用），并 `chmod +x`：

  ```bash
  #!/bin/bash
  # 运行单元测试。
  # 只装命令行工具时，Testing 框架在工具目录里，但 SwiftPM 默认找不到，需要手动加搜索路径。
  # 装了完整 Xcode 并切换过去后，直接运行 swift test 即可。
  set -euo pipefail
  cd "$(dirname "$0")/.."

  DEVDIR="$(xcode-select -p)"
  if [[ "$DEVDIR" == *CommandLineTools* ]]; then
    FW="$DEVDIR/Library/Developer/Frameworks"
    LIB="$DEVDIR/Library/Developer/usr/lib"
    exec swift test \
      -Xswiftc -F -Xswiftc "$FW" \
      -Xlinker -F -Xlinker "$FW" \
      -Xlinker -rpath -Xlinker "$FW" \
      -Xlinker -rpath -Xlinker "$LIB" \
      "$@"
  else
    exec swift test "$@"
  fi
  ```

- 测试用例（`SafeAreaTests.swift`），至少覆盖下面这些情况：

  | 用例 | screenFrame | visibleFrame | 期望 top/right/bottom/left |
  |---|---|---|---|
  | Dock 在底部 | (0, 0, 1440, 900) | (0, 80, 1440, 795) | 25 / 0 / 80 / 0 |
  | Dock 在左侧 | (0, 0, 1440, 900) | (70, 0, 1370, 875) | 25 / 0 / 0 / 70 |
  | Dock 在右侧 | (0, 0, 1440, 900) | (0, 0, 1370, 875) | 25 / 70 / 0 / 0 |
  | 副屏（原点不为 0，只有菜单栏） | (1440, -200, 1920, 1080) | (1440, -200, 1920, 1055) | 25 / 0 / 0 / 0 |
  | 没有菜单栏和 Dock | (0, 0, 1440, 900) | (0, 0, 1440, 900) | 0 / 0 / 0 / 0 |
  | visibleFrame 超出 frame（异常值，结果取 0） | (0, 0, 1440, 900) | (-10, -10, 1460, 935) | 0 / 0 / 0 / 0 |

  （表中矩形写法为 `(x, y, width, height)`。）

## 允许修改的文件

- `Package.swift`（修改：加 test target）
- `Sources/DesktopShell/SafeArea.swift`（新建）
- `Sources/DesktopShell/ScreenManager.swift`（修改）
- `Sources/DesktopShell/DesktopWindow.swift`（修改）
- `Tests/DesktopShellTests/SafeAreaTests.swift`（新建）
- `scripts/test.sh`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不加 WKWebView 和 bridge，安全区域推送给网页属于 M2/M3。
- **不要用定时器轮询 `visibleFrame`**。如果手动验证时发现 Dock 变化不会触发 `didChangeScreenParametersNotification`，在交付记录里报告，由 Claude Code 决定怎么处理。
- 不修改任何系统设置。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 退出码为 0，输出里能看到上表全部用例通过
- [ ] 故意把一个期望值改错后，`scripts/test.sh` 退出码不为 0（验证完改回来，不要提交改错的版本）
- [ ] `git diff --name-only main...task/M1-02` 只包含"允许修改的文件"
- [ ] `grep -rn "XCTest" Tests/ Sources/` 没有输出

**用户手动验证**（运行 `.build/debug/DesktopShell`）：

- [ ] 屏幕上出现半透明框，框的**底边正好贴着 Dock 的上沿**，Dock 没有压在框里；框的**顶边正好贴着菜单栏下沿**
- [ ] 框内左上角的数值与实际一致（例如 Dock 在底部时 bottom 大于 0，left/right 为 0）
- [ ] 系统设置 → 桌面与程序坞 → "在屏幕上的位置"改为"左"，**不重启应用**，框自动更新为左侧留出 Dock 的宽度；改回"底部"后恢复（验证完记得改回你原来的设置）
- [ ] 打开"自动隐藏和显示程序坞"，框的底边几乎贴到屏幕底部；关掉后恢复
- [ ] （有外接显示器时）每块屏幕各有自己的框；没有 Dock 的屏幕只在顶部留出菜单栏的高度

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
