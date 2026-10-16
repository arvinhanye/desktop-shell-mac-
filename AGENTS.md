# DesktopShell：个人 Mac 换皮桌面

> 本文件是项目的**唯一规范来源**，Codex 和 Claude Code 都以它为准。
> Codex 自动读取本文件；Claude Code 通过 `CLAUDE.md` 里的 `@AGENTS.md` 引入。
> 本文件只由用户或 Claude Code（经用户同意）修改，Codex 不修改。

## 项目背景

为自己的 Intel Mac 做一个覆盖整个桌面的"换皮桌面"应用。仅供个人使用，不上架、不分发。

需求在前期讨论中已经定下来，**以下决定不需要重新讨论**：

- **覆盖整个桌面**，Dock 和菜单栏保留系统原生。
- **隐藏 Finder 桌面图标**，由用户手动执行一次，应用本身不修改系统设置：
  ```bash
  defaults write com.apple.finder CreateDesktop -bool false && killall Finder
  # 恢复：把 false 改成 true
  ```
- **不做终端**。
- **不做文件管理器**，文件操作一律交给 Finder 或指定应用。
- **所有组件风格高度统一、可以互相联动**，这是核心需求。

用户不一定装了完整的 Xcode。开发由多个 AI 智能体分工完成，见下文"多智能体协作"。

## 核心架构

```
每块屏幕一个 DesktopWindow（无边框，覆盖整屏）
  ├─ 底层：AVPlayerLayer 循环播放背景视频（硬件解码，省电）
  └─ 上层：透明背景的 WKWebView，所有组件都在这一个网页里
        ├─ tokens.css：唯一的设计规范（配色/字体/圆角/阴影/动效）
        ├─ store.js：唯一的共享状态，组件之间通过它联动
        └─ bridge.js：与 Swift 通信的唯一入口
菜单栏 NSStatusItem：暂停动画 / 重新加载 / 打开配置文件夹 / 退出
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
| 签名证书 | 目前没有代码签名证书，M6 之前按 `scripts/setup-signing.md` 创建 |

由此得出的编码约束：

- **不能用 `xcodebuild`、`.xcodeproj`、Storyboard/XIB、Asset Catalog**，一切通过 `swift build` + `scripts/bundle.sh` 完成。界面全部用代码创建。
- 已用探针包验证，以下框架在 SwiftPM 下可以正常编译运行：AppKit、WebKit、AVFoundation、IOKit.ps、ServiceManagement（`SMAppService`），以及 `host_statistics64`。
- `Package.swift` 的最低系统版本为 `.macOS(.v14)`（`SMAppService` 需要 13，命令行工具自带的 Testing 框架按 14 编译）。
- **单元测试用 swift-testing（`import Testing`），不用 XCTest**（命令行工具不带 XCTest）。SwiftPM 默认找不到命令行工具里的 Testing 框架，**一律通过 `scripts/test.sh` 运行测试**，不要直接运行 `swift test`。可测试的逻辑写成不依赖 AppKit 状态的纯函数，测试里用 `@testable import DesktopShell`。
- **Swift 5 语言模式**：`// swift-tools-version:6.0`，并在 `Package` 上设置 `swiftLanguageModes: [.v5]`（已验证可用）。操作 UI 的类型标注 `@MainActor`，不追求 Swift 6 严格并发。
- 冷编译大约需要 2 分钟，增量编译要快得多。

## 窗口要求

- 层级：`CGWindowLevelForKey(.desktopIconWindow) + 1`，即在桌面图标层之上、普通窗口之下。
- `collectionBehavior`：`[.canJoinAllSpaces, .stationary, .ignoresCycle]`。
- 窗口接收鼠标点击。点在组件之外的空白处什么都不发生。
- 需要输入文字的组件（待办输入框等）：窗口子类重写 `canBecomeKey` 返回 `true`。点击输入框时让窗口临时成为 key window，失去焦点后归还。
- **安全区域**：读取 `NSScreen.visibleFrame`（排除 Dock 和菜单栏后的区域），换算成相对窗口的边距，通过 bridge 推送给网页，在网页里设成 CSS 变量 `--safe-top/right/bottom/left`。所有组件都布局在安全区域内。屏幕参数变化时（`NSApplication.didChangeScreenParametersNotification`）重新计算。（M1-02 已实测：Dock 位置、自动隐藏的变化都会触发这个通知，不需要轮询。计算函数为 `SafeAreaInsets.compute`。）
- 多显示器：每块屏幕一个窗口，屏幕接入或拔出时增删窗口。

## 省电要求（Intel Mac）

以下情况下暂停背景视频，并通知网页暂停动画（`store` 里设 `paused = true`）：

- 窗口被完全遮挡（`NSWindow.occlusionState`）
- 屏幕睡眠（`NSWorkspace.screensDidSleepNotification`）
- 用户切换走（`NSWorkspace.sessionDidResignActiveNotification`）
- 使用电池且电量低于 20%
- 用户在菜单栏手动暂停

网页里所有持续动画都要检查 `paused` 状态。

## Bridge 接口（白名单）

网页通过 `window.webkit.messageHandlers.shell.postMessage({action, ...})` 发消息，Swift 只处理下面这些动作，其余一律忽略并记录日志。

**网页 → Swift**

| action | 参数 | 行为 |
|---|---|---|
| `openProject` | `projectId` | 在 Finder 中打开该项目文件夹 |
| `openProjectWith` | `projectId`, `appId` | 用指定应用打开项目文件夹（例如 Cursor） |
| `launchApp` | `appId` | 启动应用 |
| `getConfig` | — | 返回配置 |
| `saveTodos` | `todos` | 写入 `todos.json` |
| `focusInput` / `blurInput` | — | 让窗口获得或交还键盘焦点 |

**安全要求**：网页**只传 id，不传路径或 bundle id**。真实路径和应用由 Swift 从 `config.json` 里查。这样即使网页被塞了坏代码，也只能打开配置里列出的东西。不提供任何执行 shell 命令的动作。

**Swift → 网页**（调用 `window.shell.receive(event)`）

| event | 内容 | 频率 |
|---|---|---|
| `safeArea` | 四个方向的边距 | 启动时和屏幕变化时 |
| `systemStats` | 电量、是否充电、CPU 占用、内存占用 | 每 5 秒 |
| `paused` | true / false | 状态变化时 |

电量用 IOKit（`IOPSCopyPowerSourcesInfo`），CPU 和内存用 `host_statistics` / `host_statistics64`。

## 配置文件示例

`~/Library/Application Support/DesktopShell/config.json`：

```json
{
  "background": { "video": "bg.mp4" },
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

## 组件清单（第一版）

用户让我们按推荐来，第一版做这五个组件：

1. **时钟**：时间、日期、星期。同时负责计算当前时段（早晨 / 白天 / 傍晚 / 夜晚），写入 `store.phase`。
2. **项目卡片**：列出 `config.projects`。点击卡片会选中它（写入 `store.selectedProject`）；卡片上有"Finder 打开"和"用 Cursor 打开"两个按钮。
3. **应用启动栏**：列出 `config.apps`，点击启动。
4. **待办**：可勾选、可新增、可删除。每条待办可以关联一个项目（`projectId`），也可以不关联。数据通过 `saveTodos` 持久化。
5. **系统状态**：电量、CPU、内存。

## 联动规则

这是本项目的重点，组件之间**只通过 store 通信，不直接互相调用**。

| 触发 | 效果 |
|---|---|
| 时钟更新 `phase` | 整个页面切换对应时段的主题变量（`tokens.css` 里用 `[data-phase="night"]` 等选择器覆盖） |
| 选中某个项目卡片 | 待办只显示该项目的待办（再点一次取消选中，显示全部）；新增的待办自动关联该项目 |
| 选中某个项目卡片 | 启动栏里与该项目相关的应用高亮（项目可以配置 `apps` 字段，没有就不高亮） |
| `systemStats` 显示使用电池且电量低 | 写入 `paused`，背景和所有动画暂停；系统状态组件显示省电提示 |
| `paused` 变化 | 所有组件停止或恢复动画 |

## 设计规范

- 所有颜色、字体、圆角、阴影、间距、动效时长都定义在 `web/styles/tokens.css` 的 CSS 变量里。**组件 CSS 里不允许出现写死的颜色值或尺寸值。**
- 配色从背景素材里提取（用户会提供从 Wallpaper Engine 解包的视频或图片）。在素材到位之前，先用一套中性的深色占位主题。
- 每个组件是一个"卡片"，共用同一个基础卡片样式（`.card`），只在内容上区分。
- 具体的视觉设计（token 数值、卡片样式、组件版式、桌面布局）在 **M3.5 设计定稿**中确定，记录在 `docs/design/`。M4 及之后实现组件时以定稿为准，**Codex 不自行做视觉决定**；定稿没有覆盖到的视觉问题，在交付记录里提问。
- 素材只用图片和视频。**不执行任何从壁纸包里解出来的脚本代码。**

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
│   ├── DesktopWindow.swift        # 窗口层级、key window 处理
│   ├── ScreenManager.swift        # 多屏、安全区域
│   ├── BackgroundPlayer.swift     # 视频背景
│   ├── WebContainer.swift         # WKWebView + URL scheme handler
│   ├── Bridge.swift               # 白名单消息处理
│   ├── SystemStats.swift          # 电量/CPU/内存
│   ├── PowerPolicy.swift          # 暂停规则
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
│       └── stats.js
├── Tests/DesktopShellTests/        # swift-testing 单元测试
└── scripts/
    ├── test.sh                    # 带上 Testing 框架路径运行 swift test
    ├── bundle.sh                  # 组装 .app、写 Info.plist（LSUIElement=true）、签名
    └── setup-signing.md           # 创建自签名证书的步骤说明
```

## 开发方式

- `bridge.js` 检测到不在 WKWebView 里时（没有 `window.webkit.messageHandlers`），自动使用 mock 数据。这样网页部分可以直接在浏览器里开发调试，改样式不需要每次重新编译 Swift。
- Swift 部分用 `swift build` 编译，`scripts/test.sh` 跑单元测试；M6 之前直接运行 `.build/debug/DesktopShell`，M6 起用 `scripts/bundle.sh` 打包后运行。

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
- **M2 背景**：视频循环播放，WKWebView 透明叠在上面；省电暂停规则生效。**开始前用户提供壁纸素材**（放到 `assets/`），M3.5 的配色也从这份素材里提取。
- **M3 网页骨架**：`tokens.css`、`store.js`、`bridge.js`（含 mock）、组件注册机制；在浏览器里能打开。`tokens.css` 只搭好变量结构，填中性深色占位值。
- **M3.5 设计定稿**（由 Claude Code 负责，不交给 Codex）：从壁纸素材提取配色，确定字体、卡片样式（圆角、阴影、透明度、毛玻璃）、五个组件的版式、桌面布局，以及四个时段主题和选中、高亮、省电等状态样式。产出放在 `docs/design/`：一个能在浏览器里直接打开的效果图页面（叠在壁纸上、用 mock 数据），一份定稿的 `tokens.css` 数值，以及截图。用户确认后才进入 M4。
- **M4 组件**：五个组件全部完成，**照 M3.5 定稿实现**，样式统一。
- **M5 联动**：按"联动规则"表实现并逐条验证。
- **M6 打包**：`bundle.sh` 产出可双击运行的 `.app`；固定签名；用 `SMAppService` 实现开机自启（在菜单栏里提供开关）。

## 不要做的事

- 不做终端、不做文件管理器、不做任何删除或移动文件的功能。
- 不开放执行 shell 命令的 bridge 动作。
- 不引入前端框架和构建工具，除非组件数量明显增加且用户同意。
- 不修改用户的系统设置（包括隐藏桌面图标，那一步由用户手动执行）。
- 不加载任何外部网站到这个 WKWebView 里。
