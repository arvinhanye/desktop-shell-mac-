# M2-03: 背景视频 + 透明 WKWebView + shell:// 处理器

- **状态**：todo
- **里程碑**：M2
- **依赖**：M2-01、M2-02（都必须已合并到 `main`）
- **分支**：task/M2-03

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

桌面窗口的深灰色占位换成**循环播放的背景视频**，上面叠一层**背景透明的 WKWebView**，通过 `shell://app/` 加载 `web/index.html`。这次的网页只是一个 M2 测试页，用来验证透明叠加、ES module、素材读取和语音播放都没问题；正式网页在 M3 做。

## 背景与约束

- 先读 `AGENTS.md` 的"核心架构""窗口要求""省电要求""Bridge 接口"（安全要求），以及 M2-02 写好的 `AppPaths`、`ConfigStore`、`SchemeResolver`。
- 本任务**不做** bridge（`window.webkit.messageHandlers`）和安全区域推送，那是 M3；也**不做**暂停规则，那是 M2-04。

### 启动流程（`AppDelegate`）

1. `let paths = AppPaths.current`，用 `NSLog` 打印三个目录。
2. `ConfigStore(supportDir: paths.supportDir).load()`；出错就 `NSLog` 记录原因并使用 `AppConfig.example`（不要覆盖用户的文件）。
3. 背景视频路径：用 `SchemeResolver(webRoot: paths.webDir, mediaRoot: paths.mediaDir).fileURL(forPath: "/media/" + config.background.video)` 取得，这样配置里的路径也经过同样的安全检查。拿不到时打印 `背景视频不存在：<路径>，请先运行 scripts/prepare-media.sh`，并继续运行（显示纯黑背景）。
4. 创建**一个共享的** `BackgroundPlayer`，交给 `ScreenManager`，所有屏幕共用同一个播放器（只解码一路视频，省电）。

### `BackgroundPlayer.swift`

- `@MainActor final class BackgroundPlayer`，用 `AVQueuePlayer` + `AVPlayerLooper` 无缝循环。
- `isMuted = true`。
- **`preventsDisplaySleepDuringVideoPlayback = false`**（必须设置！默认是 `true`，会让视频壁纸阻止显示器休眠）。
- 提供 `func makeVideoView() -> NSView`：返回一个铺满父视图的视图，背后是绑定到共享播放器的 `AVPlayerLayer`，`videoGravity = .resizeAspectFill`（视频是 16:9，屏幕是 16:10，左右各裁掉约 5%）。没有视频时返回纯黑视图。推荐写法：`NSView` 子类重写 `makeBackingLayer()` 返回 `AVPlayerLayer`。
- 提供 `play()`、`pause()`，M2-04 会用到。启动后自动 `play()`。

### `ShellSchemeHandler.swift`（`WKURLSchemeHandler`）

- 只处理 `shell` scheme 且 host 为 `app` 的请求，其他一律 404。
- 用 `SchemeResolver.fileURL(forPath: url.path)` 找文件，返回 `nil` 就回 404。
- 用 `HTTPURLResponse` 响应：`Content-Type`（来自 `mimeType`，文本类型加 `; charset=utf-8`）、`Content-Length`、`Accept-Ranges: bytes`、`Cache-Control: no-cache`。
- 支持 `Range`：用 `SchemeResolver.parseRange`，`.partial` 回 206 加 `Content-Range: bytes a-b/size`；`.unsatisfiable` 回 416 加 `Content-Range: bytes */size`。
- 读文件用 `Data(contentsOf:options: .mappedIfSafe)`。
- 记录已经被 `webView(_:stop:)` 停止的任务，**停止后不能再对它调用 `didReceive`/`didFinish`**（否则 WebKit 会抛异常导致崩溃）。

### `WebContainer.swift`

- 创建 `WKWebView`：`WKWebViewConfiguration` 注册 `ShellSchemeHandler` 处理 `shell` scheme。
- **背景透明**：`webView.setValue(false, forKey: "drawsBackground")`，再加上 `underPageBackgroundColor = .clear`。
- 加载 `shell://app/index.html`。
- `WKNavigationDelegate`：只允许 scheme 为 `shell` 的导航，其他一律 `.cancel` 并 `NSLog` 记录（规范：不加载外部网站）。`WKUIDelegate` 的新窗口请求一律返回 `nil`。
- `allowsBackForwardNavigationGestures = false`，`allowsMagnification = false`。
- 环境变量 `DESKTOPSHELL_DEVTOOLS=1` 时设置 `webView.isInspectable = true`（可以用 Safari 的"开发"菜单调试网页），默认关闭。

### `DesktopWindow.swift` / `ScreenManager.swift`

- 窗口内容改为：底层是 `BackgroundPlayer.makeVideoView()`，上层是 `WebContainer` 的 `WKWebView`，两者都铺满窗口并跟随窗口大小变化。
- **删除** M1 的 `SafeAreaDebugView` 和屏幕名称文字。`updateSafeArea(_:)` 保留，只把最新的 insets 存进属性，M3 推送给网页时用。
- 窗口层级、`collectionBehavior` 等 M1 的设置保持不变。

### M2 测试页（`web/index.html` + `web/m2-check.js`）

这是临时页面，M3 会整体替换，所以 `tokens.css` 的规则暂不适用，样式直接写在页面里。内容：

- `html, body` 背景透明，铺满窗口。
- 屏幕中央一个半透明面板（例如 `rgba(20,20,30,0.45)` 加 `backdrop-filter: blur(12px)`、圆角），面板里依次是：
  1. 标题"DesktopShell · M2 测试页"
  2. `<img src="/media/ornaments/heart.png">`，宽 480px
  3. 一行状态"ES module：…"：由 `<script type="module">` 从 `./m2-check.js` 导入一个字符串，成功时显示"ES module OK"
  4. 一行状态"路径穿越测试：…"：`fetch('/media/..%2fconfig.json')`，返回 404 时显示"404 ✓"，其他结果显示实际状态码和"✗"。（浏览器不会规范化 `%2f`，Swift 的 `url.path` 会把它解码成 `/media/../config.json`；如果检查有漏洞，就会读到 `supportDir/config.json`。）
  5. 一个按钮"播放测试语音"：`new Audio('/media/voice/1.mp3').play()`，失败时在按钮下方显示错误信息
- 面板之外的区域什么都没有（完全透明，能看到视频）。

## 允许修改的文件

- `Sources/DesktopShell/AppDelegate.swift`（修改）
- `Sources/DesktopShell/ScreenManager.swift`（修改）
- `Sources/DesktopShell/DesktopWindow.swift`（修改）
- `Sources/DesktopShell/BackgroundPlayer.swift`（新建）
- `Sources/DesktopShell/WebContainer.swift`（新建）
- `Sources/DesktopShell/ShellSchemeHandler.swift`（新建）
- `web/index.html`（新建）
- `web/m2-check.js`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"，特别是：不加载任何外部网站，不开放 bridge 动作。
- 不实现 `window.webkit.messageHandlers`、安全区域推送、暂停规则。
- 不修改 M2-02 的逻辑文件。如果发现它们有问题，在交付记录里说明，不要直接改。
- 不给每块屏幕各建一个 `AVPlayer`。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过
- [ ] `git diff --name-only main...task/M2-03` 只包含"允许修改的文件"
- [ ] `grep -rn "messageHandlers\|addScriptMessageHandler" Sources/ web/` 没有输出
- [ ] 准备一份测试素材后运行：`MEDIA_DIR=/tmp/ds-support/media scripts/prepare-media.sh`，然后 `DESKTOPSHELL_SUPPORT_DIR=/tmp/ds-support .build/debug/DesktopShell &`，等 5 秒：
  - [ ] 日志里打印出三个目录，没有"背景视频不存在"
  - [ ] `pmset -g assertions | grep -i -A3 DesktopShell` **没有** `PreventUserIdleDisplaySleep`（视频不阻止显示器休眠）
  - [ ] 记录 `top -l 6 -s 2 -stats pid,command,cpu | grep -E "DesktopShell|WebContent|VTDecoder"` 的平均值（只记录，作为省电基线）
  - [ ] 结束进程后，`/tmp/ds-support/config.json` 存在且内容是示例配置

**用户手动验证**（先运行 `scripts/prepare-media.sh`，再在仓库根目录运行 `.build/debug/DesktopShell`）：

- [ ] 桌面是循环播放的爱弥斯视频，铺满整屏没有黑边；等 30 秒以上，循环衔接处没有黑屏或卡顿
- [ ] 屏幕中央是半透明的测试面板，能透过面板模糊地看到视频；面板之外完全透明
- [ ] 面板里能看到心形装饰图，"ES module OK"，"路径穿越测试：404 ✓"
- [ ] 点"播放测试语音"能听到语音
- [ ] 普通窗口仍在桌面之上，Dock 和菜单栏正常
- [ ] （有外接显示器时）两块屏幕播放同一段视频，画面同步
- [ ] 菜单栏 → 退出，正常退出

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
