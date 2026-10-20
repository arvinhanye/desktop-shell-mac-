# DesktopShell：个人 Mac 换皮桌面

> 本文件是项目的**唯一规范来源**，Codex 和 Claude Code 都以它为准。
> Codex 自动读取本文件；Claude Code 通过 `CLAUDE.md` 里的 `@AGENTS.md` 引入。
> 本文件只由用户或 Claude Code（经用户同意）修改，Codex 不修改。

## 项目背景

为自己的 Intel Mac 做一个覆盖整个桌面的"换皮桌面"应用。仅供个人使用，不上架、不分发。

需求在前期讨论中已经定下来，**以下决定不需要重新讨论**：

- **覆盖整个桌面**，Dock 和菜单栏保留系统原生。
- **保留访达桌面图标**（2026-10-17 改定，原方案是隐藏）：图标显示在视频壁纸之上、组件之下，可以正常选中、框选、拖动、双击打开。做法见"窗口要求"。
- **不做终端**。
- **不做文件管理器**，文件操作一律交给 Finder 或指定应用。
- **所有组件风格高度统一、可以互相联动**，这是核心需求。

用户不一定装了完整的 Xcode。开发由多个 AI 智能体分工完成，见下文"多智能体协作"。

## 核心架构

```
每块屏幕两个无边框、覆盖整屏的窗口，把访达的桌面图标夹在中间：
  ├─ 上层 WidgetWindow（图标和系统桌面小组件之上）：原生毛玻璃层 + 透明背景的 WKWebView，所有组件都在这一个网页里
  │     ├─ tokens.css：唯一的设计规范（配色/字体/圆角/阴影/动效）
  │     ├─ store.js：唯一的共享状态，组件之间通过它联动
  │     └─ bridge.js：与 Swift 通信的唯一入口
  │     鼠标在组件区域内才接收点击，其余区域点击穿透给访达（动态切换 ignoresMouseEvents）
  ├─ 中间：访达的桌面图标、系统桌面小组件（系统的，不归我们管）
  └─ 下层 VideoWindow（图标之下）：AVPlayerLayer 循环播放背景视频（硬件解码，省电），不接收鼠标
系统音频捕获（全局唯一）：Core Audio process tap → 频谱分析 → 推送 audioSpectrum 给每个网页
菜单栏 NSStatusItem：暂停动画 / 隐藏桌面文件 / 语音开关 / 重新加载 / 打开配置文件夹 / 退出
运行时素材：~/Library/Application Support/DesktopShell/media/（视频、语音、头像、背景图）
```

**原则：统一和联动都靠"所有组件放在同一个页面、共享一份设计规范和一份状态"实现。** 不要为每个组件开独立的窗口或独立的 WebView。

## 技术选型

| 部分 | 选择 | 说明 |
|---|---|---|
| 语言 | Swift | |
| 窗口与系统集成 | AppKit | 不用 SwiftUI 管窗口 |
| 构建 | Swift Package Manager | 用一个脚本把可执行文件组装成 `.app` |
| 网页容器 | WKWebView | 背景透明 |
| 网页资源加载 | 自定义 URL scheme（`WKURLSchemeHandler`，例如 `shell://`） | 不用 `file://`，避免 ES module 和跨域问题 |
| 前端 | 原生 HTML / CSS / JS + ES modules，**无构建步骤** | 组件数量少，不需要框架；状态用一个小的发布订阅 store |
| 背景 | AVPlayer + AVPlayerLooper | 视频型壁纸转成 HEVC，**4K（3840×2160）**（2026-10-18 改定：屏幕按 3584×2240 渲染，1440p 要放大 1.56 倍、发虚；实测 4K 和 1440p 的耗电测不出差别） |
| 系统音频 | Core Audio process tap（macOS 14.2+）+ Accelerate（vDSP FFT） | 只需要"系统录音"权限，不需要屏幕录制权限；必须是打包签名的 `.app`，`Info.plist` 写 `NSAudioCaptureUsageDescription`。可行性见下文"技术探针" |
| 素材处理 | ffmpeg（视频转码）+ `sips`（图片缩放） | 由 `scripts/prepare-media.sh` 统一完成 |
| 沙盒 | 关闭 App Sandbox | 自用 |
| 签名 | 固定的自签名代码签名证书 | 避免每次编译后系统权限失效或反复弹窗 |
| 提醒事项 | EventKit（`requestFullAccessToReminders`） | 待办直接读写系统"提醒事项"，经 iCloud 与 iPhone 同步；需要"提醒事项"权限，`Info.plist` 写 `NSRemindersFullAccessUsageDescription`。可行性见下文"技术探针" |
| 数据存储 | `~/Library/Application Support/DesktopShell/` 下的 JSON 文件 | Swift 负责读写（待办不在这里，在系统提醒事项里） |

## 开发环境（M0 已确认，2026-10-16）

| 项目 | 结果 |
|---|---|
| 机器 | Intel Core i7-9750H，`x86_64` |
| 系统 | macOS 26.6.2 |
| 工具链 | 只有 Command Line Tools（`/Library/Developer/CommandLineTools`），**没有完整 Xcode** |
| Swift | 6.3.3，SDK 包含 MacOSX26.sdk |
| git / Codex CLI | git 2.50.1，codex-cli 0.154.0 |
| Cursor bundle id | `com.todesktop.230313mzl4w4u92`（已确认） |
| 签名证书 | `DesktopShell Self-Signed`（2026-10-17 由用户按 `scripts/setup-signing.md` 创建，SHA-1 `7D0B2EB5…62CE`）。已验证：未受信任也能签名；两次不同编译的指定要求都是 `identifier "…" and certificate leaf = H"7d0b2eb5…"`，完全一致，重新编译后系统权限不会失效 |

由此得出的编码约束：

- **不能用 `xcodebuild`、`.xcodeproj`、Storyboard/XIB、Asset Catalog**，一切通过 `swift build` + `scripts/bundle.sh` 完成。界面全部用代码创建。
- 已用探针包验证，以下框架在 SwiftPM 下可以正常编译运行：AppKit、WebKit、AVFoundation、IOKit.ps、ServiceManagement（`SMAppService`）、EventKit，以及 `host_statistics64`。
- `Package.swift` 的最低系统版本为 `.macOS(.v14)`（`SMAppService` 需要 13，命令行工具自带的 Testing 框架按 14 编译）。
- **单元测试用 swift-testing（`import Testing`），不用 XCTest**（命令行工具不带 XCTest）。SwiftPM 默认找不到命令行工具里的 Testing 框架，**一律通过 `scripts/test.sh` 运行测试**，不要直接运行 `swift test`。可测试的逻辑写成不依赖 AppKit 状态的纯函数，测试里用 `@testable import DesktopShell`。
- **Swift 5 语言模式**：`// swift-tools-version:6.0`，并在 `Package` 上设置 `swiftLanguageModes: [.v5]`（已验证可用）。操作 UI 的类型标注 `@MainActor`，不追求 Swift 6 严格并发。
- 冷编译大约需要 2 分钟，增量编译要快得多。

## 技术探针

在正式任务之前，由 Claude Code 在临时目录里搭一次性的小程序，验证有风险的技术点，结论记在这里。

| 探针 | 结论 |
|---|---|
| 系统音频捕获（process tap + vDSP），2026-10-17 | **可行**，详见下方 |
| 保留访达图标时的点击穿透，2026-10-17 | WKWebView 窗口透明区域**不会**自动穿透（35 次空白点击全被网页接住）；改为"网页上报组件区域 + 全局鼠标监听动态切换 `ignoresMouseEvents`"后，空白点击全部交给访达（0 次被接住），组件点击全部收到，从其他应用直接点组件也能一次生效，拖动框选经过组件不会被打断。全局鼠标监听不需要系统权限，鼠标移动时每秒约 20–45 个事件 |
| 系统提醒事项（EventKit），2026-10-17 | **可行**，详见下方 |
| 键盘焦点，2026-10-18 | 组件窗口**改用不激活应用的面板**，详见下方 |
| 原生毛玻璃（`NSVisualEffectView`），2026-10-18 | **可行**，开销测不出来，详见下方 |
| 播放检测（不开捕获时判断有没有应用在放声音），2026-10-19 | **可行**，不需要权限，详见下方 |
| 开机自启（`SMAppService.mainApp`），2026-10-20 | **可行**。自签名、放在普通目录（不在"应用程序"文件夹）的 `.app` 调用 `register()` 直接成功，`status` 立刻是 `.enabled`，不需要批准；从没注册过时 `status` 是 `.notFound`。`bundle.sh` 那样在同一路径原地替换 `.app` 后仍是 `.enabled`。系统登录项记录（`sfltool dumpbtm`）记的是**注册时正在运行的那份 `.app` 的路径**，从别的副本再注册会改指向那个副本；而 `status` 只按 bundle id 判断，任何副本都显示 `.enabled`，看不出指向哪份。`unregister()` 后记录变为"已停用" |

**系统音频捕获探针**（全局 tap `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`，`muteBehavior = .unmuted`，加上"默认输出设备 + tap"的私有聚合设备，再加 IOProc）：

- 只用命令行工具就能编译；`.app` 用 **ad-hoc 签名**就能拿到"系统录音"权限，`Info.plist` 里要有 `NSAudioCaptureUsageDescription`，必须用 `open` 启动 `.app`（不能直接运行可执行文件）。
- **第一次启动**时弹出权限框，`AudioDeviceCreateIOProcIDWithBlock` 会**阻塞到用户点完为止**（实测 5 秒），所以**捕获初始化不能放在主线程**。同一个签名再次启动不再弹框，0.1 秒内开始捕获。签名一变（例如重新 ad-hoc 签名）可能需要重新授权，所以 M2.5 的固定证书是必需的。
- 格式：48kHz、双声道、Float32、交错存储；每秒约 94 次回调，每次 512 帧。
- 频谱准确：440Hz 和 3000Hz 的单音、60 到 10000Hz 的扫频，峰值频率和频段都对得上。参数用 FFT 4096、hop 2048、Hann 窗、12 个对数频段（20–16500Hz）。
- CPU（i7-9750H）：频谱分析本身约 **0.3%**；捕获期间系统音频服务 `coreaudiod` 大约**多耗 3% 的单核，安静时也是这样**。所以：暂停时必须停止捕获，没有应用在放声音时也不开捕获（做法见下方"播放检测探针"）。
- 释放顺序（`AudioDeviceStop` → `AudioDeviceDestroyIOProcID` → `AudioHardwareDestroyAggregateDevice` → `AudioHardwareDestroyProcessTap`）全部成功，没有残留。

**系统提醒事项探针**（ad-hoc 签名的 `LSUIElement` 小程序，用 `open` 启动，`Info.plist` 写 `NSRemindersFullAccessUsageDescription`）：

- 只用命令行工具就能编译链接 EventKit。第一次调用 `requestFullAccessToReminders` 弹出权限框，**不阻塞主线程**（等用户点按钮的 25 秒里主线程最长停顿 0.05 秒），回调在后台线程。同一签名再次启动直接是 `fullAccess`，不再弹框。
- 用户的数据（2026-10-17）：两个 iCloud 列表，"提醒事项"（系统默认列表，6 条未完成，全部带到期时间）和"提醒"（空）。没有优先级、备注、网址、重复、闹钟。
- 读取所有列表的未完成提醒约 0.01–0.05 秒；读取今天完成的约 0.01–0.24 秒。
- 写入（新建列表、新增、勾选、取消勾选、改标题、设到期时间）都成功，每次 0.02–0.09 秒；Mac 上写入的内容会出现在 iPhone 上。
- `calendarItemIdentifier` 和列表的 `calendarIdentifier` 都是 UUID，符合 Bridge 的 id 规则，重启后不变（5/5 都能重新查到）。
- `EKEventStoreChanged`：自己写入后立刻收到；**其他进程写入后立刻收到**；iPhone 上的改动同步到 Mac 后也会收到，实测约 1 分钟（当时 Mac 的"提醒事项"应用开着）。同步过来时常常连着来 2 次通知，第一次时数据可能还没变，所以收到通知后要稍等一下（防抖）再重新读取。通知的 `userInfo` 没有有用的细节，只能整体重新读取。
- 一次例外：Mac 的"提醒事项"应用关闭时，iPhone 上的一次取消勾选 8 分钟内没有出现在 Mac 上（期间收到过 2 次通知，数据没变），原因没能确定。正式实现时，启动、唤醒和每隔几分钟调用一次 `refreshSourcesIfNecessary()` 请求同步，并在验收时实测 iPhone 改动多久出现在桌面。

**键盘焦点探针**（两轮：在图标层 +1 放几个装着 WKWebView 的小窗口，和"文本编辑"对照）：

- **现在的做法有问题**：组件窗口是普通的无边框 `NSWindow`，不能成为 key window。点一下组件里的按钮，系统就把本应用切到前台，原来的应用失去键盘，接着敲的字哪里都不去。更糟的是，应用被切到前台时，AppKit 会把键盘还给它上次的 key window，网页随之把焦点恢复到上次的输入框，字会打到用户没点的地方。
- **改用 `NSPanel`**（`styleMask` 含 `.borderless` 和 `.nonactivatingPanel`，`hidesOnDeactivate = false`），并且 `canBecomeKey` 只在网页输入框获得焦点期间为 `true`：点按钮、勾选框都**不会**切换前台应用，也不会接管键盘（6 次都没有）。
- 输入框获得焦点时调用 `makeKey()` 和 `makeFirstResponder(webView)`：英文、中文拼音都能正常输入，候选词窗口位置正常，前台应用保持不变。
- 交还键盘：按 Esc 失去焦点时调用 `NSApp.deactivate()`，键盘立刻回到原来的应用。`orderOut` 再 `orderFrontRegardless` 也能交还，但会重新排列窗口，不采用。直接点别的应用的窗口时，系统会自动交还。
- 面板成为 key window 时 `NSApp.isActive` 会变成 `true`，但前台应用其实没变，逻辑里不要依赖 `NSApp.isActive`。
- 网页在页面失去焦点时，要主动让输入框真正失焦（`blur()`），否则应用以后被激活时，WebKit 会把焦点恢复到那个输入框。

**原生毛玻璃探针**（照正式结构：VideoWindow 在图标层 −1 播放视频；WidgetWindow 是图标层 +1 的不激活 `NSPanel`，内容视图里先放一层 `NSVisualEffectView`，上面盖透明的 WKWebView，加载 M3.5 效果图；网页上报底板矩形，原生按矩形摆放毛玻璃）：

- 桌面层窗口里的 `blendingMode = .behindWindow` 能正常取样下面的视频和访达图标。`state = .active`，`appearance = .darkAqua`。
- 每块底板一个 `NSVisualEffectView`。圆角用 `maskImage`：一张可拉伸的圆角图，`capInsets` 等于半径。更新位置时 `CATransaction.setDisableActions(true)`，避免隐式动画。网页在 `requestAnimationFrame` 里读 `getBoundingClientRect` 上报；打开、关闭外观面板时重新上报。
- 用户选定材质 `.hudWindow`，网页底色层不透明度 45%（`--card-fill-opacity`）。
- 耗电（i7-9750H，当时由独显 5300M 驱动屏幕；每种情况采样 20 秒，测两轮；后台开着 Claude、Chrome 等应用，数字只看相对差别）：
  - 毛玻璃开和关，WindowServer CPU 的差别在误差以内（54–64% 对 55–65%），独显占用多 2–4 个百分点。
  - 主要开销在视频本身：只放视频时，WindowServer 比不开多约 20%；全屏透明网页窗口再多 5–10%。
  - 4K 和 1440p 测不出差别：WindowServer 53% 对 52%，解码进程 4.6% 对 4.3%。
  - 律动条用 60 帧/秒的模拟动画时，网页进程约 13%，WindowServer 再多约 10%。正式实现只在收到 `audioSpectrum`（约 23 次/秒）时刷新，静音时停住。

**播放检测探针**（命令行小程序，不开捕获、不需要任何权限；用 `afplay` 和一个反复开关输出的 AVAudioEngine 小程序做对照）：

- 系统对象的 `kAudioHardwarePropertyProcessObjectList`（macOS 14.2 起）列出所有用过音频的进程。每个进程对象能读到 `kAudioProcessPropertyPID` 和 `kAudioProcessPropertyIsRunningOutput`，由此可以知道有没有别的进程在输出声音。音量为 0 的播放也算在输出。
- **要监听 `kAudioProcessPropertyIsRunning`**：进程开始或停止输出时，进程对象发的是 `IsRunning`（`pir?`）和 `kAudioProcessPropertyDevices`（`pdv#`），不发 `IsRunningOutput` 本身，直接监听它一个事件都收不到。收到 `IsRunning` 后再去读 `IsRunningOutput`。事件在输出开关后约 0.05 秒内到达。
- 新进程出现时可能已经在输出了，之后不会再单独发事件（`afplay` 就是这样）。所以进程列表变化时要把全部进程重新读一遍。列表的事件常常连着来两次。
- 默认输出设备的 `kAudioDevicePropertyDeviceIsRunningSomewhere` 也会跟着变，但开着捕获时，聚合设备包含输出设备，这个属性很可能被我们自己占住，所以不用它。
- 本应用自己不放声音（背景视频没有音轨）。点头像的语音由 WebKit 的进程播放，也算"别的进程在放声音"，会触发捕获，这是想要的。

## 窗口要求

- 实测层级（本机）：系统壁纸和程序坞 ≤ -2147483624，**访达图标 = `CGWindowLevelForKey(.desktopIconWindow)`（-2147483603）**，系统桌面小组件 = 图标 +2。
- **VideoWindow**：层级 = 图标层 **−1**；不透明；`ignoresMouseEvents = true`。
- **WidgetWindow**：层级 = 图标层 **+3**（2026-10-18 改定，原来是 +1：用户桌面上有系统小组件，层级 +2，会盖住组件和外观面板。改到 +3 后组件在最上面；系统小组件在没被组件挡住的地方照常显示，点击穿透到它们也正常。和组件重叠的系统小组件由用户自己挪开）；内容视图里先放毛玻璃层（见"设计规范"），上面是 WKWebView；`isOpaque = false`、`backgroundColor = .clear`、无阴影；是**不激活应用的 `NSPanel`**（`styleMask` 含 `.nonactivatingPanel`，`hidesOnDeactivate = false`），点组件不会把本应用切到前台、不会抢走其他应用的键盘（2026-10-18 键盘焦点探针）。**`NSPanel.isFloatingPanel` 的 setter 会顺带改层级**（`false` 改成普通窗口层级 0），所以先设面板属性、最后设 `level`（2026-10-18 发现：M3-08 起组件窗口因此一直在层级 0，点过组件或应用全屏时会盖住其他应用，见 M4-10）。启动日志 `DesktopShell windows: …` 记录实际层级，`swift scripts/window-levels.swift` 可以随时查看。
- 两个窗口的 `collectionBehavior` 都是 `[.canJoinAllSpaces, .stationary, .ignoresCycle]`。
- **点击穿透**（2026-10-17 探针实测，见"技术探针"）：WKWebView 窗口的透明区域**不会**自动让点击穿透，所以要动态切换：
  - 网页通过 bridge 动作 `setHitRegions` 上报所有可交互组件的矩形（CSS 像素，相对网页左上角，组件布局变化时重新上报）。
  - Swift 用 `NSEvent` 的全局和本地监听（鼠标移动、拖动、松开）跟踪光标：光标在某个区域内时 `WidgetWindow.ignoresMouseEvents = false`，否则为 `true`，点击落到访达图标上。不需要任何系统权限。
  - **按住鼠标期间不切换**（`NSEvent.pressedMouseButtons != 0`），松开后再重新判断，避免打断拖动和框选。
- 点在组件之外的空白处：交给访达（选择图标、框选、右键菜单），我们不做任何事。**点击语音改为点击角色卡头像触发**。
- **隐藏桌面文件**（菜单栏勾选项，用来单纯欣赏壁纸）：把 VideoWindow 升到图标层 **+3**（与 WidgetWindow 同层，排在它下面，图标和系统小组件一起被盖住），VideoWindow **始终 `ignoresMouseEvents = true`**；同时关闭点击穿透，让最上面的 WidgetWindow **接住全部点击**，空白处的点击落在网页透明背景上，什么都不发生，不会点到看不见的图标。取消时恢复图标层 −1 并重新打开点击穿透。**不修改访达设置、不重启访达**。选择保存在 `ui.json` 的 `desktopIconsHidden`，重启后保持。（2026-10-17 实测教训：同层窗口被点击时 macOS 会把它提到同层最前面。让 VideoWindow 接收点击会盖住组件；点击后再重排又会闪烁。所以 VideoWindow 永远不接收点击。）网页要禁用右键菜单（`contextmenu` 事件 `preventDefault`），否则空白处右键会弹出 WKWebView 自带的菜单。
- 需要输入文字的组件（待办输入框等）：WidgetWindow 的 `canBecomeKey` 只在网页文本输入框获得焦点期间为 `true`。网页在文本输入框获得焦点时发 `focusInput`，Swift 调用 `makeKey()` 并把网页设为第一响应者（不激活应用）；失去焦点或按 Esc 时发 `blurInput`，Swift 恢复为不能成为 key，如果仍是 key window 就调用 `NSApp.deactivate()`，键盘回到原来的应用。**不调用 `NSApp.activate`。**
- 访达默认从屏幕**右上角**开始往下排列图标（用户桌面上约有 68 个项目），M3.5 设计布局时要给图标留出区域。
- **安全区域**：读取 `NSScreen.visibleFrame`（排除 Dock 和菜单栏后的区域），换算成相对窗口的边距，通过 bridge 推送给网页，在网页里设成 CSS 变量 `--safe-top/right/bottom/left`。所有组件都布局在安全区域内。屏幕参数变化时（`NSApplication.didChangeScreenParametersNotification`）重新计算。（M1-02 已实测：Dock 位置、自动隐藏的变化都会触发这个通知，不需要轮询。计算函数为 `SafeAreaInsets.compute`。）
- 多显示器：每块屏幕一对窗口（VideoWindow + WidgetWindow），屏幕接入或拔出时成对增删。

## 省电要求（Intel Mac）

以下情况下暂停背景视频，并通知网页暂停动画（`store` 里设 `paused = true`）：

- 窗口被完全遮挡（看 **VideoWindow** 的 `NSWindow.occlusionState`；所有屏幕的 VideoWindow 都看不见时才算。窗口刚显示、还没收到第一次遮挡通知之前，按"可见"处理，避免启动时误判暂停。**防抖**：遮挡状态持续 1 秒以上才计入暂停原因，变为可见时立即恢复；用一次性的延迟任务实现，不轮询。2026-10-17 实测：全屏切换桌面、窗口动画时遮挡状态会闪烁，最短 9 毫秒）
- 屏幕睡眠（`NSWorkspace.screensDidSleepNotification`）
- 用户切换走（`NSWorkspace.sessionDidResignActiveNotification`）
- 使用电池且电量低于 20%
- 用户在菜单栏手动暂停

网页里所有持续动画都要检查 `paused` 状态。

AVPlayer 必须设置 `preventsDisplaySleepDuringVideoPlayback = false`，否则视频壁纸会阻止显示器休眠。所有屏幕共用**一个** AVPlayer（每个窗口各自一个 `AVPlayerLayer`），只解码一路视频。

暂停时还要**停止系统音频捕获**（停掉 IOProc，而不是只停止推送），因为它是最耗电的部分。**没有应用在放声音时也不开捕获**（2026-10-19 定）：别的应用开始输出声音时立刻开始捕获，全部停止输出持续 3 秒后再拆掉，切歌的间隙不会反复开关；判断方法见"技术探针"里的播放检测探针。捕获开着、但没有声音时（持续静音超过 2 秒，例如有的应用暂停后输出流还开着）不做频谱分析、不推送 `audioSpectrum`。点击语音由用户主动触发，暂停时照样可以播放。

## Bridge 接口（白名单）

网页通过 `window.webkit.messageHandlers.shell.postMessage({action, ...})` 发消息，Swift 只处理下面这些动作，其余一律拒绝并记录日志。

**通信方式**（M3 定，2026-10-17）：

- 网页 → Swift：Swift 用 `WKScriptMessageHandlerWithReply` 注册，`postMessage` 返回 Promise。每条消息 Swift 都回复且只回复一次：成功时 resolve 为回复值（多数动作是 `null`），失败时 reject，错误的 `message` 是以下错误码之一：`untrusted`（来源不对）、`invalid`（格式不对）、`unknown-action`（不在白名单或尚未实现）、`not-found`（id 在配置或素材里查不到）、`failed`（系统调用失败）。
- 除 `action` 外**只允许下表列出的参数**，多出任何键都算 `invalid`；所有 id 参数必须是只含字母、数字、`_`、`-` 的非空字符串。
- Swift → 网页：用 `callAsyncJavaScript("window.shell?.receive?.(event)", arguments: ["event": …])` 传参，**不拼接 JS 字符串**。事件是平铺的对象，`event` 字段是事件名，例如 `{event: "paused", paused: true}`。
- 每次页面加载完成（含重新加载、新接入的屏幕），Swift 给该页面重推 `safeArea`、`paused`、`uiState`、`systemStats`、`todos` 的最新值。
- 日志只写 action、id、数量和错误码，不写用户内容。

**网页 → Swift**

| action | 参数 | 行为 |
|---|---|---|
| `openProject` | `projectId` | 在 Finder 中打开该项目文件夹 |
| `openProjectWith` | `projectId`, `appId` | 用指定应用打开项目文件夹（例如 Cursor）。应用只要在 `config.apps` 里即可 |
| `launchApp` | `appId` | 启动应用 |
| `getConfig` | — | 回复 `{config, media, uiState}`：`config` 含 `user`（`name`）、`character`（`name`、`motto`）、`greetings`、`projects`（`id`、`name`、`tags`、`apps`、`hasReminders`）、`apps`（`id`、`name`、`iconUrl`），**不含**项目路径、应用 bundle id、提醒事项列表名和背景视频；`media.avatars`、`media.backgrounds`、`media.voices`（`media/voice/` 里的 mp3，2026-10-18 增加，点击语音用）由 Swift 扫描 `media/` 目录生成，每项 `{id, url}`；`apps[].iconUrl` 是 `/media/app-icons/<appId>.png`，应用没装或图标导出失败时为 `null`；`user.name`、`character.motto` 没有配置（或只有空白）时为 `null`；`uiState` 为 `{avatarId, backgroundId, voiceEnabled}`。待办不在这里，见推送事件 `todos` |
| `addTodo` | `text`, `projectId?` | 在系统提醒事项里新增一条，只设标题。放进该项目对应的列表；没有 `projectId`、为 `null`，或者该项目没有配置列表时，放进系统默认列表。`text` 去掉首尾空白后不为空、不超过 500 字。回复新提醒（格式同 `todos` 事件里的一项） |
| `setTodoDone` | `todoId`, `done` | 勾选或取消勾选一条提醒。`todoId` 查不到 → `not-found`。**不提供删除**（删除在 iPhone 或 Mac 的提醒事项里做） |
| `saveUiState` | `avatarId?`, `backgroundId?`（`null` 表示恢复默认） | 写入 `ui.json`，回复新的 `uiState`，并向所有页面推送 `uiState`。Swift 先核对 id 确实存在于 `media/avatars`、`media/backgrounds`，不存在就回复 `not-found` |
| `focusInput` / `blurInput` | — | 网页的文本输入框获得 / 失去焦点时发送。`focusInput`：该窗口允许成为 key window 并 `makeKey()`，不激活应用；`blurInput`：恢复为不能成为 key，如果仍是 key window 就 `NSApp.deactivate()`。做法见"窗口要求"和"技术探针" |
| `setHitRegions` | `regions`：`[[x, y, w, h], …]`，CSS 像素，相对网页左上角 | 整体替换该窗口的可交互区域，用于点击穿透判断。只接受有限数值，最多 64 个，宽高必须为正，超出窗口的部分裁掉；格式不对就整条拒绝并记录日志 |
| `setGlassRegions` | `regions`：`[[x, y, w, h, radius], …]`，CSS 像素，相对网页左上角 | 整体替换该窗口毛玻璃的位置（2026-10-18 增加）。校验同 `setHitRegions`，另外 `radius` 必须在 0 到宽高较小值的一半之间 |

**安全要求**：

- Bridge 只处理来自 `shell://app` **主框架**的消息（校验 `message.frameInfo.isMainFrame`，以及 `securityOrigin` 的 scheme 为 `shell`、host 为 `app`），其他来源一律忽略并记录日志。
- 网页**只传 id，不传路径或 bundle id**。真实路径和应用由 Swift 从 `config.json` 里查。这样即使网页被塞了坏代码，也只能打开配置里列出的东西。不提供任何执行 shell 命令的动作。
- URL 约定（同一个源）：`shell://app/<path>` 对应 `web/<path>`，`shell://app/media/<path>` 对应 `media/<path>`。
- `shell://` URL scheme 处理器**只能读取两个根目录**：应用内的 `web/` 和运行时素材目录 `media/`。路径先标准化，再确认仍在根目录之内；包含 `..`、绝对路径、符号链接指向根目录之外的请求一律返回 404。

**Swift → 网页**（调用 `window.shell.receive(event)`）

| event | 内容 | 频率 |
|---|---|---|
| `safeArea` | `top`、`right`、`bottom`、`left`（CSS 像素） | 启动时和屏幕变化时 |
| `systemStats` | `battery: {level（0–100 或 null）, charging, onBattery}`、`cpu`（0–100）、`memory: {usedBytes, totalBytes, percent}` | 每 5 秒 |
| `paused` | `paused`：true / false | 状态变化时 |
| `uiState` | `avatarId`, `backgroundId`（为空时是 `null`）, `voiceEnabled` | 启动时、菜单栏切换语音开关时、外观保存后 |
| `todos` | `access`（`granted` / `denied` / `notDetermined` / `restricted` / `writeOnly`）、`items: [{id, text, done, projectId, due}]`：所有列表的未完成提醒加上今天完成的；`projectId` 由列表对应的项目得出，没有就是 `null`；`due` 为 `{date: "YYYY-MM-DD", time: "HH:mm" 或 null}` 或 `null` | 启动时、提醒事项有变化时（含 iPhone 同步过来的改动） |
| `audioSpectrum` | `bands`：每侧 12 个 0–1 的数值（左右两侧共用一组，由网页镜像显示） | 有声音时约 23 次/秒（48 kHz 时每 2048 帧一次）；静音、暂停或没有应用在放声音时不推送 |

电量用 IOKit（`IOPSCopyPowerSourcesInfo`），CPU 和内存用 `host_statistics` / `host_statistics64`。

## 配置文件示例

`~/Library/Application Support/DesktopShell/config.json`：

```json
{
  "background": { "video": "video/aemeath.mp4" },
  "user": { "name": "Arvin" },
  "character": { "name": "爱弥斯", "motto": "愿星光一直落在你走的路上" },
  "greetings": [
    { "from": 0,  "title": "深夜了", "wish": "时辰已晚，且捻熄灯盏，良宵安枕" },
    { "from": 6,  "title": "早上好", "wish": "晨光熹微，愿您涤尽尘扰，理裳启新日" },
    { "from": 12, "title": "下午好", "wish": "愿清风伴您今日，时刻皆有阳光满心" },
    { "from": 18, "title": "傍晚了", "wish": "且舒怀抱，自在一刻尽欢愉" },
    { "from": 20, "title": "晚上好", "wish": "且舒怀抱，自在一刻尽欢愉" },
    { "from": 21, "title": "晚上好", "wish": "时辰已晚，且捻熄灯盏，良宵安枕" },
    { "from": 23, "title": "深夜了", "wish": "时辰已晚，且捻熄灯盏，良宵安枕" }
  ],
  "projects": [
    { "id": "desktop-shell", "name": "DesktopShell", "path": "~/projects/desktop-shell", "tags": ["dev"], "remindersList": "DesktopShell" }
  ],
  "apps": [
    { "id": "cursor", "name": "Cursor", "bundleId": "com.todesktop.230313mzl4w4u92" },
    { "id": "safari", "name": "Safari", "bundleId": "com.apple.Safari" }
  ]
}
```

（Cursor 的 bundle id 要在用户机器上确认：`osascript -e 'id of app "Cursor"'`。）

首次启动时如果配置文件不存在，就生成一份示例配置。

- `background.video` 是相对 `media/` 的路径。
- 项目的 `remindersList`（可选）是系统提醒事项里一个列表的名字，按名字精确匹配；找不到时记录日志，当作没有配置。同名列表有多个时取第一个并记录日志。
- `greetings` 按整点 `from` 升序排列，取不大于当前小时的最后一项；问候显示为 `"<title>，<user.name>"`，名字用强调色；没有 `user.name` 时只显示 `title`（2026-10-18 改定，原来是角色名）。默认文案取自美化包 `Skins/Ageo` 的配置。
- `character.motto`（签名）显示在角色卡上名字的右边，可选，没有就不显示。
- 同目录下的其他数据文件：`ui.json`（当前头像、背景图、语音开关、是否隐藏桌面文件）。待办存在系统提醒事项里，不另存文件。`ui.json` 由应用自己管理，缺少的字段用默认值，损坏时记录日志并使用默认值。

### 运行时素材目录

`~/Library/Application Support/DesktopShell/media/`，由 `scripts/prepare-media.sh` 从 `assets/` 里的原始素材生成：

| 子目录 | 内容 | 处理方式 |
|---|---|---|
| `video/` | 背景视频 | ffmpeg 把 webm 转成 HEVC 的 mp4，保持原片的 3840×2160，不缩小 |
| `voice/` | 点击语音（mp3） | 原样复制 |
| `avatars/` | 头像（PNG，"签名 + 圆形头像"的组合图） | 复制 `assets/avatars-2x/` 里的 480×300 版本（2026-10-18 定：显示尺寸 240×150 点，Retina 屏需要 2 倍）。`avatars-2x/` 由 Claude Code 一次性生成，不进 git，做法见 `docs/design/parameters.md`"头像超分" |
| `backgrounds/` | 背景图库 | 长边超过 2400 才缩到 2400，**只缩不放**（`sips -Z` 会放大小图，必须先判断尺寸）；不透明的图转 JPEG（质量 90），带透明的角色立绘保持 PNG |
| `ornaments/` | 心形装饰条等装饰图 | 缩到实际显示尺寸的 2 倍 |
| `fonts/` | 用到的字体文件 | 原样复制，只复制设计定稿里用到的 |
| `app-icons/` | 启动栏的应用图标（128px PNG） | **由 Swift 生成，不归 `prepare-media.sh` 管**（2026-10-18 定）：启动时在后台线程用 `NSWorkspace.icon(forFile:)` 为 `config.apps` 里的每个应用导出 `<appId>.png`，覆盖同名文件，不删除其他文件。实测每个约 50 ms，第一次约 0.8 秒 |

文件名就是 id（去掉扩展名），例如 `avatars/12.png` 的 id 是 `12`。

## 组件清单（第一版）

视觉主题复刻《鸣潮》爱弥斯美化包（作者 Dr_Black），按 Mac 的实际情况调整。第一版共八个组件和两项功能：

1. **时钟**：以大号衬线体的星期和日期为主（Mac 菜单栏已经显示时间）。同时负责计算当前时段，写入 `store.phase`：早晨 6–12 点、白天 12–18 点、傍晚 18–21 点、夜晚 21–6 点。
2. **项目卡片**：列出 `config.projects`。点击卡片会选中它（写入 `store.selectedProject`）；每个项目有"访达"和"用 <应用> 打开"两个按钮（应用取项目 `apps` 里的第一个，例如 Cursor；没有就只有"访达"，M3.5 定）。
3. **应用启动栏**：列出 `config.apps`，点击启动。
4. **待办（系统提醒事项）**（2026-10-17 改定，原方案是自己存 `todos.json`）：直接读写系统"提醒事项"，和 iPhone 同步。显示所有列表的未完成提醒和今天完成的提醒，带到期时间的显示到期时间。可勾选完成、可新增（第一版只填文字，到期时间在 iPhone 上加），**不能删除**。项目通过配置里的 `remindersList` 对应一个列表。没有授权时显示提示，告诉用户去"系统设置 → 隐私与安全性 → 提醒事项"里允许。
5. **系统状态**：电量、CPU、内存，外加一条 CPU 历史折线。
6. **问候语**：按 `config.greetings` 显示当前整点对应的问候和祝福语，称呼（`user.name`）用强调色，没有配置就只显示问候。
7. **角色卡**：圆形头像、名字、签名（签名来自 `config.character.motto`；2026-10-18 去掉了标签）。**点击头像播放语音**；卡片右上角的"外观"按钮（M3.5 定）点击后在**同一个网页里**弹出"外观"面板，可以换头像和背景图，选择结果通过 `saveUiState` 保存。
8. **音频律动**：冰晶心形装饰条，两侧各 12 根柱子跟随 `audioSpectrum` 跳动。

两项功能：

- **点击语音**：点击角色卡的**头像**随机播放 `media/voice/` 里的一句语音（播放期间不重复触发）；菜单栏可以开关。（原方案是点空白处，因保留访达图标而改为点头像）
- **背景图库**：`media/backgrounds/` 里的图片可以作为应用启动栏和卡片的背景，在"外观"面板里切换。

**不做**：Windows 开始菜单、资源管理器、设置页的换皮（Mac 上对应的是系统程序，换皮需要关闭 SIP 注入代码），以及任务栏和 Dock 的换皮。

## 联动规则

这是本项目的重点，组件之间**只通过 store 通信，不直接互相调用**。

| 触发 | 效果 |
|---|---|
| 时钟更新 `phase` | 整个页面切换对应时段的主题变量（`tokens.css` 里用 `[data-phase="night"]` 等选择器覆盖） |
| 选中某个项目卡片 | 待办只显示该项目对应列表里的提醒（再点一次取消选中，显示全部列表）；新增的提醒放进该项目的列表。项目没有配置列表时，待办组件提示"这个项目没有对应的提醒事项列表"，新增的提醒放进默认列表 |
| 选中某个项目卡片 | 启动栏里与该项目相关的应用高亮（项目可以配置 `apps` 字段，没有就不高亮） |
| 时钟每分钟更新 | 问候语组件按当前整点切换问候和祝福语 |
| `systemStats` 显示使用电池且电量低 | 写入 `paused`，背景和所有动画暂停；系统状态组件显示省电提示 |
| `paused` 变化 | 所有组件停止或恢复动画；律动条归零静止；Swift 端停止或恢复系统音频捕获 |
| 外观面板里换头像或背景图 | 通过 `saveUiState` 保存；Swift 推送 `uiState` 写入 `store.ui`，角色卡、启动栏立即生效 |
| 菜单栏切换语音开关 | Swift 推送 `uiState`，写入 `store.ui.voiceEnabled`；关闭时点击头像不再播放语音 |

## 设计规范

- 所有颜色、字体、圆角、阴影、间距、动效时长都定义在 `web/styles/tokens.css` 的 CSS 变量里。**组件 CSS 里不允许出现写死的颜色值或尺寸值。**
- 配色从背景素材里提取。在素材到位之前，先用一套中性的深色占位主题。
- 视觉参考：美化包里对应皮肤的配置（字体、字号、颜色、线宽、文案）。M3.5 开始时由 Claude Code 先整理成参数表，再在此基础上设计。已知的起点：正文白色、强调色 `rgb(250,192,207)`、问候语字体思源宋体。
- 每个组件是一个"卡片"，共用同一个基础卡片样式（`.card`），只在内容上区分。
- **桌面组件交互基线**（写在 `base.css` / 页面入口里，所有组件共用）：图片和装饰元素不能拖动（`-webkit-user-drag: none`、`draggable="false"`）；除输入框外文字不能选中（`user-select: none`）；禁用右键菜单（`contextmenu` 事件 `preventDefault`）；鼠标指针默认是箭头，只有可点击的元素才变化。M2 测试页没有做这些，那只是临时页面。
- **毛玻璃用原生 `NSVisualEffectView`**（2026-10-18 定，探针见"技术探针"）：垫在 WidgetWindow 里 WKWebView 的下面，网页通过 `setGlassRegions` 上报每块底板（`.card`）和打开着的弹层（`[data-glass]`）的矩形与圆角，Swift 按区域摆放，材质 `.hudWindow`。网页底板的底色单独放一层（`.card::before`），不透明度用 `--card-fill-opacity`（有原生毛玻璃时 45%，由 `<html data-glass="on">` 切换）。在普通浏览器里开发时没有原生毛玻璃，底色按 100% 显示。不用 CSS `backdrop-filter`：M2-05 把视频拆到单独的 VideoWindow 后，它只能跨窗口取样，macOS 按应用是否在前台切换渲染方式，透明度会在点击、切换前后台的那一刻跳动，CSS 控制不了。
- 具体的视觉设计（token 数值、卡片样式、组件版式、桌面布局）在 **M3.5 设计定稿**中确定，记录在 `docs/design/`（2026-10-18 定稿：`tokens.css` 是 token 数值，`design.css` 按目标文件分节写好了每个组件的样式，`index.html` 里每个 `data-widget` 区块就是组件要生成的 DOM，说明见 `docs/design/README.md`）。M4 及之后实现组件时以定稿为准，**Codex 不自行做视觉决定**；定稿没有覆盖到的视觉问题，在交付记录里提问。
- 素材只用**图片、视频、音频和字体**。**不执行任何从壁纸包里解出来的代码**（包括 exe/dll/ps1/vbs/bat/ahk/lua 和网页 JS），需要的功能自己重写。皮肤配置文件只当作数据来读，用来提取参数。

### 素材来源

原始素材是用户下载的《鸣潮》爱弥斯美化包（`~/Downloads/鸣潮-爱弥斯美化包.zip`），需要的部分解压到 `assets/`（不进 git，素材版权属于原作者，仅供个人使用，不再分发）。

| 用途 | 包内位置 | 许可 |
|---|---|---|
| 背景视频 | `A_WW_Aemeath/Wallpaper/.../video/Wallpaper.webm` | — |
| 点击语音（54 条） | `A_WW_Aemeath/Wallpaper/.../login/*.mp3` | — |
| 心形装饰条 | `Skins/Aemeath/@Resources/1.png` | — |
| 问候文案、配色、字体 | `Skins/Ageo/@Resources/Language/Language.inc`、`Variables.inc` | 未附许可，仅参考 |
| 头像（30 张） | `Skins/prototype/@Resources/Images/Profile/*.png` | 未附许可，仅个人使用 |
| 律动参数 | `Skins/Lano-VisualizerL/`：FFT 4096、上升 100ms、衰减 60ms、20–16500Hz、灵敏度 18、每侧 12 根 | MIT |
| 背景图库 | `开始菜单背景/`、`A_WW_Aemeath/文件夹背景/` | — |
| 字体 | 各皮肤的 `@Resources/Fonts/` | 按字体各自的许可，仅个人使用 |

**不使用**：`MToolBox`、`OldNewExplorer`、`*.mepack`（Windows 资源管理器和开始菜单的美化工具及其预设），以及所有可执行文件和脚本。

## 建议的目录结构

```
desktop-shell/
├── AGENTS.md                      # 唯一规范来源（本文件）
├── CLAUDE.md                      # 引入本文件 + Claude Code 的角色说明
├── docs/tasks/                    # 任务单，智能体之间的交接载体
│   ├── _TEMPLATE.md
│   └── M1-01-<简述>.md
├── docs/design/                   # M3.5 设计定稿：效果图、token 数值、组件样式（截图含素材，存在 assets/design-screenshots/，不进 git）
├── assets/                        # 用户提供的壁纸素材（视频/图片），不进 git
├── Package.swift
├── Sources/DesktopShell/
│   ├── main.swift
│   ├── AppDelegate.swift          # 菜单栏、生命周期
│   ├── DesktopWindow.swift        # VideoWindow / WidgetWindow：窗口层级、key window 处理
│   ├── HitTesting.swift           # 组件区域解析 + 点击穿透判断（纯函数）
│   ├── HitTestController.swift    # 全局鼠标监听，动态切换 ignoresMouseEvents
│   ├── GlassLayer.swift           # 按网页上报的区域摆放 NSVisualEffectView
│   ├── ScreenManager.swift        # 多屏、安全区域
│   ├── BackgroundPlayer.swift     # 视频背景
│   ├── WebContainer.swift         # WKWebView + URL scheme handler
│   ├── Bridge.swift               # 白名单消息处理（WebKit 部分）
│   ├── BridgeProtocol.swift       # 来源校验、请求解析、回复和推送事件的内容（纯函数）
│   ├── AppState.swift             # 配置、外观状态、待办存储的唯一持有者
│   ├── MediaLibrary.swift         # 扫描 media/ 生成头像、背景、语音列表
│   ├── AppIcons.swift             # 启动时把 config.apps 的图标导出到 media/app-icons/
│   ├── RemindersStore.swift       # EventKit：读写系统提醒事项、监听变化
│   ├── ProjectPath.swift          # 解析项目路径（~、绝对路径）
│   ├── OcclusionDebouncer.swift   # 遮挡防抖
│   ├── SystemStatsMonitor.swift   # 每 5 秒采样并推送 systemStats
│   ├── SystemStats.swift          # 电量/CPU/内存
│   ├── PowerPolicy.swift          # 暂停规则
│   ├── UiStateStore.swift         # 读写 ui.json
│   ├── AudioSpectrum.swift        # 系统音频捕获：tap、聚合设备、IOProc，何时开关（M5.5）
│   ├── SpectrumAnalyzer.swift     # 采样 → 12 个 0–1 柱高（FFT、平滑、分频段；纯计算）
│   ├── PlaybackMonitor.swift      # 监听有没有别的应用在放声音
│   ├── LaunchAtLogin.swift        # 开机自启：SMAppService 状态 → 菜单勾选、点击动作（M6）
│   └── ConfigStore.swift          # 读写 JSON
├── web/
│   ├── index.html
│   ├── styles/tokens.css          # 照 docs/design/tokens.css
│   ├── styles/fonts.css           # 字体文件在 media/fonts/
│   ├── styles/base.css
│   ├── js/store.js
│   ├── js/bridge.js               # 在普通浏览器里自动切换为 mock
│   ├── js/mock.js                 # mock 数据和模拟事件（含 audioSpectrum）
│   ├── js/widgets.js              # 组件注册与挂载
│   ├── js/hit-regions.js          # 自动上报点击区域
│   ├── js/glass-regions.js        # 自动上报毛玻璃区域（底板和弹层）
│   ├── js/scroll-hints.js         # 可滚动列表上下边缘的淡出提示
│   ├── js/media.js                # 按 store.ui 选出头像、背景图的地址（角色卡、启动栏、外观面板共用）
│   ├── js/main.js                 # 页面入口
│   └── widgets/                   # 每个组件一个 <名字>.js，样式在同名 .css（照 docs/design/design.css 对应的一节）
│       ├── clock.js
│       ├── projects.js
│       ├── launcher.js
│       ├── todos.js
│       ├── stats.js
│       ├── greeting.js
│       ├── character.js           # 角色卡
│       ├── appearance.js          # 外观面板（角色卡上的"外观"按钮通过 store 打开）
│       ├── visualizer.js          # 音频律动 + 心形装饰条
│       └── voice.js               # 点击头像播放语音（无界面）
├── Tests/DesktopShellTests/        # swift-testing 单元测试
├── Tests/web/                     # 网页逻辑的 node --test 测试（不打包进 .app）
└── scripts/
    ├── test.sh                    # 带上 Testing 框架路径运行 swift test
    ├── prepare-media.sh           # assets/ → media/：视频转码、图片缩放、复制语音和字体
    ├── bundle.sh                  # 组装 .app、写 Info.plist（LSUIElement、NSAudioCaptureUsageDescription、NSRemindersFullAccessUsageDescription）、签名
    ├── test-web.sh                # 用 node --test 运行 Tests/web/
    ├── serve-web.mjs              # 浏览器开发服务器
    └── setup-signing.md           # 创建自签名证书的步骤说明
```

## 开发方式

- `bridge.js` 检测到不在 WKWebView 里时（没有 `window.webkit.messageHandlers`），自动使用 mock 数据。这样网页部分可以直接在浏览器里开发调试，改样式不需要每次重新编译 Swift。
- **Node.js 只用于开发**（2026-10-17 定）：不进 `.app`，不装 npm 包，不建 `package.json`。`scripts/test-web.sh` 用 Node 自带的 `node --test` 跑 `Tests/web/` 下的网页逻辑测试；`node scripts/serve-web.mjs` 启动浏览器开发服务器（只监听 `127.0.0.1:8765`；`/media/` 映射到运行时素材目录，`/design/` 映射到 `docs/design/`，其余映射到 `web/`；路径安全规则同 `shell://`；支持 Range，Safari 能播放视频和音频）。
- Swift 部分用 `swift build` 编译，`scripts/test.sh` 跑单元测试；M2.5 之前直接运行 `.build/debug/DesktopShell`，M2.5 起用 `scripts/bundle.sh` 打包后运行。
- 打包：`scripts/bundle.sh [--debug] [--adhoc] [--open]`，产物为 `build/DesktopShell.app`（不进 git），bundle id 为 `local.desktopshell.DesktopShell`，签名身份为 `DesktopShell Self-Signed`（由用户按 `scripts/setup-signing.md` 创建）。`.app` 的日志用 `/usr/bin/log stream --style compact --predicate 'subsystem == "local.desktopshell.DesktopShell"'` 查看（**必须写 `/usr/bin/log`**：zsh 有一个同名的内置命令）。
- **日志**：一律用 `Log.notice` / `Log.error`（M2.5-02 起），不用 `NSLog`。`.app` 启动时 NSLog 的内容在统一日志里会被隐藏成 `<private>`；`Log` 用 `os.Logger` 并标记为公开，同时写一行到 stderr。日志里只写路径、状态和错误信息，**不写用户的内容**（例如待办文字）。
- 直接运行 `.build/debug/DesktopShell` 仍然可以用来快速调试，但需要系统权限的功能（M5.5 系统音频）只能用签名后的 `.app` 测试。
- **开机自启只在主仓库的 `build/DesktopShell.app` 里打开**（2026-10-20 定）：系统记住的是点开关时正在运行的那份 `.app` 的路径（见"技术探针"）。审查、调试用的临时构建（worktree、临时目录里的 `.app`）不要去点菜单栏的"开机自启"，否则登录时会去启动那份临时构建，临时目录删掉后就不再自启。注册成功时日志会记下 `login item: registered path=…`，可以据此核对。

## 多智能体协作

### 角色

| 角色 | 负责 | 不负责 |
|---|---|---|
| **用户** | 提需求、最终决定、在两个工具之间转交任务、手动目测 GUI 效果 | — |
| **Claude Code**（规划 + 审查 + 设计） | 拆里程碑为任务单、写验收标准、审查 diff、跑验收命令、合并到 `main`、维护本文件（经用户同意）；M3.5 在 `docs/design/` 出效果图和 token 数值 | 不写业务代码（审查时可修正明显的笔误，需在审查记录里注明） |
| **Codex**（实现） | 按任务单写代码、自测、填写交付记录 | 不改本文件、`CLAUDE.md` 和任务单的需求部分；不自行扩大任务范围 |

### 流程

```
用户 ──提需求──▶ Claude Code：在 docs/tasks/ 写任务单（状态 todo）
                     │
用户 ──"做 M1-01"──▶ Codex：建分支 task/M1-01，实现、自测，填写"交付记录"，状态改为 review
                     │
用户 ──"审 M1-01"──▶ Claude Code：git diff main...task/M1-01，对照验收标准逐条验证
                     ├─ 不通过 → 写"审查记录"，状态改为 changes-requested → 回到 Codex
                     └─ 通过   → 合并到 main，状态改为 done
```

### 任务单

- 位置：`docs/tasks/<任务号>-<简述>.md`，任务号格式为 `M<里程碑>-<两位序号>`，例如 `M1-01-desktop-window.md`。
- 模板：`docs/tasks/_TEMPLATE.md`。
- 状态取值：`todo` / `in-progress` / `review` / `changes-requested` / `done`。
- 每个任务应当能在一个分支里独立完成并验证；太大就拆。

### Codex 工作规则

1. 一次只做一个任务。开始时把状态改为 `in-progress`，从最新的 `main` 建分支 `task/<任务号>`。
2. 只修改任务单"允许修改的文件"里列出的文件。确实需要改其他文件时，停下来在交付记录里说明原因，不要直接改。
3. 规范或任务单有歧义、互相矛盾，或与本文件冲突时，**停下来在交付记录里提问**，不要自己猜。
4. 不修改 `AGENTS.md`、`CLAUDE.md`，也不修改任务单的需求部分（目标、范围、验收标准）；只填写"交付记录"并改状态。
5. 尽量把验收标准里的命令都跑一遍，并把结果写进交付记录。GUI 效果无法自动验证的，写清楚用户需要怎么手动验证。
6. 提交信息格式：`<任务号>: <简述>`，例如 `M1-01: 桌面层窗口与菜单栏退出`。
7. 遵守本文件"不要做的事"一节。

### Claude Code 审查规则

1. 先读任务单和交付记录，再看 `git diff main...task/<任务号>`。
2. 逐条核对验收标准，能执行的命令都要实际执行，不能只看代码就判定通过。
3. 重点检查：是否越出"允许修改的文件"；bridge 白名单和"只传 id"的安全要求；组件 CSS 里有没有写死的颜色或尺寸；是否违反"不要做的事"。
4. 审查结论写进任务单的"审查记录"。通过后合并到 `main`（`git merge --no-ff`），把状态改为 `done`，然后推送 `main`。

### 远端与推送

- 远端 `origin` 是用户的 GitHub 仓库，用来留存备份、方便回退。
- **Claude Code** 每次合并任务后执行 `git push origin main`。
- **Codex** 交付任务（状态改为 `review`）时推送自己的任务分支 `git push -u origin task/<任务号>`；网络不通时在交付记录里注明即可，不影响交付。
- 任何人都**不使用 `--force`**，不改写已经推送过的历史。

## 里程碑

每完成一个里程碑都要能实际运行，并告诉用户如何验证。M1 起，每个里程碑开始前先由 Claude Code 拆成任务单，再交给 Codex 实现。

- **M0 环境检查**：运行 `sw_vers`、`xcode-select -p`、`xcodebuild -version`、`swift --version`、`git --version`、`codex --version`，确认 macOS 版本、Swift 工具链、git 和 Codex CLI 是否可用；初始化 git 仓库。如果缺工具，告诉用户需要安装什么，然后停下等用户处理。
- **M1 外壳**：每块屏幕一个桌面层窗口，显示纯色占位；菜单栏图标可以退出；安全区域正确（用一个半透明框把安全区域画出来验证，确认不会被 Dock 挡住）。
- **M2 背景**：`prepare-media.sh` 生成运行时素材；视频循环播放，WKWebView 透明叠在上面；`shell://` scheme 处理器（含路径安全检查）；省电暂停规则生效。
- **M2.5 打包与签名**（从 M6 提前，因为系统音频权限只能授予签名的 `.app`）：`bundle.sh` 产出可双击运行的 `.app`；`setup-signing.md` 和固定的自签名证书；`Info.plist` 含 `LSUIElement`、`NSAudioCaptureUsageDescription`。此后都用 `.app` 运行。
- **M3 网页骨架**：`tokens.css`、`store.js`、`bridge.js`（含 mock，mock 里包括模拟的 `audioSpectrum`）、组件注册机制、点击区域自动上报、骨架自检面板；在浏览器里能打开。`tokens.css` 只搭好变量结构，填中性深色占位值。Swift 端同时完成 Bridge 的回复通道和来源校验、白名单动作（含键盘焦点 `focusInput` / `blurInput`，组件窗口改为不激活应用的面板）、`safeArea` / `paused` / `uiState` / `systemStats` 推送、遮挡防抖，菜单栏补上"点击语音""重新加载""打开配置文件夹"；接入系统提醒事项（权限、读取、勾选、新增、变化推送 `todos`）。
- **M3.5 设计定稿**（由 Claude Code 负责，不交给 Codex）：先从美化包皮肤配置整理参数表，再从壁纸素材提取配色，确定字体、卡片样式（圆角、阴影、透明度、毛玻璃）、八个组件的版式、外观面板、桌面布局，以及四个时段主题和选中、高亮、省电等状态样式。布局要给访达桌面图标留出区域（访达默认从右上角往下排列，用户桌面上约有 68 个项目），与用户商定图标区和组件区的划分。还要根据定下的显示尺寸，决定原图偏小的立绘（726×660）和头像（240×150）是否需要 AI 超分放大（Real-ESRGAN 动漫模型；需要下载时先征得用户同意）。产出放在 `docs/design/`：一个能在浏览器里直接打开的效果图页面（叠在壁纸上、用 mock 数据），一份定稿的 `tokens.css` 数值，以及截图。用户确认后才进入 M4。
- **M4 组件**：八个组件和两项功能全部完成，**照 M3.5 定稿实现**，样式统一。"联动规则"表里的联动在各组件里一起实现（定稿画出了选中、高亮等状态）。音频律动此时用 mock 数据。
- **M5 联动**（2026-10-18 改定，原来是"实现并逐条验证"）：联动已在 M4 各组件里实现；M5 到桌面上按"联动规则"表逐条验证，发现问题再修补。
- **M5.5 系统音频律动**：`AudioSpectrum.swift` 捕获系统声音、做频谱分析，推送 `audioSpectrum`，接上 M4 的律动组件；暂停和没有应用在放声音时不开捕获，静音时不推送；初始参数采用 Lano-Visualizer 的取值。
- **M6 开机自启**：用 `SMAppService` 实现开机自启（在菜单栏里提供开关）。

## 后续想法

记录用户提出、但**还没有决定要做**的功能。不属于任何里程碑，M6 之后再逐条评估；Codex 不要实现这里的内容。

### 桌面终端（2026-10-17 记录）

在桌面上做一个可以直接输入命令的终端组件。

- **与现有规则的冲突**：违反"不做终端"和"不开放执行 shell 命令的 bridge 动作"两条。做之前必须由用户明确修改这两条规则，并接受安全模型的变化：目前网页只能传 id，即使页面被注入恶意代码也只能打开配置里列出的东西；有了终端，网页就等于能执行任意命令。前提是只加载我们自己的页面（"不加载外部网站"这条必须保留）。
- **已具备的基础**：WidgetWindow 在图标之上并且可以点击（M2-05）；M3-08 实现了"组件窗口临时获得键盘焦点"（不激活应用的面板），终端可以复用；Bridge 是双向通道。
- **还需要做的**：Swift 端用伪终端（PTY）启动用户的 shell，通过 Bridge 双向传递输入输出，窗口尺寸变化时同步行列数；处理快捷键冲突（⌘C/⌘V/⌘W 等）和中文输入法。
- **前端两个方案**：
  - xterm.js 放在同一个网页里，样式直接用 tokens，风格最统一；需要引入一个前端库（单个 JS 文件，不需要构建工具，按规范要先征得用户同意）；中文输入法在网页终端里可能有小问题。
  - SwiftTerm（MIT）原生终端视图叠在网页上，输入法和性能更稳；样式要单独对齐 tokens，"所有组件在一个网页里"的原则会打折扣。
- **工作量估计**：一个探针（验证桌面层窗口里的键盘焦点和输入法体验）加上 2–3 个 Codex 任务。
- **更轻量的替代**（不需要改规则，可以先做）：项目卡片上加"用终端打开"按钮，复用 `openProjectWith`，用"终端"或 iTerm 打开项目目录；或者做"命令按钮"组件，命令写在 `config.json` 里，网页只传命令 id，输出显示在组件里。

### 正在播放的音乐（2026-10-17 记录）

在桌面上显示 Mac "音乐"应用正在播放的歌曲（歌名、歌手、专辑封面），比较自然的位置是和"音频律动"放在一起。

- **可行做法**（只覆盖 Mac 上的"音乐"应用），建议两种结合：
  - 监听系统广播 `com.apple.Music.playerInfo`：播放、暂停、切歌时推送歌名、歌手、专辑、时长和播放状态。不需要权限，不轮询；但只在变化时发，启动时不知道当前在放什么，也没有封面。
  - 用 ScriptingBridge / AppleScript 询问"音乐"应用：当前歌曲、播放进度、封面，还能控制播放、暂停、下一首。第一次需要"自动化"授权（固定签名下只问一次）；"音乐"没在运行时不能去问，否则会把它启动起来。
- **与现有规则的冲突**：要允许 Swift 对"音乐"应用发送 Apple Events（只读取播放信息和控制播放），在"不要做的事"里写明这个例外；`Info.plist` 增加 `NSAppleEventsUsageDescription`。
- **不做**通用的"正在播放"（不管哪个应用在放都能显示）：系统只通过私有框架 MediaRemote 提供，macOS 15.4 起第三方应用被拦截；社区的绕过办法借 `/usr/bin/perl` 加载辅助库，属于钻空子，还要执行外部命令。
- **限制**：iPhone 上在放的、网页版 Apple Music、网易云等看不到。上面两种途径存在多年但没写进苹果正式文档，做之前先在 macOS 26 上做探针确认。
- **工作量估计**：一个探针加一个 Codex 任务，M3.5 需要补上它的版式。

### 天气（2026-10-17 记录）

在桌面上显示所在城市的天气。

- **苹果的 WeatherKit 用不了**：需要加入付费的 Apple 开发者计划，并用开发者账号签名；系统"天气"应用也没有给其他应用读取数据的接口。
- **可行做法**：用免费的第三方天气服务，例如 Open-Meteo（不需要注册和密钥，个人非商业使用免费，数据要求注明来源，CC BY 4.0）。城市或经纬度写在 `config.json` 里，不需要定位权限。由 Swift 定时请求（例如每 30 分钟一次，暂停时不请求），通过 Bridge 推送给网页；网页仍然不加载任何外部网站。断网时显示上一次的结果。
- **与现有规则的变化**：项目目前完全不联网。做之前要用户同意由 Swift 发起网络请求，并接受把城市或坐标发给第三方服务。
- **零代码的替代**：把 macOS 自带的天气小组件直接放到桌面上，但样式和皮肤不统一，而且系统小组件的窗口层级比我们的组件高，会盖在上面。
- **工作量估计**：一个 Codex 任务，M3.5 需要补上它的版式。

## 不要做的事

- 不做终端、不做文件管理器、不做任何删除或移动文件的功能；不删除系统提醒事项。
- 不开放执行 shell 命令的 bridge 动作。
- 不引入前端框架和构建工具，除非组件数量明显增加且用户同意。
- 不修改用户的系统设置。
- 不加载任何外部网站到这个 WKWebView 里。
