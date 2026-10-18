# M3-08: 组件窗口改为不激活应用的面板，实现键盘焦点（focusInput / blurInput）

- **状态**：todo
- **里程碑**：M3
- **依赖**：M3-07（必须已合并到 `main`；会改到 M3-04 到 M3-07 也改过的 Bridge 相关文件）
- **分支**：task/M3-08

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

1. 点桌面组件上的按钮、勾选框，**不再**把 DesktopShell 切到前台，也不会抢走你正在用的应用（例如 Cursor、文本编辑）的键盘。
2. 组件里的文本输入框可以正常打字，英文和中文拼音都行；按 Esc、或者点别处之后，键盘回到原来的应用。

## 背景与约束

- 先读 `AGENTS.md`：技术探针里的**"键盘焦点探针"**（2026-10-18 实测结论，本任务照着做）、窗口要求（WidgetWindow 和"需要输入文字的组件"两条）、Bridge 表里的 `focusInput` / `blurInput`。
- 现状：WidgetWindow 是普通无边框 `NSWindow`，不能成为 key window，所以输入框打不了字；而且点一下组件，系统就会把 DesktopShell 切到前台，原来的应用失去键盘（M3-03 验收时用户已确认打不了字，探针确认会抢焦点）。
- **不调用 `NSApp.activate`**。面板成为 key window 时 `NSApp.isActive` 会变成 `true`，但前台应用没变，逻辑里不要依赖它。
- 点击穿透（`HitTestController` 切换 `ignoresMouseEvents`）、隐藏桌面文件、窗口层级和 `collectionBehavior` 的行为**完全不变**。

### 1. WidgetWindow 改为面板（`DesktopWindow.swift`）

- `WidgetWindow` 改为继承 `NSPanel`，初始化时 `styleMask: [.borderless, .nonactivatingPanel]`（**必须在初始化时给**，不要创建后再改 `styleMask`）。
- `hidesOnDeactivate = false`（**必须**：否则 `NSApp.deactivate()` 时面板会被隐藏）；`isFloatingPanel = false`；层级、`collectionBehavior`、透明、无阴影等设置照旧。
- 新增 `var acceptsKeyboard = false`；`override var canBecomeKey: Bool { acceptsKeyboard }`；`override var canBecomeMain: Bool { false }`。
- 面板失去 key window 状态时（`didResignKey`），把 `acceptsKeyboard` 设回 `false`（防止网页没来得及发 `blurInput` 的情况）。
- `VideoWindow` 不改。

### 2. Bridge 动作（`BridgeProtocol.swift`、`Bridge.swift`）

- `BridgeRequest` 增加 `.focusInput`、`.blurInput`，都没有参数（多出参数 → `invalid`），不再回复 `unknown-action`。来源校验照旧。
- `focusInput`：`window.acceptsKeyboard = true`，`window.makeKey()`，`window.makeFirstResponder(webView)`；回复 `nil`。
- `blurInput`：`window.acceptsKeyboard = false`；如果它仍是 key window，调用 `NSApp.deactivate()`；回复 `nil`。
- 窗口已释放 → `failed`（和 `setHitRegions` 一样）。
- 日志：`DesktopShell bridge: focusInput ok`、`DesktopShell bridge: blurInput ok`（不写内容）。

### 3. 网页的通用焦点处理（新建 `web/js/keyboard-focus.js`，`main.js` 安装）

```js
export function isTextEntry(element)                         // 纯函数，供测试
export function installKeyboardFocus({ doc = document, win = window, send })
```

- **`isTextEntry`**：`textarea`；`input` 且 `type` 为 `text`、`search`、`email`、`url`、`tel`、`password`、`number` 或没写 `type`；`contenteditable` 为 `true` 的元素。**勾选框、单选框、按钮、滑块等不算**（点勾选框绝对不能接管键盘）。
- **`installKeyboardFocus`**（都在 `doc` 上监听，捕获阶段）：
  - `focusin`：目标是文本输入框 → `send('focusInput')`。
  - `focusout`：失去焦点的是文本输入框，并且新获得焦点的元素（`relatedTarget`）不是文本输入框 → `send('blurInput')`。在两个输入框之间切换时不发。
  - `keydown`：在文本输入框里按 Esc，并且不在输入法组字过程中（`event.isComposing` 为 `false`）→ 让它 `blur()`。组字时按 Esc 是取消候选词，不能退出输入。
  - `win` 的 `blur`（整个页面失去焦点，例如用户点了别的应用）：如果当前焦点在文本输入框上，就让它 `blur()`，避免以后应用被激活时 WebKit 把焦点恢复回来。
  - `send` 失败只忽略（bridge 已经打印警告）。
- `main.js`：在 `createBridge` 之后调用 `installKeyboardFocus({ send: action => bridge.send(action) })`。
- `mock.js`：`focusInput`、`blurInput` 不带参数时 resolve `null`（不再是 `unknown-action`），多出参数 → `invalid`。

### 4. 测试

- `BridgeTests.swift`：`focusInput`、`blurInput` 的解析（合法；多出参数 → `invalid`）；从"尚未实现的动作"测试里去掉这两个。
- `Tests/web/keyboard-focus.test.mjs`（用假的元素和事件对象）：`isTextEntry` 对 `text` / 无 `type` / `search` / `password` / `textarea` / `contenteditable` 为真，对 `checkbox` / `radio` / `button` / `range` / 普通 `div` 为假；聚焦文本输入框发 `focusInput`、聚焦勾选框不发；从输入框移到页面空白处发 `blurInput`；从一个输入框移到另一个输入框不发；Esc 让输入框失焦、组字中按 Esc 不失焦；页面 `blur` 时让聚焦的输入框失焦。
- `Tests/web/mock.test.mjs`：`focusInput`、`blurInput` resolve `null`，多出参数 → `invalid`。

## 允许修改的文件

- `Sources/DesktopShell/DesktopWindow.swift`、`Bridge.swift`、`BridgeProtocol.swift`（修改）
- `Tests/DesktopShellTests/BridgeTests.swift`（修改）
- `web/js/keyboard-focus.js`（新建）、`web/js/main.js`、`web/js/mock.js`（修改）
- `Tests/web/keyboard-focus.test.mjs`（新建）、`Tests/web/mock.test.mjs`（修改）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不调用 `NSApp.activate`，不改 `setActivationPolicy`，不注册全局快捷键。
- 不修改 `HitTesting`、`HitTestController`、`PowerMonitor`、`ScreenManager` 的逻辑（类型从 `NSWindow` 变成 `NSPanel` 带来的编译调整除外，需要时在交付记录里说明）。
- 不修改组件和自检面板的界面。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 和 `scripts/test-web.sh` 全部通过，包含上面列出的新测试
- [ ] `git diff --name-only main...task/M3-08` 只包含"允许修改的文件"
- [ ] `grep -n "nonactivatingPanel" Sources/DesktopShell/DesktopWindow.swift` 和 `grep -n "hidesOnDeactivate = false" Sources/DesktopShell/DesktopWindow.swift` 都有输出
- [ ] `grep -rn "NSApp.activate\|activate(ignoringOtherApps" Sources/` 没有输出
- [ ] 浏览器（mock）里：点自检面板的输入框、按 Esc，控制台没有 `focusInput` / `blurInput` 失败的警告

**用户手动验证**（`scripts/bundle.sh --open`，旁边开一个"文本编辑"文稿，每一步开始前先点一下文本编辑，确认它在前台）：

- [ ] 点自检面板的按钮（例如时段"夜晚"）和勾选框（例如"显示安全区域"），然后直接打字：字进了**文本编辑**（不再被抢走）
- [ ] 点自检面板的输入框，打英文和中文拼音（例如"你好"）：都能打进去，候选词窗口位置正常
- [ ] 打完按 Esc，然后直接打字：字进了文本编辑；**面板没有消失或闪烁**
- [ ] 点输入框打几个字，然后直接点文本编辑的窗口，再打字：字进了文本编辑
- [ ] 点输入框打字时，把鼠标移到面板外面（桌面空白处），继续打字：字仍然进输入框
- [ ] 点输入框后，点桌面空白处的一个图标：图标被选中，输入框不再有光标
- [ ] 打字并按 Esc 之后，点开菜单栏的 DesktopShell 菜单再关掉，然后打字：字仍然进文本编辑
- [ ] 菜单栏"隐藏桌面文件"状态下，重复第 1、3 条，结果相同；验证后取消隐藏
- [ ] 回归：点击穿透（空白处选中、框选、双击、右键访达菜单）和自检面板的各个按钮都和之前一样

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
