# M4-10: 修正组件窗口层级（组件盖住其他应用和全屏应用）

- **状态**：todo
- **里程碑**：M4
- **依赖**：M4-05（已合并）。**插队，在 M4-06 之前做**；M4-09 里原来的"窗口层级"一节挪到了这里
- **分支**：task/M4-10

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

组件窗口回到桌面层（图标层 +3），永远在普通应用窗口下面：点过组件之后，其他应用的窗口照样盖在组件上面；应用全屏时看不到组件。"隐藏桌面文件"时视频窗口升到 +3、排在组件窗口下面。启动时在日志里记下两个窗口的实际层级，以后再出这种问题一眼能看出来。

## 背景与约束

- **用户报告**（2026-10-18）：应用全屏时、以及有些时候，组件盖在其他应用的窗口上面。
- **Claude Code 复现结果**：
  - 用 `CGWindowListCopyWindowInfo` 看正在运行的 DesktopShell：视频窗口在图标层 −1（正确），**组件窗口在层级 0**，也就是普通应用窗口的层级，而不是代码里写的图标层 +1。
  - 原因在 `DesktopWindow.swift` 的 `WidgetWindow.init`：先设 `level`，后设 `isFloatingPanel = false`。`NSPanel.isFloatingPanel` 的 setter 会顺带改层级（`true` 改成浮动层级，`false` 改成普通层级），把前面设的桌面层级覆盖掉了。这是 M3-08 把组件窗口改成 `NSPanel` 时带进来的。
  - 一次性探针（两个 60 × 60 的透明面板，其他设置和 `WidgetWindow` 一样）：按现在的顺序设置，层级是 0，`orderFrontRegardless()` 之后排在其他应用的窗口**前面**；把 `hidesOnDeactivate`、`isFloatingPanel` 放在前面、`level` 最后设，层级是图标层 +3，`orderFrontRegardless()` 之后仍在所有应用窗口**后面**；再 `makeKey()`（输入框获得焦点时会调用）层级也不变。
  - 层级 0 的窗口被点一下就会被提到普通窗口的最前面；它又带着 `.canJoinAllSpaces`，所以全屏应用的空间里也会出现、并可能排在全屏窗口前面。层级改对之后这两种情况都不会发生（同样设置的视频窗口在图标层 −1，全屏时从来没出现过）。
- AGENTS.md "窗口要求"：WidgetWindow 是图标层 **+3** 的不激活 `NSPanel`；"隐藏桌面文件"时 VideoWindow 升到 **+3**、排在 WidgetWindow 下面，取消时回到 −1。
- 不改变点击穿透、键盘焦点（M3-08）、"隐藏桌面文件"的其他行为。

### 1. 层级的计算（新建 `Sources/DesktopShell/WindowLevels.swift`，纯函数）

```swift
enum WindowLevels {
    static func widget(iconLevel: Int) -> Int                 // iconLevel + 3
    static func video(iconLevel: Int, iconsHidden: Bool) -> Int  // 隐藏桌面文件时 iconLevel + 3，否则 iconLevel - 1
    static func describe(_ level: Int, iconLevel: Int) -> String // 日志用："icon+3"、"icon-1"；差得太远（例如层级 0）时写原始数值，例如 "0"
}
```

### 2. 窗口设置（`DesktopWindow.swift`）

- `WidgetWindow.init`：先设 `hidesOnDeactivate = false`、`isFloatingPanel = false` 等面板属性，**最后**设 `level = WindowLevels.widget(...)`。在设 `level` 的地方写一行注释说明原因（`isFloatingPanel` 的 setter 会改层级）。
- `VideoWindow.setDesktopIconsHidden` 改用 `WindowLevels.video(...)`。
- 把"创建并配置 `NSPanel`"的部分提成一个可以单独调用的函数（例如 `WidgetWindow.configure(_ panel: NSPanel, iconLevel: Int)`，`init` 里调用它），方便测试用一个空的 `NSPanel` 验证配置完的层级。

### 3. 启动和切换时记录实际层级（`ScreenManager.swift`）

- 每次为一块屏幕建好一对窗口、以及切换"隐藏桌面文件"之后，记录一行（读窗口**实际的** `level`，不是算出来的值）：
  `DesktopShell windows: display=<id> widget=icon+3 video=icon-1`
- `applyDesktopIconsHidden` 现在"先把视频窗口、再把组件窗口提到前面"的顺序保留。

### 4. 检查脚本（新建 `scripts/window-levels.swift`，调试用，不进 `.app`）

用 `swift scripts/window-levels.swift` 运行。用 `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 列出屏幕上的窗口（从前到后），对每个 `DesktopShell` 的窗口打印一行：窗口号、尺寸、相对图标层的层级（`icon+3` 这样的写法），以及它排在第一个普通应用窗口（层级 0、不属于 DesktopShell）的前面还是后面。例如：

```
DesktopShell #318 1792x1120 level=icon+3 behind app windows
DesktopShell #316 1792x1120 level=icon-1 behind app windows
```

只读窗口信息，不需要"屏幕录制"权限（不读窗口标题）。

### 5. 测试

- `Tests/DesktopShellTests/WindowLevelsTests.swift`（新建）：`widget`、`video` 两种状态、`describe`（`icon+3`、`icon-1`、层级 0 写原始数值）。
- 同一个文件里加一个 `@MainActor` 测试：建一个和 `WidgetWindow` 一样 `styleMask` 的空 `NSPanel`，调用第 2 节的配置函数，断言 `panel.level.rawValue == WindowLevels.widget(...)`。如果测试进程里建不了 `NSPanel`，在交付记录里说明，并用第 4 节的脚本在打包的应用上验证。

## 允许修改的文件

- `Sources/DesktopShell/WindowLevels.swift`（新建）
- `Sources/DesktopShell/DesktopWindow.swift`、`Sources/DesktopShell/ScreenManager.swift`（修改）
- `scripts/window-levels.swift`（新建）
- `Tests/DesktopShellTests/WindowLevelsTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改 `collectionBehavior`、点击穿透（`HitTestController`、`ignoresMouseEvents` 的切换）和键盘焦点的逻辑；不调用 `NSApp.activate`。
- 不让 VideoWindow 接收鼠标。
- 不做 M4-09 的毛玻璃。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh`、`scripts/test-web.sh` 全部通过，包含上面的新测试
- [ ] `git diff --name-only main...task/M4-10` 只包含"允许修改的文件"
- [ ] `grep -n "isFloatingPanel\|level =" Sources/DesktopShell/DesktopWindow.swift`：`isFloatingPanel` 出现在设 `level` 的那一行**之前**
- [ ] `scripts/bundle.sh --open` 后：日志里有 `DesktopShell windows: display=… widget=icon+3 video=icon-1`；`swift scripts/window-levels.swift` 显示组件窗口 `icon+3`、视频窗口 `icon-1`，都排在普通应用窗口后面
- [ ] 菜单栏勾上"隐藏桌面文件"：日志 `widget=icon+3 video=icon+3`，脚本里视频窗口排在组件窗口后面；取消后回到 `video=icon-1`

**用户手动验证**（`scripts/bundle.sh --open`）：

- [ ] 点一下待办、项目卡片等组件，再点一个普通应用的窗口（例如访达、Safari）把它拖到组件上面 → 应用窗口盖在组件上面，组件不会跑到前面来
- [ ] 把一个应用全屏（例如 Safari 按 ⌃⌘F）→ 全屏应用里看不到任何组件；退出全屏回到桌面，组件照常显示
- [ ] 桌面上的组件照常能点（勾选待办、点项目、点启动栏）；点空白处穿透给访达，能框选
- [ ] 待办输入框能输入中文，Esc 后键盘回到原来的应用
- [ ] 系统桌面小组件和我们的组件重叠的地方，我们的组件在上面
- [ ] "隐藏桌面文件"：访达图标和系统小组件被视频盖住，组件仍在最上面、能点；取消后恢复

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
