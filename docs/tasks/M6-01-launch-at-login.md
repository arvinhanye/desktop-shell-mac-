# M6-01: 开机自启

- **状态**：done
- **里程碑**：M6
- **依赖**：无（M5.5 已完成）
- **分支**：task/M6-01

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

菜单栏加一个"开机自启"勾选项。勾上以后，登录 Mac 时 DesktopShell 自动启动；取消就不再自动启动。勾选状态始终反映系统里的真实状态，包括用户在"系统设置 → 通用 → 登录项"里改过的情况。

## 背景与约束

- AGENTS.md："里程碑" M6 一行；"技术选型"和"开发环境"（`SMAppService` 在 SwiftPM 下可以编译运行，最低系统 macOS 13，项目是 14）；"不要做的事"（不修改用户的系统设置）。开机自启只在用户自己点了开关时才注册，不算擅自修改设置。
- **Claude Code 的探针**（2026-10-20）：做了一个和本应用同样用 `DesktopShell Self-Signed` 证书签名、`LSUIElement` 的小应用，放在普通目录（不在"应用程序"文件夹）里，调用 `SMAppService.mainApp`：
  - **从没注册过**：`status` 是 `.notFound`，不是 `.notRegistered`。
  - **注册**：`register()` 直接成功，`status` 立刻变成 `.enabled`，没有弹出需要批准的提示（没有出现 `.requiresApproval`）。
  - **原地重新打包**：照 `bundle.sh` 的做法，在同一路径上把旧 `.app` 换成新签的 `.app`，`status` 仍是 `.enabled`。
  - **系统记住的是路径**：系统的登录项记录（`sfltool dumpbtm`）记的是**注册时正在运行的那份 `.app` 的路径**。从另一个位置的副本再调用 `register()`，记录的路径会改成那个副本。
  - **`status` 不能区分副本**：`status` 只按 bundle id 判断。同一 bundle id、不同路径的副本，都会显示 `.enabled`。
  - **取消注册**：`unregister()` 成功，`status` 变成 `.notRegistered`；系统里的记录变成"已停用"。
- **由此得出的约定**：开机自启指向"点开关时正在运行的那份 `.app`"。日常使用的是主仓库的 `build/DesktopShell.app`（`bundle.sh` 原地替换，路径不变）。审查用的临时构建不要去点这个开关。为了事后能查，注册成功时在日志里记下当前 `.app` 的路径。

### 1. 状态和动作（新建 `Sources/DesktopShell/LaunchAtLogin.swift`）

把"系统状态 → 菜单显示"和"点击 → 做什么"写成纯函数，方便测试：

```swift
enum LoginItemStatus { case enabled, requiresApproval, notRegistered, notFound, unknown }

enum LaunchAtLogin {
    /// 菜单勾选：enabled → .on；requiresApproval → .mixed；其余 → .off
    static func menuState(_ status: LoginItemStatus) -> NSControl.StateValue
    enum Action: Equatable { case register, unregister, openSettings }
    /// 点击：enabled → unregister；requiresApproval → openSettings；其余 → register
    static func action(for status: LoginItemStatus) -> Action
}
```

- 再写一个很薄的包装，读 `SMAppService.mainApp.status` 并转换成 `LoginItemStatus`，负责调用 `register()`、`unregister()`、`SMAppService.openSystemSettingsLoginItems()`。这部分不写单元测试。
- `.requiresApproval` 本机探针没有出现，以防万一还是处理：点击时打开系统设置的"登录项"页面，让用户自己批准。我们不替用户改设置。

### 2. 菜单（`AppDelegate.swift`）

- 在"点击语音"下面加一项"开机自启"。
- 每次打开菜单时重新读一次状态，更新勾选（例如设成 `NSMenuDelegate` 的 `menuNeedsUpdate(_:)`）。这样用户在系统设置里改过，菜单也是对的。不轮询。
- 点击后按 `LaunchAtLogin.action(for:)` 执行，然后重新读状态、更新勾选。失败时不弹窗，勾选显示系统的真实状态。
- 不把这个开关存进 `ui.json`。系统的状态就是唯一来源。
- 日志（`Log.notice` / `Log.error`）：
  - 启动时记一次：`DesktopShell login item: status=<enabled|requiresApproval|notRegistered|notFound|unknown>`。
  - 注册成功：`DesktopShell login item: registered path=<当前 .app 的路径>`。
  - 取消成功：`DesktopShell login item: unregistered`。
  - 打开系统设置：`DesktopShell login item: opened settings`。
  - 失败：`DesktopShell login item: register failed error=<domain>/<code>`（取消失败同理）。

### 3. 测试（新建 `Tests/DesktopShellTests/LaunchAtLoginTests.swift`）

- `menuState`：5 种状态各自对应的勾选状态。
- `action(for:)`：5 种状态各自对应的动作。

## 允许修改的文件

- `Sources/DesktopShell/LaunchAtLogin.swift`（新建）
- `Sources/DesktopShell/AppDelegate.swift`（修改）
- `Tests/DesktopShellTests/LaunchAtLoginTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不在启动时自动注册。只有用户点开关才注册或取消。
- 不用已经废弃的 `SMLoginItemSetEnabled`、`LSSharedFileList`，也不写 LaunchAgent plist。
- 不改 `bundle.sh`、`Info.plist` 的内容，也不加安装脚本。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build` 无错误、无警告
- [ ] `scripts/test.sh` 全部通过，包括第 3 节的测试
- [ ] `scripts/bundle.sh` 成功
- [ ] `git diff --name-only main...task/M6-01` 只有上面"允许修改的文件"

**用户手动验证**（用户操作，Claude Code 对照日志和系统记录）：

- [ ] 用主仓库的 `build/DesktopShell.app` 启动 → 日志有一行 `login item: status=…`；菜单里"开机自启"没有勾
- [ ] 点"开机自启" → 勾上；日志 `login item: registered path=…/build/DesktopShell.app`；"系统设置 → 通用 → 登录项"里出现 DesktopShell（可能还会弹一条"已添加后台项目"的系统通知）
- [ ] 注销再登录（或重启 Mac）→ DesktopShell 自动启动，桌面组件、视频、菜单都正常
- [ ] 在"系统设置 → 登录项"里把 DesktopShell 关掉或移除，再打开菜单 → "开机自启"的勾自动消失
- [ ] 再点一次勾上，然后点一次取消 → 日志 `login item: unregistered`；系统设置里不再启用
- [ ] 最后按用户自己的意愿留在开或关

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**（2026-10-20）：
  - 基于最新 `main` / `origin/main` 的 `4d29526ef1ca6cc6c815d0035a17d83058ce5e51`，在 `task/M6-01` 实现；仅涉及本任务允许的 4 个文件。
  - `LaunchAtLogin.swift`：五种状态对应菜单勾选和点击动作的纯函数；`LoginItemService` 薄封装读取 `SMAppService.mainApp.status`、注册、取消注册和打开登录项设置。未来未知系统枚举值映射为 `unknown`。
  - 菜单在“点击语音”下面增加“开机自启”；启动查询并记录一次状态，每次 `menuNeedsUpdate` 重新查询。点击时再次查询并选择动作，动作结束后（包括失败）重读系统状态，而非直接翻转勾选。
  - 启动不注册，不轮询，不写 `ui.json`。成功日志按任务格式记录，注册路径来自 `Bundle.main.bundleURL.path`；失败仅记录操作名与 NSError domain/code，不弹窗。
  - 新增 10 项严格断言测试，覆盖 5 种状态分别对应的菜单状态与点击动作。没有改动已有测试、打包脚本、配置、Bridge 或网页。
- **自测结果**：
  - **PASS 基线**：实现前 `scripts/test.sh`，215/215，24 suites。日志 `/tmp/desktop-shell-m6-01-baseline.log`。
  - **预期 RED**：先新增测试再运行 `scripts/test.sh --filter LaunchAtLoginTests`，因缺少 `LaunchAtLogin` 实现而编译失败；未调整断言。日志 `/tmp/desktop-shell-m6-01-red.log`。
  - **PASS GREEN**：实现后同一聚焦命令，10/10，1 suite。日志 `/tmp/desktop-shell-m6-01-green.log`。
  - **PASS 全量 Swift**：`scripts/test.sh`，225/225，25 suites。日志 `/tmp/desktop-shell-m6-01-full.log`。
  - **PASS 构建**：`swift build`，退出 0，无错误、无警告。日志 `/tmp/desktop-shell-m6-01-build.log`。
  - **PASS release 打包**：`scripts/bundle.sh`，退出 0；Info.plist 校验及固定证书签名校验通过。日志 `/tmp/desktop-shell-m6-01-bundle.log`。
  - **PASS 最终产物复验**：`codesign --verify --strict --verbose=2 build/DesktopShell.app`、`codesign -d -r- build/DesktopShell.app`、`plutil -lint build/DesktopShell.app/Contents/Info.plist`。产物为主仓库 `/Users/arvinhan/Desktop/desktop-shell/build/DesktopShell.app`，指定要求仍为 `identifier "local.desktopshell.DesktopShell" and certificate leaf = H"7d0b2eb51dec80fa75cdbd1d01ace77cee1c62ce"`。
  - **PASS 范围检查**：`git diff --check` 通过；已跟踪差异与新文件合计正好 4 个允许路径；`AGENTS.md`、`CLAUDE.md`、`scripts/bundle.sh` 及任务需求/正式审查区均保持不变。
  - **PASS 独立复核**：子代理只读核对任务、全部新增文件、菜单调用链与本机 SDK 声明，未发现明确 P1/P2/P3 问题。另在临时目录独立编译纯映射 harness，10/10 断言通过；未调用 ServiceManagement 变更 API。该复核不替代 Claude 正式审查或实机验收。
  - **SKIP 手动验收**：本次未启动应用、未注册或取消登录项、未注销/重启 Mac。上方 6 项用户验收均留待用户操作；只使用主仓库的 `build/DesktopShell.app`，对照日志、系统登录项记录和实际重新登录结果。薄系统包装按任务要求不做单元测试，真实系统调用成功/失败路径留作实机验证。网页未改动，本任务未重复运行 web 测试。
- **疑问 / 偏离**：
  - 实现无范围或行为偏离。验收口径补充：本机 SDK 说明，在系统设置撤销允许时可能返回 `requiresApproval`，此时按第 1 节显示 `.mixed`（横杠，非 `.on` 勾选），点击打开登录项设置；只有 `notRegistered`、`notFound`、`unknown` 显示 `.off`。不把所有“系统设置关闭”情况强行显示为 `.off`。
  - 用户已明确允许推送 `task/M6-01`；交付仅提交/推送该任务分支，`main` 留给 Claude 正式审查后合并。真实登录项最终保持开启或关闭，由用户自己选择。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：通过（2026-10-20，Claude Code），合并到 `main`。M6 完成。"注销再登录后自动启动"当时不方便验证，经用户同意先合并；**2026-10-21 已确认**（见下面补充）。
- **可执行的检查**（在 `3416939` 的临时检出里实际运行）：
  - `swift build`：0 个警告。
  - `scripts/test.sh`：225/225 通过。
  - 改动范围：只有允许的 4 个文件。
  - 打包：Codex 在主仓库打的 `build/DesktopShell.app`，签名指定要求不变。
- **代码核对**：
  - 两个纯函数和任务单的对应表一致，测试覆盖 5 种状态。
  - 菜单每次打开都重新读系统状态；点击前也重新读一次，不按旧的勾选操作。失败只记日志。
  - 启动时不注册，不写 `ui.json`。注册成功时记下 `.app` 路径。
- **桌面验证**：
  - 运行的是主仓库的 `build/DesktopShell.app`（01:52 重启到新构建）。
  - 用户操作，Claude Code 对照日志和 `sfltool dumpbtm`：

    | 验收项 | 证据 | 结果 |
    |---|---|---|
    | 启动时记录状态，菜单没勾 | 01:52:28 `login item: status=notFound` | 通过 |
    | 勾上 | 01:53:32 `registered path=/Users/arvinhan/Desktop/desktop-shell/build/DesktopShell.app`；系统记录指向同一路径，`enabled, allowed`；用户在"系统设置 → 登录项"里看到 DesktopShell | 通过 |
    | 在系统设置里关掉 → 菜单的勾消失 | 用户在系统设置里关掉后点菜单，01:57:41 记录的是 `registered`：点击时读到的是"未注册"，菜单显示未勾（如果是需要批准，会记 `opened settings`） | 通过 |
    | 取消 | 01:55:43、01:56:17 `unregistered` | 通过 |
    | 注销再登录后自动启动 | 2026-10-21 重启两次后，DesktopShell 都在登录后自动启动：01:56 重启 → 01:56:59 启动（pid 603）；06:23 重启 → 06:23:33 启动（pid 630），之后日志 `login item: status=enabled` | 通过（2026-10-21 补） |
    | 最后的状态 | 用户留在"开"，系统记录 `enabled`，指向主仓库那份 | — |

  - 下次登录时这样确认：登录后不手动打开 DesktopShell，看它是否自己启动。用 `/usr/bin/log show --last 10m --predicate 'subsystem == "local.desktopshell.DesktopShell"'` 查看，应该有登录后不久的 `login item: status=enabled` 和 `windows: …` 启动日志。如果没有自动启动，另开修复任务。
- **意见**：无。
