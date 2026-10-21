# M7-04: 输入框支持复制、粘贴等编辑快捷键

- **状态**：todo
- **里程碑**：M7
- **依赖**：无。只改 `AppDelegate.swift` 和一个新文件，和 M7-03 的文件不冲突，前后都行
- **分支**：task/M7-04

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

在待办、项目的输入框里，⌘V 粘贴、⌘C 复制、⌘X 剪切、⌘A 全选、⌘Z 撤销、⇧⌘Z 重做都能用，和普通 Mac 应用一样。M7 的"粘贴文件夹路径"离不开这一条。

## 背景与约束

- **用户报告**（2026-10-21，M7-03 验收时）：项目和待办的输入框都不能复制粘贴。
- **原因**（Claude Code 查明）：
  - 普通 Mac 应用的这些快捷键，是由菜单栏"编辑"菜单里各菜单项的快捷键分派的：⌘V 对应 `paste:`，沿响应链送到当前的第一响应者，也就是 WKWebView。
  - DesktopShell 是 `LSUIElement` 应用，代码里从没设过 `NSApp.mainMenu`，只有菜单栏图标的菜单。所以 ⌘V 这类按键没有菜单项接手，WebView 也不处理，按下去什么都不发生。
  - 网页又在 `main.js` 里禁用了右键菜单（AGENTS.md "桌面组件交互基线"），所以用右键粘贴也不行。
  - 这个问题从 M3-08（组件窗口能获得键盘）起就存在。
- **做法**：给应用设一个**看不见的主菜单**，里面放标准的"编辑"菜单。`LSUIElement` 应用不显示菜单栏，但 `NSApp.mainMenu` 里的快捷键仍然会被分派。组件窗口在输入框获得焦点时是 key window（M3-08），按键会走到这里。
  - 不改"不激活应用"的做法，不调用 `NSApp.activate`。
  - 不恢复右键菜单。

### 1. 编辑菜单（新建 `Sources/DesktopShell/EditMenu.swift`）

```swift
enum EditMenu {
    /// 返回一个只有"编辑"子菜单的主菜单，交给 NSApp.mainMenu。
    static func makeMainMenu() -> NSMenu
}
```

- "编辑"子菜单里的项目，按顺序：

  | 标题 | action | 快捷键 |
  |---|---|---|
  | 撤销 | `undo:` | ⌘Z |
  | 重做 | `redo:` | ⇧⌘Z |
  | 分隔线 | | |
  | 剪切 | `cut:` | ⌘X |
  | 拷贝 | `copy:` | ⌘C |
  | 粘贴 | `paste:` | ⌘V |
  | 全选 | `selectAll:` | ⌘A |

- `target` 都是 `nil`，沿响应链送给第一响应者。

### 2. 接线（`AppDelegate.swift`）

- 在 `applicationDidFinishLaunching` 里设 `NSApp.mainMenu = EditMenu.makeMainMenu()`，放在建窗口之前。
- 不改菜单栏图标的菜单。

### 3. 如果主菜单的做法在不激活的面板上不起作用

在桌面上验证时，如果按 ⌘V 没有反应，就说明主菜单的快捷键没有分派到不激活的面板。这时在 `WidgetWindow`（`DesktopWindow.swift`）里改写 `performKeyEquivalent(with:)` 作为后备：

- 只处理 Command 加 Z / ⇧Z / X / C / V / A 这几个组合；
- 用 `NSApp.sendAction(_:to: nil, from:)` 发出上表对应的 action；
- 其余按键交给 `super`。

用了后备方案的话，在交付记录里写明，`DesktopWindow.swift` 也算在允许修改的范围里。先试第 1、2 节的做法，不要两种都做。

### 4. 测试

- 新建 `Tests/DesktopShellTests/EditMenuTests.swift`：用 `@MainActor` 建菜单，断言这些内容：
  - 有一个子菜单；
  - 子菜单的项目顺序、`action`、`keyEquivalent` 和 `keyEquivalentModifierMask` 和上表一致；
  - 所有项目的 `target` 都是 `nil`。
- 用了后备方案的话：把"按键 → action"的对应关系写成纯函数，补测试。

## 允许修改的文件

- `Sources/DesktopShell/EditMenu.swift`（新建）
- `Sources/DesktopShell/AppDelegate.swift`（修改）
- `Sources/DesktopShell/DesktopWindow.swift`（只在用第 3 节的后备方案时修改）
- `Tests/DesktopShellTests/EditMenuTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不调用 `NSApp.activate`，不改组件窗口获得和交还键盘的逻辑（M3-08）。
- 不改网页：不恢复右键菜单，不在 JS 里自己处理 ⌘V。
- 不让菜单栏出现别的菜单，状态栏图标的菜单保持不变。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build` 无错误、无警告
- [ ] `scripts/test.sh` 全部通过
- [ ] `scripts/bundle.sh` 成功
- [ ] `git diff --name-only main...task/M7-04` 只有上面"允许修改的文件"

**用户手动验证**（用主仓库的 `build/DesktopShell.app`）：

- [ ] 在别的应用里拷贝一段文字，点项目输入框，⌘V → 文字贴进去了
- [ ] 待办输入框里同样能 ⌘V
- [ ] 输入框里打几个字：⌘A 全选，⌘C 拷贝，再到别的应用里 ⌘V 能贴出来；⌘X 剪切后输入框变空；⌘Z 撤销、⇧⌘Z 重做都有效
- [ ] 用拼音输入法打中文照常（候选框位置正常，回车上屏）
- [ ] 不受影响的情况：
  - 输入框没有焦点时（例如刚在桌面空白处点了一下），⌘V 不会把东西贴到组件里；
  - 在别的应用里 ⌘C / ⌘V 照常；
  - 按 Esc 后键盘回到原来的应用。
- [ ] 菜单栏里没有多出 DesktopShell 的菜单，前台应用的菜单栏保持原样

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
