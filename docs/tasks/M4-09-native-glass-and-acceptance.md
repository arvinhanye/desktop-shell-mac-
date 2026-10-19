# M4-09: 原生毛玻璃和 M4 整体验收

- **状态**：done
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
  - `GlassRegions.parse` 严格校验五元区域、64 项上限、有限数字且排除布尔；`clip` 在实际网页视口裁剪并收小圆角。Bridge 接入严格参数白名单，失败回复 `invalid`。
  - WidgetWindow 使用容器叠放 `GlassLayer` / WKWebView，铺满并随尺寸变化；保留原有面板属性、层级赋值顺序和点击/键盘控制。毛玻璃使用 `.hudWindow` / `.behindWindow` / `.active` / `.darkAqua`，复用视图与可拉伸圆角 mask，更新关闭隐式动画；导航开始和关闭窗口时清空，仅区域数量变化记日志。
  - 网页仅 native 模式安装 reporter，保留小数坐标，观察布局/可见性/字体/过渡变化，每帧合并、结果去重；装饰后代变化不触发连续扫描。首次成功回复后才启用玻璃 token，mock 浏览器保持原底色。
  - 特别排除 `document.documentElement`：根节点的 `data-glass="on"` 是能力标记，不是整屏底板；增加 RED→GREEN 回归。hit-regions.js、所有 CSS/设计文件保持原样。
- **自测结果**（2026-10-19）：
  - 基线：Swift **167/167 PASS**；网页 **403/403 PASS**。
  - RED：新增 Bridge 两项测试均因 `unknown-action` 失败；mock 新动作测试同样失败。新区域文件实现前分别报告缺少 Swift 类型/JS 模块，属接口尚未实现，不计行为测试通过。入口未接线时真实 main 测试失败；根能力标记测试捕获多报整屏区域后修复。
  - 测试编写期间修正 `CGFloat.infinity` 类型歧义和 Testing 宏 key-path 写法；最终无编译错误。
  - 最终：`scripts/test.sh` **174/174 PASS，20 suites**；`scripts/test-web.sh` **412/412 PASS**，包含新解析/裁剪/视图复用/窗口 resize/导航/关闭、上报去重/可见性/native 成功与失败/mock 回退测试。
  - `swift build` **PASS**，真实退出码 0，warning/error 检索无输出。`grep -rn "backdrop-filter" web/` 无匹配；`git diff --check` **PASS**。13 个改动文件均在允许范围，未改需求与 Claude 审查记录。
  - `scripts/bundle.sh --open` **PASS**：release 打包、固定 `DesktopShell Self-Signed` 证书校验通过并重启。`swift scripts/window-levels.swift`：组件 **icon+3**、视频 **icon-1**，均 `behind app windows`。
  - 真实应用启动日志（PID 18932）：`widget=icon+3 video=icon-1`，随后 `setGlassRegions regions=5`，该启动检查范围内无被拒日志。测试进程的 1/0 区域日志单独识别，未算作真实应用证据。
  - 浏览器：普通 mock 页面根节点无 data-glass，底板 opacity=1、面板底色 alpha=0.9；打开外观面板无 warn/error。另用 `/tmp` 下的 native 传输替身承接真实网页，点击外观/完成观察 **5→6→5**，无 warn/error。该测试只证明网页上报，不等同原生模糊或原生 5→6→5 日志验收；1280×720 预览不作为目标桌面布局验收。
  - 独立只读子代理 `m409_glass_review`：检查全部 13 个文件，独立针对测试 **72 PASS**，未发现可复现的 Critical/High/Medium 问题；这不替代 Claude Code 复验与合并。
  - 本地证据：`/tmp/desktopshell-m4-09-check/` 下保存 baseline、RED、最终测试/构建/打包/窗口日志；截图为 `browser-mock-appearance.jpg` 和 `browser-regions-5-6-5.jpg`。
- **疑问 / 偏离**：
  - 无视觉或接口扩展，M4-11 保持暂缓；交接只写本任务单，未改额外交接文件。
  - 审查保留项：相同失败区域不自动重试（沿用既有去重约定，首次失败保留原底色，需布局变化或重载后再报）；半径缓存不额外限额（当前定稿半径固定）；首次成功后的后续失败不撤销 data-glass（原生保留上次成功区域）。未增加这些任务外策略；若未来动态圆角或持续传输故障成为实际需求，再单独处理。
  - **待 Claude 复验**：真实应用打开/关闭外观面板的日志 **5→6→5** 与无拒绝日志。
  - **待用户手动验收**：卡片模糊及圆角对齐；点击/切换应用透明度稳定；外观玻璃显示/消失；隐藏桌面文件开关；WindowServer CPU 前后对比；与目标设计截图逐态对照；暂停时系统状态继续刷新；Finder 选择/框选/拖动/双击；中文输入与 Esc 交还键盘；全屏/普通应用遮挡；外接显示器插拔。以上未标为 PASS，M4 整体验收仍待完成。
  - 回退方式：Claude 合并前保持 main 不变；需要撤回运行效果时从已合并的 main 重新签名打包，不改写已推送历史，不调整用户配置或提醒事项数据。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**通过**，已合并到 `main`。代码审查和自动验收见下；手动验证 2026-10-19 完成并对照了日志（见最后）。**M4 完成**（M4-11 头像光环暂缓）。
- **复验结果**（Claude Code，2026-10-19，在 `4042684` 的独立检出上执行；打包在主目录的同一提交上执行）：
  - [x] `swift build` 零警告零错误；`scripts/test.sh` 174 项全部通过（20 个 suite，含 `GlassLayerTests`）；`scripts/test-web.sh` 412 项全部通过
  - [x] 只改了允许的 13 个文件（`hit-regions.js` 和它的测试没动）；`git diff --check` 通过；`grep -rn "backdrop-filter" web/` 没有输出；样式、组件、`docs/design/` 都没动
  - [x] M4-10 的层级顺序保留：`isFloatingPanel` 在第 75 行、设 `level` 在第 83 行
  - [x] `scripts/bundle.sh --open`（`07:56:21`）：日志 `windows: … widget=icon+3 video=icon-1`、`setGlassRegions regions=5`，没有被拒的记录；`swift scripts/window-levels.swift` 两个窗口都在普通应用窗口后面
  - [x] WindowServer CPU（开着毛玻璃，接电源，后台有其他应用）：每 2 秒一次、共 8 次，52–69%，和 M3.5 探针的结论（开 54–64%、关 55–65%）一致，看不出额外开销。供"活动监视器"那一项参考
- **意见**：
  - Swift：`GlassRegions.parse` 严格校验（5 个有限数字、排除布尔、最多 64 项、半径不超过短边一半），`clip` 按网页视图实际尺寸裁剪并收小半径，都是纯函数；`GlassLayer` 是翻转坐标、不接收鼠标的视图，复用 `NSVisualEffectView`（`.hudWindow` / `.behindWindow` / `.active` / 深色外观），圆角 mask 按半径缓存，更新时关闭隐式动画；窗口内容改成容器，毛玻璃在下、网页在上；页面开始加载、窗口关闭时清空；只在数量变化时记日志。和任务单一致。
  - 网页：只在应用里（`bridge.mode === 'native'`）安装；上报 `.card` 和 `[data-glass]`，保留小数，合并到一帧、结果不变不重发；第一次成功后才设 `data-glass="on"`。**Codex 额外处理得好的一点**：`<html data-glass="on">` 本身也匹配 `[data-glass]`，不排除的话会多报一块整屏的毛玻璃，Codex 排除了根元素并加了回归测试。律动条每秒 30 次的样式变化不会触发重新收集。
  - 交付记录里的三个保留项（同一组区域失败后不自动重试、半径缓存不设上限、成功后再失败不撤销 `data-glass`）都可以接受：现在定稿只有一种圆角，传输失败要靠重新加载恢复，和点击区域的做法一致。
- **手动验证**（2026-10-19，用户在 Claude Code 打包启动的 `4042684` 上验证，Claude Code 对照日志）。对照截图时的两处已知出入：按钮的字以 `design.css` 为准；头像发光仍是旧的整张图发光（M4-11 暂缓）。
  - 毛玻璃：
    - [x] 卡片后面是模糊的视频，边缘和模糊区域对齐（用户目测）
    - [x] 点按钮、切换应用、点空白处时透明度不跳动（用户目测）
    - [x] 外观面板的毛玻璃：`07:58:25 setGlassRegions regions=6`，关上后 `07:59:02 regions=5`
    - [x] 隐藏桌面文件时毛玻璃照常：`08:00:12 windows: … video=icon+3`，`08:00:15` 回到 `video=icon-1`
    - [x] WindowServer 的 CPU 没有明显变化（Claude Code 实测 52–69%，和探针一致）
  - M4 整体：
    - [x] 当前时段的整体效果、选中项目 / 外观面板 / 隐藏桌面文件三种状态和截图一致（用户目测）
    - [x] 暂停动画：`08:00:16 power: paused=true reasons=[manual]`，`08:00:18` 恢复；视频停住、律动条静止、系统状态卡照常（用户目测）
    - [x] 访达图标选中、框选、拖动、双击正常（用户目测）
    - [x] 待办输入：`07:59:56 focusInput ok` → `08:00:02 blurInput ok`，另一次 `08:00:05` → `08:00:20`
    - [x] 应用全屏时看不到组件，点过组件后其他应用的窗口仍在上面（用户目测）
    - [x] 外接显示器：用户确认（没有外接显示器时这一项跳过）
  - 备注：用户第一次说"做完了"时日志里只有外观面板的 5 → 6 → 5，隐藏桌面文件、暂停、待办输入三项是之后补做的
