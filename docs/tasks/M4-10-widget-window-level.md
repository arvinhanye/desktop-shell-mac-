# M4-10: 修正组件窗口层级（组件盖住其他应用和全屏应用）

- **状态**：done
- **里程碑**：M4
- **依赖**：M4-06（用户 2026-10-18 定：先做 M4-06，再做本任务）。M4-07、M4-08 只改网页，和本任务不冲突，前后都行；**必须在 M4-09 之前合并**（M4-09 里原来的"窗口层级"一节挪到了这里）
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
  - `WindowLevels` 集中计算组件 `icon+3`、视频正常 `icon-1` / 隐藏文件时 `icon+3`；日志在图标层 ±16 内显示相对偏移，远处显示原值，差值溢出时也保留原值。
  - 提取正式初始化和测试共用的 `WidgetWindow.configure`，面板属性设置完成后最后赋层级，并注明 `isFloatingPanel` setter 覆盖层级的原因。窗口集合行为、点击穿透、键盘焦点和视频鼠标属性保持原样。
  - 新建每对窗口及切换隐藏状态后记录两个窗口的实际层级，保留视频先、组件后 `orderFront` 顺序。
  - 增加只读 `scripts/window-levels.swift`，打印尺寸、层级和前后顺序；没有参照应用时明确说明，没有 DesktopShell 窗口或必要元数据时非零退出。不读取窗口标题。
- **自测结果**：
  - 修改前原生基线：`scripts/test.sh`，161/161 PASS。
  - 纯函数临时回归程序直接编译正式 `WindowLevels.swift`：旧行为 4 项失败、3 项通过 → 修正后 7/7 PASS。日志：`/tmp/desktopshell-m4-10-check/pure-red.log`、`pure-green.log`。
  - 新增原生回归：用户在终端运行 `scripts/test.sh --filter WindowLevelsTests`，6/6 PASS（2026-10-19 回传），包含真实空 `NSPanel` 配置后的层级与原有属性断言。这是修复后 GREEN；本轮未实际运行修复前的原生 RED，旧顺序问题的原生证据来自任务单已有探针。
  - 网页：`scripts/test-web.sh`，345/345 PASS，无跳过。
  - 检查脚本临时数据样例：6/6 PASS，覆盖桌面层在普通应用之后、错误层级 0 在前、隐藏时同层窗口顺序、没有参照应用、没有本应用窗口、元数据缺失；仅替换窗口列表数据来源，不作为真实桌面证据。日志：`/tmp/desktopshell-m4-10-check/script-fixtures.log`。
  - Codex 只读自查覆盖全部 6 文件，未发现代码问题；不替代 Claude 正式复验。
  - 最终源码 `swiftc -typecheck -swift-version 5 -module-cache-path /tmp/desktopshell-m4-10-check/module-cache Sources/DesktopShell/*.swift` PASS，退出 0，无诊断；此项不替代 `swift build`。`git diff --check` 和精确 6 文件范围检查 PASS，任务需求与 Claude 审查区保持原样。
  - 最终完整验证：用户运行临时入口 `bash /tmp/desktopshell-m4-10-check/verify-native.sh` 后回传结果，Codex 同时复核其完整日志；`scripts/test.sh` **167/167 PASS（19 suites）**，`swift build` PASS，完整构建日志无 warning/error。
  - `scripts/bundle.sh --open` PASS：release 构建、Info.plist 校验、固定证书 `DesktopShell Self-Signed` 签名与严格校验均通过，已重启 `build/DesktopShell.app`。未使用 ad-hoc 签名。
  - 实际启动日志（2026-10-19 01:00:13）：`DesktopShell windows: display=2077748985 widget=icon+3 video=icon-1`。只读脚本确认 `#310 1792x1120 level=icon+3 behind app windows`，`#309 1792x1120 level=icon-1 behind app windows`。日志分别保存为 `/tmp/desktopshell-m4-10-check/{swift-final,build-final,bundle-final,startup-levels,windows-final}.log`。
  - 环境说明：受限执行环境的 SwiftPM 嵌套沙盒报 `Operation not permitted`；正常权限请求多次遇到审核服务超时或容量不足，失败请求未执行命令。因此上述最终原生命令由用户运行，Codex 读取落盘日志核验，未将基础设施失败计作产品失败或通过。
- **疑问 / 偏离**：普通窗口遮挡、全屏、中文输入与 Esc、桌面点击穿透、系统小组件叠放和隐藏桌面文件切换仍保留为真实桌面验收项；未合并到 `main`。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**通过**，已合并到 `main`。代码审查和自动验收见下；手动验证 2026-10-19 完成并对照了日志（见最后）。
- **复验结果**（Claude Code，2026-10-19，在 `e9352b6` 的独立检出上执行；打包在主目录的同一提交上执行）：
  - [x] `swift build` 零警告零错误；`scripts/test.sh` 167 项全部通过（19 个 suite，含 `WindowLevelsTests` 里用真实 `NSPanel` 验证配置后层级的测试）；`scripts/test-web.sh` 345 项全部通过
  - [x] 只改了允许的 6 个文件；`git diff --check` 通过
  - [x] `DesktopWindow.swift` 里 `isFloatingPanel = false` 在第 67 行，设 `level` 在第 75 行，并有注释说明原因
  - [x] `scripts/bundle.sh --open`（`03:43:58` 启动）：日志 `03:44:03 DesktopShell windows: display=2077748985 widget=icon+3 video=icon-1`；`swift scripts/window-levels.swift` 输出组件窗口 `level=icon+3 behind app windows`、视频窗口 `level=icon-1 behind app windows`
  - [x] 另用 `CGWindowListCopyWindowInfo` 列出全部窗口（从前到后）：普通应用窗口（层级 0）→ DesktopShell 组件窗口（icon+3）→ 系统桌面小组件（icon+2）→ 访达图标（icon+0）→ DesktopShell 视频窗口（icon−1）。修复前组件窗口在层级 0、和普通应用窗口混在一起
- **意见**：
  - 修正方式和任务单一致：面板属性先设、层级最后设；`configure` 正式初始化和测试共用。`WindowLevels.describe` 在图标层 ±16 以内显示相对值，否则写原始数值，层级 0 这类错误一眼能看出来。
  - 层级日志在每对窗口建好时、每次切换"隐藏桌面文件"后各记一行，读的是窗口实际的 `level`。视频先、组件后提到前面的顺序保留。
  - 检查脚本只读窗口的拥有者、层级、尺寸和编号，不读标题，不需要"屏幕录制"权限。
  - 交付记录说明 Codex 所在环境的 SwiftPM 沙盒报错，原生命令由用户代跑；这次 Claude Code 自己重跑了构建、全部测试和打包，结果一致。
- **手动验证**（2026-10-19，用户在 Claude Code 打包启动的 `e9352b6` 上验证，Claude Code 对照日志）：
  - [x] 点过组件之后，应用窗口仍盖在组件上面（用户目测）
  - [x] 应用全屏时看不到组件，退出全屏后组件照常（用户目测）
  - [x] 组件照常能点：`03:49:56`–`03:50:24` 七次 `setTodoDone ok`，`03:50:46 openProjectWith desktop-shell cursor ok`、`03:50:52 openProject desktop-shell ok`；点空白处穿透给访达（用户目测）
  - [x] 待办输入：`03:49:25 focusInput ok` → `03:49:29 addTodo ok` → `03:49:31 blurInput ok`
  - [x] 系统桌面小组件和组件重叠处，组件在上面（用户目测；窗口列表里组件 icon+3 在系统小组件 icon+2 前面）
  - [x] 隐藏桌面文件：`05:41:28 windows: … widget=icon+3 video=icon+3`，隐藏期间点了项目按钮和启动栏（`05:41:30`–`05:42:15` 四次 `ok`），`05:42:37 windows: … widget=icon+3 video=icon-1` 恢复，`ui.json` 里 `desktopIconsHidden` 为 `false`。第一次回复"做完了"时日志里没有这次切换（应用在 `03:51:58` 被退出），Claude Code 重新打开应用后补做
