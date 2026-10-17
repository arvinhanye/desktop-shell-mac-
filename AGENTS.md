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
  ├─ 上层 WidgetWindow（图标之上）：透明背景的 WKWebView，所有组件都在这一个网页里
  │     ├─ tokens.css：唯一的设计规范（配色/字体/圆角/阴影/动效）
  │     ├─ store.js：唯一的共享状态，组件之间通过它联动
  │     └─ bridge.js：与 Swift 通信的唯一入口
  │     鼠标在组件区域内才接收点击，其余区域点击穿透给访达（动态切换 ignoresMouseEvents）
  ├─ 中间：访达的桌面图标（系统的，不归我们管）
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
| 背景 | AVPlayer + AVPlayerLooper | 视频型壁纸转成 H.264/HEVC，1080p 或 1440p |
| 系统音频 | Core Audio process tap（macOS 14.2+）+ Accelerate（vDSP FFT） | 只需要"系统录音"权限，不需要屏幕录制权限；必须是打包签名的 `.app`，`Info.plist` 写 `NSAudioCaptureUsageDescription`。可行性见下文"技术探针" |
| 素材处理 | ffmpeg（视频转码）+ `sips`（图片缩放） | 由 `scripts/prepare-media.sh` 统一完成 |
| 沙盒 | 关闭 App Sandbox | 自用 |
| 签名 | 固定的自签名代码签名证书 | 避免每次编译后系统权限失效或反复弹窗 |
| 数据存储 | `~/Library/Application Support/DesktopShell/` 下的 JSON 文件 | Swift 负责读写 |

## 开发环境（M0 已确认，2026-10-16）

| 项目 | 结果 |
|---|---|
| 机器 | Intel Core i7-9750H，`x86_64` |
| 系统 | macOS 26.6.2 |
| 工具链 | 只有 Command Line Tools（`/Library/Developer/CommandLineTools`），**没有完整 Xcode** |
| Swift | 6.3.3，SDK 包含 MacOSX26.sdk |
| git / Codex CLI | git 2.50.1，codex-cli 0.154.0 |
| Cursor bundle id | `com.todesktop.230313mzl4w4u92`（已确认） |
| 签名证书 | 目前没有代码签名证书，M2.5 按 `scripts/setup-signing.md` 创建 |

由此得出的编码约束：

- **不能用 `xcodebuild`、`.xcodeproj`、Storyboard/XIB、Asset Catalog**，一切通过 `swift build` + `scripts/bundle.sh` 完成。界面全部用代码创建。
- 已用探针包验证，以下框架在 SwiftPM 下可以正常编译运行：AppKit、WebKit、AVFoundation、IOKit.ps、ServiceManagement（`SMAppService`），以及 `host_statistics64`。
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

**系统音频捕获探针**（全局 tap `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`，`muteBehavior = .unmuted`，加上"默认输出设备 + tap"的私有聚合设备，再加 IOProc）：

- 只用命令行工具就能编译；`.app` 用 **ad-hoc 签名**就能拿到"系统录音"权限，`Info.plist` 里要有 `NSAudioCaptureUsageDescription`，必须用 `open` 启动 `.app`（不能直接运行可执行文件）。
- **第一次启动**时弹出权限框，`AudioDeviceCreateIOProcIDWithBlock` 会**阻塞到用户点完为止**（实测 5 秒），所以**捕获初始化不能放在主线程**。同一个签名再次启动不再弹框，0.1 秒内开始捕获。签名一变（例如重新 ad-hoc 签名）可能需要重新授权，所以 M2.5 的固定证书是必需的。
- 格式：48kHz、双声道、Float32、交错存储；每秒约 94 次回调，每次 512 帧。
- 频谱准确：440Hz 和 3000Hz 的单音、60 到 10000Hz 的扫频，峰值频率和频段都对得上。参数用 FFT 4096、hop 2048、Hann 窗、12 个对数频段（20–16500Hz）。
- CPU（i7-9750H）：频谱分析本身约 **0.3%**；捕获期间系统音频服务 `coreaudiod` 大约**多耗 3% 的单核，安静时也是这样**。所以：暂停时必须停止捕获；建议 M5.5 再验证一下，能否监听输出设备的 `kAudioDevicePropertyDeviceIsRunningSomewhere`，只在有应用在放声音时才开启捕获。
- 释放顺序（`AudioDeviceStop` → `AudioDeviceDestroyIOProcID` → `AudioHardwareDestroyAggregateDevice` → `AudioHardwareDestroyProcessTap`）全部成功，没有残留。

## 窗口要求

- 实测层级（本机）：系统壁纸和程序坞 ≤ -2147483624，**访达图标 = `CGWindowLevelForKey(.desktopIconWindow)`（-2147483603）**，系统桌面小组件 = 图标 +2。
- **VideoWindow**：层级 = 图标层 **−1**；不透明；`ignoresMouseEvents = true`。
- **WidgetWindow**：层级 = 图标层 **+1**；`isOpaque = false`、`backgroundColor = .clear`、无阴影。
- 两个窗口的 `collectionBehavior` 都是 `[.canJoinAllSpaces, .stationary, .ignoresCycle]`。
- **点击穿透**（2026-10-17 探针实测，见"技术探针"）：WKWebView 窗口的透明区域**不会**自动让点击穿透，所以要动态切换：
  - 网页通过 bridge 动作 `setHitRegions` 上报所有可交互组件的矩形（CSS 像素，相对网页左上角，组件布局变化时重新上报）。
  - Swift 用 `NSEvent` 的全局和本地监听（鼠标移动、拖动、松开）跟踪光标：光标在某个区域内时 `WidgetWindow.ignoresMouseEvents = false`，否则为 `true`，点击落到访达图标上。不需要任何系统权限。
  - **按住鼠标期间不切换**（`NSEvent.pressedMouseButtons != 0`），松开后再重新判断，避免打断拖动和框选。
- 点在组件之外的空白处：交给访达（选择图标、框选、右键菜单），我们不做任何事。**点击语音改为点击角色卡头像触发**。
- **隐藏桌面文件**（菜单栏勾选项，用来单纯欣赏壁纸）：把 VideoWindow 升到图标层 **+1**（与 WidgetWindow 同层，但排在它下面），并设 `ignoresMouseEvents = false`，空白处的点击被视频窗口接住，不会点到看不见的图标；取消时恢复图标层 −1 和 `ignoresMouseEvents = true`。**不修改访达设置、不重启访达**。选择保存在 `ui.json` 的 `desktopIconsHidden`，重启后保持。
- 需要输入文字的组件（待办输入框等）：WidgetWindow 子类重写 `canBecomeKey` 返回 `true`。点击输入框时让窗口临时成为 key window，失去焦点后归还。
- 访达默认从屏幕**右上角**开始往下排列图标（用户桌面上约有 68 个项目），M3.5 设计布局时要给图标留出区域。
- **安全区域**：读取 `NSScreen.visibleFrame`（排除 Dock 和菜单栏后的区域），换算成相对窗口的边距，通过 bridge 推送给网页，在网页里设成 CSS 变量 `--safe-top/right/bottom/left`。所有组件都布局在安全区域内。屏幕参数变化时（`NSApplication.didChangeScreenParametersNotification`）重新计算。（M1-02 已实测：Dock 位置、自动隐藏的变化都会触发这个通知，不需要轮询。计算函数为 `SafeAreaInsets.compute`。）
- 多显示器：每块屏幕一对窗口（VideoWindow + WidgetWindow），屏幕接入或拔出时成对增删。

## 省电要求（Intel Mac）

以下情况下暂停背景视频，并通知网页暂停动画（`store` 里设 `paused = true`）：

- 窗口被完全遮挡（看 **VideoWindow** 的 `NSWindow.occlusionState`；所有屏幕的 VideoWindow 都看不见时才算。窗口刚显示、还没收到第一次遮挡通知之前，按"可见"处理，避免启动时误判暂停）
- 屏幕睡眠（`NSWorkspace.screensDidSleepNotification`）
- 用户切换走（`NSWorkspace.sessionDidResignActiveNotification`）
- 使用电池且电量低于 20%
- 用户在菜单栏手动暂停

网页里所有持续动画都要检查 `paused` 状态。

AVPlayer 必须设置 `preventsDisplaySleepDuringVideoPlayback = false`，否则视频壁纸会阻止显示器休眠。所有屏幕共用**一个** AVPlayer（每个窗口各自一个 `AVPlayerLayer`），只解码一路视频。

暂停时还要**停止系统音频捕获**（停掉 IOProc，而不是只停止推送），因为它是最耗电的部分。没有声音时（持续静音超过 2 秒）不做频谱分析、不推送 `audioSpectrum`。点击语音由用户主动触发，暂停时照样可以播放。

## Bridge 接口（白名单）

网页通过 `window.webkit.messageHandlers.shell.postMessage({action, ...})` 发消息，Swift 只处理下面这些动作，其余一律忽略并记录日志。

**网页 → Swift**

| action | 参数 | 行为 |
|---|---|---|
| `openProject` | `projectId` | 在 Finder 中打开该项目文件夹 |
| `openProjectWith` | `projectId`, `appId` | 用指定应用打开项目文件夹（例如 Cursor） |
| `launchApp` | `appId` | 启动应用 |
| `getConfig` | — | 返回配置，另附 `media.avatars`、`media.backgrounds` 两个 id 列表（Swift 扫描 `media/` 目录生成）和当前 `uiState` |
| `saveTodos` | `todos` | 写入 `todos.json` |
| `saveUiState` | `avatarId?`, `backgroundId?` | 写入 `ui.json`。Swift 先核对 id 确实存在于 `media/avatars`、`media/backgrounds`，不存在就忽略并记录日志 |
| `focusInput` / `blurInput` | — | 让窗口获得或交还键盘焦点 |
| `setHitRegions` | `regions`：`[[x, y, w, h], …]`，CSS 像素，相对网页左上角 | 整体替换该窗口的可交互区域，用于点击穿透判断。只接受有限数值，最多 64 个，宽高必须为正，超出窗口的部分裁掉；格式不对就整条忽略并记录日志 |

**安全要求**：

- 网页**只传 id，不传路径或 bundle id**。真实路径和应用由 Swift 从 `config.json` 里查。这样即使网页被塞了坏代码，也只能打开配置里列出的东西。不提供任何执行 shell 命令的动作。
- URL 约定（同一个源）：`shell://app/<path>` 对应 `web/<path>`，`shell://app/media/<path>` 对应 `media/<path>`。
- `shell://` URL scheme 处理器**只能读取两个根目录**：应用内的 `web/` 和运行时素材目录 `media/`。路径先标准化，再确认仍在根目录之内；包含 `..`、绝对路径、符号链接指向根目录之外的请求一律返回 404。

**Swift → 网页**（调用 `window.shell.receive(event)`）

| event | 内容 | 频率 |
|---|---|---|
| `safeArea` | 四个方向的边距 | 启动时和屏幕变化时 |
| `systemStats` | 电量、是否充电、CPU 占用、内存占用 | 每 5 秒 |
| `paused` | true / false | 状态变化时 |
| `uiState` | `avatarId`, `backgroundId`, `voiceEnabled` | 启动时，以及菜单栏切换语音开关时 |
| `audioSpectrum` | `bands`：每侧 12 个 0–1 的数值（左右两侧共用一组，由网页镜像显示） | 有声音时约 30 次/秒；静音或暂停时不推送 |

电量用 IOKit（`IOPSCopyPowerSourcesInfo`），CPU 和内存用 `host_statistics` / `host_statistics64`。

## 配置文件示例

`~/Library/Application Support/DesktopShell/config.json`：

```json
{
  "background": { "video": "video/aemeath.mp4" },
  "character": { "name": "爱弥斯" },
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
    { "id": "desktop-shell", "name": "DesktopShell", "path": "~/projects/desktop-shell", "tags": ["dev"] }
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
- `greetings` 按整点 `from` 升序排列，取不大于当前小时的最后一项；问候显示为 `"<title>，<character.name>"`，角色名用强调色。默认文案取自美化包 `Skins/Ageo` 的配置。
- 同目录下的其他数据文件：`todos.json`（待办）、`ui.json`（当前头像、背景图、语音开关、是否隐藏桌面文件）。`ui.json` 由应用自己管理，缺少的字段用默认值，损坏时记录日志并使用默认值。

### 运行时素材目录

`~/Library/Application Support/DesktopShell/media/`，由 `scripts/prepare-media.sh` 从 `assets/` 里的原始素材生成：

| 子目录 | 内容 | 处理方式 |
|---|---|---|
| `video/` | 背景视频 | ffmpeg 把 webm 转成 H.264 或 HEVC 的 mp4 |
| `voice/` | 点击语音（mp3） | 原样复制 |
| `avatars/` | 头像（PNG） | 缩到 256px 以内 |
| `backgrounds/` | 背景图库 | 长边超过 2400 才缩到 2400，**只缩不放**（`sips -Z` 会放大小图，必须先判断尺寸）；不透明的图转 JPEG（质量 90），带透明的角色立绘保持 PNG |
| `ornaments/` | 心形装饰条等装饰图 | 缩到实际显示尺寸的 2 倍 |
| `fonts/` | 用到的字体文件 | 原样复制，只复制设计定稿里用到的 |

文件名就是 id（去掉扩展名），例如 `avatars/12.png` 的 id 是 `12`。

## 组件清单（第一版）

视觉主题复刻《鸣潮》爱弥斯美化包（作者 Dr_Black），按 Mac 的实际情况调整。第一版共八个组件和两项功能：

1. **时钟**：以大号衬线体的星期和日期为主（Mac 菜单栏已经显示时间）。同时负责计算当前时段，写入 `store.phase`：早晨 6–12 点、白天 12–18 点、傍晚 18–21 点、夜晚 21–6 点。
2. **项目卡片**：列出 `config.projects`。点击卡片会选中它（写入 `store.selectedProject`）；卡片上有"Finder 打开"和"用 Cursor 打开"两个按钮。
3. **应用启动栏**：列出 `config.apps`，点击启动。
4. **待办**：可勾选、可新增、可删除。每条待办可以关联一个项目（`projectId`），也可以不关联。数据通过 `saveTodos` 持久化。
5. **系统状态**：电量、CPU、内存，外加一条 CPU 历史折线。
6. **问候语**：按 `config.greetings` 显示当前整点对应的问候和祝福语，角色名用强调色。
7. **角色卡**：圆形头像、签名、标签。**点击头像播放语音**；卡片上另设一个入口（具体形式在 M3.5 定，例如签名区域或一个小按钮），点击后在**同一个网页里**弹出"外观"面板，可以换头像和背景图，选择结果通过 `saveUiState` 保存。
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
| 选中某个项目卡片 | 待办只显示该项目的待办（再点一次取消选中，显示全部）；新增的待办自动关联该项目 |
| 选中某个项目卡片 | 启动栏里与该项目相关的应用高亮（项目可以配置 `apps` 字段，没有就不高亮） |
| 时钟每分钟更新 | 问候语组件按当前整点切换问候和祝福语 |
| `systemStats` 显示使用电池且电量低 | 写入 `paused`，背景和所有动画暂停；系统状态组件显示省电提示 |
| `paused` 变化 | 所有组件停止或恢复动画；律动条归零静止；Swift 端停止或恢复系统音频捕获 |
| 外观面板里换头像或背景图 | 写入 `store.ui`，角色卡、启动栏、卡片立即生效，并通过 `saveUiState` 保存 |
| 菜单栏切换语音开关 | Swift 推送 `uiState`，写入 `store.ui.voiceEnabled`；关闭时点击头像不再播放语音 |

## 设计规范

- 所有颜色、字体、圆角、阴影、间距、动效时长都定义在 `web/styles/tokens.css` 的 CSS 变量里。**组件 CSS 里不允许出现写死的颜色值或尺寸值。**
- 配色从背景素材里提取。在素材到位之前，先用一套中性的深色占位主题。
- 视觉参考：美化包里对应皮肤的配置（字体、字号、颜色、线宽、文案）。M3.5 开始时由 Claude Code 先整理成参数表，再在此基础上设计。已知的起点：正文白色、强调色 `rgb(250,192,207)`、问候语字体思源宋体。
- 每个组件是一个"卡片"，共用同一个基础卡片样式（`.card`），只在内容上区分。
- 具体的视觉设计（token 数值、卡片样式、组件版式、桌面布局）在 **M3.5 设计定稿**中确定，记录在 `docs/design/`。M4 及之后实现组件时以定稿为准，**Codex 不自行做视觉决定**；定稿没有覆盖到的视觉问题，在交付记录里提问。
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
├── docs/design/                   # M3.5 设计定稿：效果图、token 数值、截图
├── assets/                        # 用户提供的壁纸素材（视频/图片），不进 git
├── Package.swift
├── Sources/DesktopShell/
│   ├── main.swift
│   ├── AppDelegate.swift          # 菜单栏、生命周期
│   ├── DesktopWindow.swift        # VideoWindow / WidgetWindow：窗口层级、key window 处理
│   ├── HitTesting.swift           # 组件区域解析 + 点击穿透判断（纯函数）
│   ├── HitTestController.swift    # 全局鼠标监听，动态切换 ignoresMouseEvents
│   ├── ScreenManager.swift        # 多屏、安全区域
│   ├── BackgroundPlayer.swift     # 视频背景
│   ├── WebContainer.swift         # WKWebView + URL scheme handler
│   ├── Bridge.swift               # 白名单消息处理
│   ├── SystemStats.swift          # 电量/CPU/内存
│   ├── PowerPolicy.swift          # 暂停规则
│   ├── UiStateStore.swift         # 读写 ui.json
│   ├── AudioSpectrum.swift        # 系统音频捕获 + FFT（M5.5）
│   └── ConfigStore.swift          # 读写 JSON
├── web/
│   ├── index.html
│   ├── styles/tokens.css
│   ├── styles/base.css
│   ├── js/store.js
│   ├── js/bridge.js               # 在普通浏览器里自动切换为 mock
│   └── widgets/
│       ├── clock.js
│       ├── projects.js
│       ├── launcher.js
│       ├── todos.js
│       ├── stats.js
│       ├── greeting.js
│       ├── character.js           # 角色卡 + 外观面板
│       ├── visualizer.js          # 音频律动 + 心形装饰条
│       └── voice.js               # 点击头像播放语音（无界面）
├── Tests/DesktopShellTests/        # swift-testing 单元测试
└── scripts/
    ├── test.sh                    # 带上 Testing 框架路径运行 swift test
    ├── prepare-media.sh           # assets/ → media/：视频转码、图片缩放、复制语音和字体
    ├── bundle.sh                  # 组装 .app、写 Info.plist（LSUIElement、NSAudioCaptureUsageDescription）、签名
    └── setup-signing.md           # 创建自签名证书的步骤说明
```

## 开发方式

- `bridge.js` 检测到不在 WKWebView 里时（没有 `window.webkit.messageHandlers`），自动使用 mock 数据。这样网页部分可以直接在浏览器里开发调试，改样式不需要每次重新编译 Swift。
- Swift 部分用 `swift build` 编译，`scripts/test.sh` 跑单元测试；M2.5 之前直接运行 `.build/debug/DesktopShell`，M2.5 起用 `scripts/bundle.sh` 打包后运行。
- 打包：`scripts/bundle.sh [--debug] [--adhoc] [--open]`，产物为 `build/DesktopShell.app`（不进 git），bundle id 为 `local.desktopshell.DesktopShell`，签名身份为 `DesktopShell Self-Signed`（由用户按 `scripts/setup-signing.md` 创建）。`.app` 的日志用 `log stream --style compact --predicate 'process == "DesktopShell"'` 查看。
- 直接运行 `.build/debug/DesktopShell` 仍然可以用来快速调试，但需要系统权限的功能（M5.5 系统音频）只能用签名后的 `.app` 测试。

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
- **M3 网页骨架**：`tokens.css`、`store.js`、`bridge.js`（含 mock，mock 里包括模拟的 `audioSpectrum`）、组件注册机制；在浏览器里能打开。`tokens.css` 只搭好变量结构，填中性深色占位值。
- **M3.5 设计定稿**（由 Claude Code 负责，不交给 Codex）：先从美化包皮肤配置整理参数表，再从壁纸素材提取配色，确定字体、卡片样式（圆角、阴影、透明度、毛玻璃）、八个组件的版式、外观面板、桌面布局，以及四个时段主题和选中、高亮、省电等状态样式。布局要给访达桌面图标留出区域（访达默认从右上角往下排列，用户桌面上约有 68 个项目），与用户商定图标区和组件区的划分。还要根据定下的显示尺寸，决定原图偏小的立绘（726×660）和头像（240×150）是否需要 AI 超分放大（Real-ESRGAN 动漫模型；需要下载时先征得用户同意）。产出放在 `docs/design/`：一个能在浏览器里直接打开的效果图页面（叠在壁纸上、用 mock 数据），一份定稿的 `tokens.css` 数值，以及截图。用户确认后才进入 M4。
- **M4 组件**：八个组件和两项功能全部完成，**照 M3.5 定稿实现**，样式统一。音频律动此时用 mock 数据。
- **M5 联动**：按"联动规则"表实现并逐条验证。
- **M5.5 系统音频律动**：`AudioSpectrum.swift` 捕获系统声音、做频谱分析，推送 `audioSpectrum`，接上 M4 的律动组件；暂停和静音时停止；初始参数采用 Lano-Visualizer 的取值。
- **M6 开机自启**：用 `SMAppService` 实现开机自启（在菜单栏里提供开关）。

## 不要做的事

- 不做终端、不做文件管理器、不做任何删除或移动文件的功能。
- 不开放执行 shell 命令的 bridge 动作。
- 不引入前端框架和构建工具，除非组件数量明显增加且用户同意。
- 不修改用户的系统设置。
- 不加载任何外部网站到这个 WKWebView 里。
