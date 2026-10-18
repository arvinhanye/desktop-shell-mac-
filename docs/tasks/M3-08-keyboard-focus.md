# M3-08: 组件窗口改为不激活应用的面板，实现键盘焦点（focusInput / blurInput）

- **状态**：done
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
  - `WidgetWindow` 改为初始化即含 `.nonactivatingPanel` 的 `NSPanel`，保留原有层级、透明与点击穿透配置；设置 `hidesOnDeactivate = false`、`isFloatingPanel = false`，仅文本输入期间允许成为 key，始终不成为 main。通过 AppKit 的 `resignKey()` 覆盖点清除键盘资格。
  - 接入严格无参数的 `focusInput` / `blurInput`；保留来源校验、窗口失效的 `failed` 回复及不含用户内容的日志。没有新增激活应用调用。
  - 新增通用网页焦点模块并在入口安装，处理文本输入识别、输入框间切换、Esc 组字保护、页面失焦清理及 Promise 失败消化；mock 同步支持两个动作。
  - 补充重载保护：替换网页前先清除键盘资格，若窗口仍为 key 则交还键盘，避免旧输入框销毁后保留键盘占用。
- **自测结果**（2026-10-18）：
  - 前置：从最新 `main`（`17ffd4f`）建立 `task/M3-08`，确认 M3-07 已合并，起始工作区干净。
  - RED → GREEN：新增 Swift 焦点解析测试先因 `unknown-action` 失败；mock 三项先失败；网页焦点模块空实现时七项行为断言失败；原生面板探针先因仍为 `NSWindow` 失败。实现后全部通过。重载残留另以原生断言确认失败，再修复为通过。
  - `swift build`：PASS，退出码 0，输出检索 `warning|error` 为空。
  - `scripts/test.sh`：**152/152 PASS，17 suites**；`scripts/test-web.sh`：**149/149 PASS，0 FAIL / 0 SKIP**。最终重载修复后已重跑两套完整测试。
  - 浏览器 mock：实际点击输入框并输入，`activeElement` 为 `INPUT`；实际按 Esc 后为 `BODY`，控制台 warn/error 列表为空。截图：`/tmp/ds-m3-08-validation/browser-focus-escape.png`。
  - 隔离原生探针：**13/13 PASS**，覆盖真实 WKWebView 回复、key/第一响应者、前台应用保持、失焦后面板仍显示、额外参数拒绝、网页 Esc、合成组字事件保护、失去 key 兜底、聚焦后重载和窗口失效。探针仅使用临时配置与屏幕外面板，没有访问或改写真实提醒事项。早期连续切焦点探针出现一次时序超时；等待前一轮原生与网页失焦完成后，同一检查序列通过。合成组字事件不等于真实输入法验收。
  - `scripts/bundle.sh --open`：最终 release 包 PASS，固定证书签名、严格验证通过，指定要求仍为 `identifier "local.desktopshell.DesktopShell" and certificate leaf = H"7d0b2eb51dec80fa75cdbd1d01ace77cee1c62ce"`。产物：`/Users/arvinhan/Desktop/desktop-shell/build/DesktopShell.app`，已打开。
  - 范围检查：仅任务允许的 **10 个文件**；`git diff --check` PASS；两项面板配置检索均有结果；禁止的激活调用检索为空。独立只读代码审查未发现阻塞项；其建议验证的重载边界已复现并修复。
  - 自测日志与原生探针保留于 `/tmp/ds-m3-08-validation/`，包括 `swift-final.log`、`web-final.log`、`build-final.log`、`native-final.log`、`reload-red.log`、`bundle-final.log` 和 `FocusBridgeProbe.swift`。
- **疑问 / 偏离**：
  - 在允许修改的 `DesktopWindow.swift` 重载入口增加键盘交还，依据是原生复现的旧文档键盘资格残留；没有扩展 Bridge 接口、修改其他模块或改变界面。
  - 本任务的九项用户手动验证仍待完成：真实英文/中文拼音与候选框位置、按钮和勾选框不抢文本编辑键盘、Esc 与跨应用/Finder/菜单交还、面板无闪烁、移出面板继续输入、隐藏桌面文件模式及点击穿透回归。上述自动检查不替代这些 GUI 验收。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**通过**，已合并到 `main`。用户 2026-10-18 手动验证（对照"文本编辑"和 Word）：
  - 第 1、2、4、5、6、8、9 条第一轮就通过：点按钮和勾选框不再抢键盘；英文和中文拼音都能输入，候选词窗口位置正常；点别的应用、移出面板继续输入、点桌面图标、隐藏桌面文件模式、点击穿透回归都正常。
  - 第 3 条（Esc 后打字）和第 7 条（Esc 后开关菜单栏菜单再打字）第一轮没通过：字没进文本编辑 / 进了面板输入框。日志里每次 Esc 都有成对的 `focusInput ok` / `blurInput ok`。重测时只打英文，两条都通过；再分别测"选好字、候选框消失后按一次 Esc"和"候选框还开着时按两次 Esc（第一次取消候选框）"，也都通过。第一轮的失败应该是按 Esc 时拼音候选框还开着——这时 Esc 只取消候选框、输入框保持焦点，是有意的设计。**写进 M3.5 / M4**：待办输入框的提示文字或交互说明里体现"有候选框时第一次 Esc 取消候选，第二次退出输入"。
- **复验结果**（Claude Code，2026-10-18，在 `be233f2` 的独立检出上执行）：
  - [x] `swift build` 零警告零错误（测试编译也没有警告）
  - [x] `scripts/test.sh`：152 项全部通过（17 个 suite）；`scripts/test-web.sh`：149 项全部通过
  - [x] 只改了允许的 10 个文件；`HitTesting`、`HitTestController`、`ScreenManager`、`PowerMonitor` 和组件界面都没改；`git diff --check` 通过
  - [x] `nonactivatingPanel`、`hidesOnDeactivate = false` 都有输出；`NSApp.activate` / `activate(ignoringOtherApps` 没有输出
  - [x] 内置浏览器（mock）：聚焦自检面板的输入框后 `activeElement` 是输入框，按 Esc 后回到 `BODY`；组字中（`isComposing: true`）按 Esc 不失焦；聚焦勾选框不发请求；全程没有 warn / error
  - [x] 在主目录（`task/M3-08` = `be233f2`）重新 `scripts/bundle.sh --open`，启动日志正常
- **意见**：
  - `WidgetWindow` 改为 `NSPanel`，`.nonactivatingPanel` 在初始化时就给出；`canBecomeKey` 只看 `acceptsKeyboard`，`canBecomeMain` 为 `false`；用重写 `resignKey()` 在失去 key 时清除资格，和任务单要求的 `didResignKey` 效果相同。
  - **超出任务单但合理的补充**：重新加载页面前先清除键盘资格，如果仍是 key window 就 `NSApp.deactivate()`。Codex 实测在输入框有焦点时重新加载，旧页面销毁不会发 `blurInput`，窗口会一直占着键盘。改在允许修改的 `DesktopWindow.swift` 里，接受。
  - 网页模块用 `isContentEditable` 判断可编辑区域（比只看 `contenteditable="true"` 属性更完整，也覆盖可编辑区域里的子元素）；`input` 没写 `type` 时按 `text` 处理；`send` 失败被吞掉，不会出现未处理的 Promise。
  - **写进 M4 的要求**：组件里的文本输入框不需要自己处理焦点，`keyboard-focus.js` 已经统一处理；不要在组件里另外调用 `focusInput` / `blurInput`。
