# M2-03: 背景视频 + 透明 WKWebView + shell:// 处理器

- **状态**：review
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
  - 启动时打印三个目录、加载配置，出错时仅在内存使用示例；背景路径复用 M2-02 的安全解析。视频缺失时记录提示并保留黑色背景。
  - 全局一个 `AVQueuePlayer` / `AVPlayerLooper`，静音且允许显示器休眠；每个窗口的视频层绑定同一播放器，铺满并裁剪。保留 `play()` / `pause()` 给 M2-04。
  - 每窗一个透明 WKWebView，通过 `shell://app/index.html` 加载测试页；取消其他 scheme 的导航、新窗口返回 nil，开发工具仅在环境变量显式开启时启用。
  - 资源处理器使用后台队列读取映射数据，返回 200 / 206 / 416 / 404 及对应响应头；主队列管理任务和回调，以任务标识及 generation 排除已停止、重入停止和旧任务完成回调。
  - 删除 M1 安全区域调试图与屏幕文字，只保存最新 insets；保留桌面层级、Spaces 行为及多屏增删逻辑。测试页包含心形图片、ES module、穿越请求结果和语音按钮。
  - 改动限于允许的 8 个实现文件及本任务状态、交付记录；未修改 M2-02 逻辑、规范或需求，未接入 bridge、安全区域推送或暂停策略。
- **自测结果**（2026-10-17）：
  - 从已包含 M2-01、M2-02 的最新 `main`（`193a2ef`）建立 `task/M2-03`。基线与最终 `scripts/test.sh` 均 **34/34 通过**，退出码 0；最终 `swift build` 退出码 0，日志经 `grep -iE 'warning|error'` 检查无输出。
  - 任务白名单没有新增测试文件，因此额外集成检查放在 `/tmp/ds-m2-03-validation/`，编译实际生产源文件执行，未加入仓库：
    - `HandlerChecks.swift`：空实现先产生预期失败（19/119 通过），完整实现 **119/119 通过**。覆盖实际响应字节、头、MIME、各种 Range、空文件、scheme/host、编码穿越、符号链接，以及停止前后、回调重入、旧任务回调。
    - `ViewChecks.swift`：空实现 3/21，接入后 **21/21 通过**。真实 WKWebView 完成 ES module 导入、图片加载（naturalWidth 2400）、穿越请求 404、外部导航拦截、透明 alpha 和开发工具开关检查。WebKit 返回的透明颜色使用 sRGB 色彩空间，按 alpha=0 检查，而非与命名颜色对象比较。
    - `WindowChecks.swift`：**11/11 通过**。同机两扇原生窗口共用播放器，两层均 ready 并取得已显示像素；播放时间推进；窗口缩放、层级、Spaces、insets 保存正确。静音测试音频 readyState=4、播放时间推进且无媒体错误。此检查不等同于真实双显示器或可听声音验收。
  - 实际执行 `MEDIA_DIR=/tmp/ds-support/media scripts/prepare-media.sh` 成功，生成 30 秒、2560×1440 HEVC 视频及测试素材。用 `DESKTOPSHELL_SUPPORT_DIR=/tmp/ds-support .build/debug/DesktopShell` 运行约 40 秒，进程正常存活，日志打印三个目录且无缺视频或页面加载错误；随后结束本次测试进程。生成的配置经完整解码比较，等于 `AppConfig.example`。
  - 启动 5 秒后 `pmset -g assertions` 显示 `PreventUserIdleDisplaySleep = 0`，没有 DesktopShell 持有的显示器休眠阻止断言。
  - 按要求执行 `top -l 6 -s 2 -stats pid,command,cpu`。六次样本平均（含首个 0 样本）：DesktopShell **1.68%**、对应 VTDecoder **1.75%**、WebContent **0.00%**；剔除首样本分别为 **2.02% / 2.10% / 0.00%**。top 截短 WebKit 名称，结合 `ps` 全路径按 PID 识别 WebContent；保留原始采样。采样期间项目测试也在运行，这只是本机单屏基线，不是性能验收阈值。
  - 另以临时损坏配置且缺少视频启动：记录解析错误和缺视频提示，5 秒后仍运行，损坏配置逐字节未变。所有应用启动均使用临时支持目录。
  - `git diff --check` 通过；bridge 关键词扫描无输出；M2-02 文件、AGENTS.md 和 CLAUDE.md 无差异。独立只读代码检查未发现 Critical / Important 问题，正式验收仍由 Claude Code 完成。
  - 完整日志、临时检查源文件和网页快照：`/tmp/ds-m2-03-validation/`。快照 `web-snapshot.png` 已查看，标题、图片、状态和按钮无裁切；它只捕获网页，不证明原生视频合成观感。
- **疑问 / 偏离**：
  - 无范围偏离。GUI 验收仍开放：真实桌面的铺满及循环衔接、面板对原生视频的模糊效果、可听语音、Dock/菜单栏和退出、真实双屏同步与热插拔。透明属性及 CSS 已配置，不把它们当成模糊观感的实测结论。可在仓库根目录用上述 `/tmp/ds-support` 启动命令复验，或按任务手动步骤验证真实素材目录。
  - 非阻断 Minor（独立检查提出，保留待后续处理）：临时语音按钮快速重复点击时，上一轮 `play()` 的延迟错误可能写入当前提示，监听器也引用可变的播放对象；不影响正常单次点击。M3 替换临时页面时应使用每次播放的局部对象并校验当前对象，避免陈旧错误提示。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：代码审查通过，可执行检查全部通过；**等用户手动验证后合并**。
- **复验结果**（Claude Code，2026-10-17）：
  - [x] touch 源码后强制重编，零警告零错误；`scripts/test.sh` 34/34 通过
  - [x] 改动范围是 6 个 Swift 文件、2 个网页文件和本任务单，都在允许范围内；M2-02 的 4 个逻辑文件没有改动；`grep` 没有找到 `messageHandlers` 或 `addScriptMessageHandler`
  - [x] 用临时支持目录运行：日志打印出三个目录，没有"背景视频不存在"；`config.json` 等于示例配置，中文没有被转义
  - [x] `pmset -g assertions`：`PreventUserIdleDisplaySleep 0`，视频不阻止显示器休眠
  - [x] CPU（去掉首个样本后的平均值，单屏）：DesktopShell 约 2.0%，VTDecoderXPCService 约 0.5%，WebContent 约 0%。作为后续省电对比的基线
  - [x] SIGTERM 后正常退出
- **意见**（不阻塞）：
  - `ShellSchemeHandler` 用"任务标识 + generation"防止对已停止的任务回调，包括回调过程中被重入停止的情况；文件读取放在后台队列，回调都在主线程。设计严谨。
  - 全局一个播放器，每个窗口各自一个 `AVPlayerLayer`；`WebContainer` 由窗口持有，弱引用的导航代理不会被提前释放；关闭窗口时先停止网页加载。都符合要求。
  - Codex 自己发现的测试页小问题（快速连点语音按钮时可能显示上一次的错误提示）认可为不阻塞：测试页会在 M3 被整体替换，届时 `voice.js` 每次播放都用局部对象，这一点会写进 M3/M4 的任务单。
  - 用于集成检查的 `/tmp/ds-m2-03-validation/` 很有价值，但没有进仓库。WKWebView 和窗口相关的集成测试是否要正式纳入，M3 再决定。
