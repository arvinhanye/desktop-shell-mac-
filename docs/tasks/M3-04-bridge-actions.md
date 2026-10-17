# M3-04: Bridge 动作——打开项目、启动应用、保存外观

- **状态**：todo
- **里程碑**：M3
- **依赖**：M3-03（必须已合并到 `main`）
- **分支**：task/M3-04

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

白名单里有实际作用的四个动作可用：在 Finder 里打开项目、用指定应用打开项目、启动应用、保存外观（待办改为系统提醒事项，`addTodo`、`setTodoDone` 在 M3-07 实现）。网页只传 id，真实路径和应用由 Swift 从 `config.json` 查；任何不合规的请求都被拒绝并回复错误码。在 `.app` 里用自检面板的按钮就能看到效果。

## 背景与约束

- 先读 `AGENTS.md`："Bridge 接口（白名单）"和"安全要求"（**只传 id，不传路径或 bundle id**；不提供执行 shell 命令的动作）、"不要做的事"。
- 沿用 M3-03 的规则：先校验来源；除 `action` 外只允许下表列出的参数，多出任何键 → `invalid`；每条消息只回复一次；日志只写 action、id、数量和错误码，**不写用户内容**。
- 所有 id 参数先检查类型（必须是字符串）和 `isValidID`，不通过 → `invalid`；格式合法但在配置或素材里查不到 → `not-found`。

### 1. 动作

| action | 参数 | 校验 | 行为 | 成功回复 |
|---|---|---|---|---|
| `openProject` | `projectId` | 项目存在；路径能解析且是已存在的目录，否则 `not-found` | `NSWorkspace.shared.open(目录)`；返回 `false` → `failed` | `nil` |
| `openProjectWith` | `projectId`、`appId` | 项目同上；应用在 `config.apps` 里，且 `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` 能找到，否则 `not-found`。**不要求**应用出现在该项目的 `apps` 里（那个字段只用来高亮） | `NSWorkspace.shared.open([目录], withApplicationAt:, configuration:)`；完成回调里有错误 → `failed` | `nil`（等完成回调之后再回复） |
| `launchApp` | `appId` | 同上 | `NSWorkspace.shared.openApplication(at:, configuration:)`，`activates = true`；有错误 → `failed` | `nil`（等完成回调之后再回复） |
| `saveUiState` | `avatarId`、`backgroundId`（都可选） | 见第 4 节 | 更新 `AppState.uiState` 并保存 | 新的 `{avatarId, backgroundId, voiceEnabled}`（为空的写 `null`，不省略） |

- 每次成功记录一行，例如 `DesktopShell bridge: openProject desktop-shell ok`、`DesktopShell bridge: saveUiState avatarId=12 backgroundId=nil ok`。
- `NSWorkspace` 的完成回调不一定在主线程，回到主线程再回复。

### 2. 项目路径解析（纯函数）

```swift
enum ProjectPath {
    static func resolve(_ path: String, home: URL) -> URL?
}
```

- `"~"` → `home`；`"~/x/y"` → `home/x/y`；以 `/` 开头的绝对路径原样使用；其他（相对路径、`"~user/x"`、空字符串）→ `nil`。
- 结果做 `standardizedFileURL`。是否存在、是否目录由调用方检查（`FileManager.fileExists(atPath:isDirectory:)`）。

### 3. `saveUiState` 的规则（纯函数）

```swift
enum UiPatch: Equatable { case unchanged, clear, set(String) }
enum UiStateUpdate {
    static func apply(to state: UiState, avatar: UiPatch, background: UiPatch,
                      avatars: [MediaItem], backgrounds: [MediaItem]) -> Result<UiState, BridgeError>
}
```

- 参数缺失 → `unchanged`；值为 `NSNull` → `clear`（恢复默认，即 `nil`）；字符串 → `set`；其他类型或者不满足 `isValidID` → `invalid`。两个参数都缺失 → `invalid`。
- `set` 的 id 必须在当前扫描到的 `media/avatars`、`media/backgrounds` 列表里（用 M3-03 的 `MediaLibrary.scan`），否则 `not-found`。
- 只改 `avatarId`、`backgroundId`，`voiceEnabled` 和 `desktopIconsHidden` 保持不变。
- 保存 `ui.json` 失败 → 内存里的状态**恢复到修改前**，回复 `failed`（保证内存和文件一致）。
- M3-05 会在保存成功后把 `uiState` 推送给所有页面，本任务只回复。

### 4. 测试

- 在 `BridgeTests.swift` 里补充：四个动作的 `parse`（合法；缺参数；参数类型错；id 非法，例如 `"../etc"`、`""`、`"a b"`；多出参数，例如 `openProject` 带 `path`）。
- `ProjectPathTests.swift`：上面列出的各种路径形式。
- `UiStateUpdate.apply`：只改头像；只改背景；清除；两个都缺失；不存在的 id；非法 id；其他字段保持不变。

## 允许修改的文件

- `Sources/DesktopShell/Bridge.swift`（修改：执行动作）
- `Sources/DesktopShell/BridgeProtocol.swift`（修改：解析新动作）
- `Sources/DesktopShell/AppState.swift`（修改：外观更新）
- `Sources/DesktopShell/ProjectPath.swift`（新建）
- `Tests/DesktopShellTests/BridgeTests.swift`（修改）、`ProjectPathTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。不执行 shell 命令（不用 `Process`、`NSAppleScript`、`osascript`），不接受网页传来的路径、bundle id 或 URL。
- 不实现 `addTodo`、`setTodoDone`（M3-07）和 `focusInput`、`blurInput`（仍回复 `unknown-action`）。不引入 EventKit。
- 不修改 `web/` 下的任何文件，不修改 `HitTesting`、`HitTestController`、`PowerMonitor`。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过，包含上面列出的新测试；`scripts/test-web.sh` 仍然全部通过
- [ ] `git diff --name-only main...task/M3-04` 只包含"允许修改的文件"
- [ ] `grep -rnE "Process\(|NSTask|NSAppleScript|osascript|/bin/sh|/bin/zsh" Sources/` 没有输出
- [ ] `grep -rnE "removeItem|moveItem|trashItem" Sources/` 没有输出
- [ ] `.app` 里点完下面"用户手动验证"的按钮后，日志里能看到对应的 `ok` 行：
  ```bash
  /usr/bin/log show --last 5m --style compact --predicate 'subsystem == "local.desktopshell.DesktopShell"' | grep "DesktopShell bridge"
  ```

**用户手动验证**（`scripts/bundle.sh --open`，用自检面板）：

- [ ] 项目一行的"Finder"：访达打开该项目文件夹
- [ ] "用 Cursor 打开"：Cursor 打开该项目文件夹
- [ ] "启动 Safari"：Safari 启动或切到前台
- [ ] "随机头像"：面板上的头像立刻换掉；`ui.json` 里 `avatarId` 变了，`desktopIconsHidden`、`voiceEnabled` 没变。"随机背景"同理
- [ ] "恢复默认外观"：`ui.json` 里没有 `avatarId`、`backgroundId`（或为 `null`），面板不再显示头像
- [ ] "发送非法请求"：第 1–5 条和第 7 条 ✓；第 6 条（`setTodoDone`）显示 `unknown-action`（预期，M3-07 实现）
- [ ] 把 `config.json` 里项目的 `path` 改成一个不存在的目录，菜单栏退出后重新打开应用，再点"Finder"：结果栏显示 `not-found`，没有打开任何东西（验证后改回来）

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
