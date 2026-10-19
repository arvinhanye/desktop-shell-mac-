# M4-09: 原生毛玻璃和 M4 整体验收

- **状态**：todo
- **里程碑**：M4
- **依赖**：M4-08、M4-10（都必须已合并到 `main`；所有组件都已就位，才能对着真实的卡片验证毛玻璃；窗口层级在 M4-10 已经改好）
- **分支**：task/M4-09

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

每块底板（`.card`）和打开着的外观面板下面垫上原生毛玻璃，透出被模糊的视频；切换前后台、点击组件时透明度不跳动。做完后整个 M4 对着设计截图验收一遍。

## 背景与约束

- 先读 AGENTS.md：技术探针里的"原生毛玻璃探针"（实测结论，本任务照着做）；"窗口要求"里 WidgetWindow 的层级和"隐藏桌面文件"；Bridge 表里的 `setGlassRegions`；"设计规范"里关于毛玻璃的一条。
- `docs/design/tokens.css` 末尾的 `:root[data-glass="on"]`：页面在应用里、毛玻璃就位后设 `<html data-glass="on">`，底板底色降到 45%，外观面板底色降到 0.6。浏览器里没有毛玻璃，不设这个属性。
- 探针源码在 Claude Code 的临时目录里，不在仓库中；需要的做法都写在下面。

### 1. 窗口层级

- 已在 M4-10 改好（组件窗口图标层 +3，`WindowLevels`，启动日志 `DesktopShell windows: …`）。本任务改 `DesktopWindow.swift` 的内容视图时，**不要动设置面板属性和 `level` 的顺序**（`isFloatingPanel` 的 setter 会改层级，见 M4-10），做完后用 `swift scripts/window-levels.swift` 确认组件窗口仍是 `icon+3`。

### 2. `setGlassRegions`（`BridgeProtocol.swift`、`Bridge.swift`）

- 参数只有 `regions`：最多 64 项，每项 `[x, y, w, h, radius]`，都是有限数字（排除布尔值，做法同 `HitTesting.parseRegions`），`w`、`h` 大于 0，`radius` 在 0 到 `min(w, h) / 2` 之间。多出参数、格式不对 → 整条 `invalid`，记录日志。空数组表示清掉全部毛玻璃。
- 解析时先校验、保留原始数值；应用到窗口时再按网页视图的实际尺寸裁掉超出的部分（和 `setHitRegions` 一样），裁完的矩形如果变小了，`radius` 也收到新矩形 `min(w, h) / 2` 以内；裁完为空的去掉。
- 解析和裁剪写成纯函数（例如放在 `GlassLayer.swift` 里的 `GlassRegions.parse`、`GlassRegions.clip`）。
- 某个窗口的区域数量和上次不同时，记录一行 `DesktopShell bridge: setGlassRegions regions=<数量>`；数量不变只是位置变了不记。

### 3. 毛玻璃层（新建 `GlassLayer.swift`，接到 `DesktopWindow.swift`）

- WidgetWindow 的内容视图改成一个容器：最下面是毛玻璃层，上面是原来的 WKWebView，两者都铺满窗口、跟着窗口尺寸变化。
- 毛玻璃层是一个 `isFlipped = true` 的 `NSView`（坐标和网页一样从左上角算，CSS 像素 = 窗口的点），`hitTest` 返回 `nil`（永远不接收鼠标）。
- 每个区域一个 `NSVisualEffectView`：`material = .hudWindow`、`blendingMode = .behindWindow`、`state = .active`、`appearance = NSAppearance(named: .darkAqua)`。
- 圆角用 `maskImage`：一张 `(2r + 1) × (2r + 1)` 的黑色圆角矩形图，`capInsets` 四边都是 `r`，`resizingMode = .stretch`。同一个半径的图缓存起来复用。
- 更新时复用已有的视图：数量够就改位置，多出来的隐藏，不够再新建；整个更新包在 `CATransaction.begin()` / `setDisableActions(true)` / `commit()` 里，避免隐式动画。
- 页面开始重新加载（`didStartProvisionalNavigation`，包括菜单栏"重新加载"）时清掉全部毛玻璃，等新页面重新上报；窗口关闭时也清掉。
- 点击穿透的判断不变：毛玻璃不接收鼠标，`ignoresMouseEvents` 仍由 `HitTestController` 按点击区域切换。

### 4. 网页上报（新建 `web/js/glass-regions.js`，改 `web/js/main.js`）

- `installGlassRegions({ send, root = document, win = window })`，做法和 `hit-regions.js` 一样：
  - 收集 `.card` 和 `[data-glass]`，只要可见的（`visibility` 为 `visible`、宽高大于 0，`hidden` 的元素自然没有尺寸）。
  - 每个元素报 `[x, y, w, h, radius]`：前四个来自 `getBoundingClientRect()`，**不取整**；`radius` 是 `parseFloat(getComputedStyle(el).borderTopLeftRadius) || 0`。完全在视口外的去掉，最多 64 个。
  - 什么时候重新收集：`ResizeObserver`、`MutationObserver`（`class`、`style`、`hidden`、`data-glass` 属性和子节点增删）、窗口 `resize`、`load`、字体加载完、`transitionend` / `animationend`。同一帧里多次触发合并成一个 `requestAnimationFrame`；结果和上次一样就不发。
  - 区域计算写成导出的纯函数 `toGlassRegions(entries, viewport)`，方便测试。
  - 可以把 `hit-regions.js` 里"观察变化、合并到一帧"的部分提成两边共用的函数，但 `hit-regions.js` 的行为和现有测试不能变。
- `main.js`：只在 `bridge.mode === 'native'` 时安装。第一次 `setGlassRegions` 成功回复后设 `document.documentElement.dataset.glass = 'on'`；失败就不设（底色保持 100%，bridge 已经记了日志）。
- `mock.js` 的白名单加上 `setGlassRegions`（校验 `regions` 是数组，回复 `null`），和 Swift 保持一致；浏览器里 `main.js` 不会安装它。

### 5. 测试

- `Tests/DesktopShellTests/GlassLayerTests.swift`：`GlassRegions.parse`（合法；65 项；布尔值；`NaN`；`w` 为 0；`radius` 为负、超过一半；4 个数字的项；多出参数；空数组）；`clip`（部分超出时裁剪并收小 `radius`；完全在外面的去掉）。
- `Tests/DesktopShellTests/BridgeTests.swift`：`setGlassRegions` 的请求解析和错误码。
- `Tests/web/glass-regions.test.mjs`：`toGlassRegions`（不取整；零尺寸、完全在视口外的去掉；超过 64 截断）；安装后用假的观察器验证同一帧只发一次、结果不变不重发。
- `Tests/web/mock.test.mjs`：mock 接受 `setGlassRegions`，多出参数时 `invalid`。

## 允许修改的文件

- `Sources/DesktopShell/GlassLayer.swift`（新建）
- `Sources/DesktopShell/DesktopWindow.swift`、`WebContainer.swift`、`BridgeProtocol.swift`、`Bridge.swift`（修改）
- `web/js/glass-regions.js`（新建）；`web/js/main.js`、`web/js/mock.js`、`web/js/hit-regions.js`（修改；`hit-regions.js` 只在提取共用代码时动）
- `Tests/DesktopShellTests/GlassLayerTests.swift`（新建），`BridgeTests.swift`（修改）
- `Tests/web/glass-regions.test.mjs`（新建），`Tests/web/mock.test.mjs`、`Tests/web/hit-regions.test.mjs`（修改）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不用 CSS `backdrop-filter`；不改 `tokens.css`、`base.css` 和各组件的样式。
- 不改变窗口层级、点击穿透、键盘焦点（M3-08）和"隐藏桌面文件"的行为。
- 毛玻璃视图不接收鼠标，不让 VideoWindow 接收鼠标。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh`、`scripts/test-web.sh` 全部通过，包含上面列出的新测试
- [ ] `grep -rn "backdrop-filter" web/` 没有输出
- [ ] `git diff --name-only main...task/M4-09` 只包含"允许修改的文件"
- [ ] `scripts/bundle.sh --open` 后 `swift scripts/window-levels.swift`：组件窗口仍是 `icon+3`、视频窗口 `icon-1`，都排在普通应用窗口后面
- [ ] （Claude Code 复验）`scripts/bundle.sh --open` 后，日志里有 `DesktopShell bridge: setGlassRegions regions=5`（角色卡、系统状态、项目、待办、启动栏五块底板）；打开外观面板后变成 `regions=6`，关上回到 5；没有 `setGlassRegions` 被拒的日志。（Swift 只在某个窗口的区域**数量**变化时记这一行，避免刷屏）

**用户手动验证**（`scripts/bundle.sh --open`）——毛玻璃：

- [ ] 每块卡片后面是模糊的视频，卡片边缘和模糊区域对齐，没有露出直角或错位
- [ ] 点卡片里的按钮、切换到别的应用再切回来、点桌面空白处：卡片的透明度都**不跳动**
- [ ] 打开外观面板：面板后面也是毛玻璃；关上后那块毛玻璃消失
- [ ] 菜单栏"隐藏桌面文件"：卡片后面的毛玻璃照常（这时模糊的是盖住图标的视频）；取消后恢复
- [ ] "活动监视器"里 WindowServer 的 CPU 和装毛玻璃之前相比没有明显变化（探针结论：差别在误差以内）

**用户手动验证**——M4 整体（对照 `assets/design-screenshots/` 的截图）：

- [ ] 当前时段的整体效果和对应时段的截图（`01-夜晚` / `02-早晨` / `03-白天` / `04-傍晚`）一致：布局、字体、配色、底板
- [ ] 选中项目（`05-选中项目`）、外观面板（`08-外观面板`）、隐藏桌面文件（`09-隐藏图标看组件区`）三种状态和截图一致
- [ ] 菜单栏"暂停动画"：视频停住，律动条静止；系统状态卡照常更新
- [ ] 右侧两列访达图标能正常选中、框选、拖动、双击打开；拖动框选经过组件时不会被打断
- [ ] 在待办输入框打字（含中文拼音），Esc 退出后键盘回到原来的应用
- [ ] 应用全屏时看不到组件；点过组件之后，其他应用的窗口仍然盖在组件上面（M4-10 的回归检查）
- [ ] 有外接显示器时：每块屏幕都有一套组件和毛玻璃，插拔显示器后正常

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
