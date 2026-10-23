# M8-02: 去掉 launchApp 和应用图标导出，配置里加终端快捷键（Swift）

- **状态**：todo
- **里程碑**：M8
- **依赖**：无。和 M8-01、M8-03、M8-04 互不依赖；M8-05 依赖本任务（用到 `HotKey.swift` 和 `config.terminal`）
- **分支**：task/M8-02

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

- Swift 端去掉只给启动栏用的东西：`launchApp` 动作、启动时导出应用图标、`getConfig` 里的 `apps[].iconUrl`。
- `config.json` 认识新的可选项 `terminal.hotkey`，解析成快捷键的键码、修饰键和显示文字；`getConfig` 和推送的 `config` 带上 `terminal.hotkey` 的显示文字。

本任务**不注册**快捷键（M8-05 做），也不碰终端。

## 背景与约束

- 先读 AGENTS.md：
  - "配置文件示例"里的 `terminal.hotkey`；
  - Bridge 接口里 `getConfig` 的说明（已经去掉了 `iconUrl`，加了 `terminal`）；
  - "技术探针"的终端面板探针：快捷键一段，说明了为什么要可配置。
- 快捷键的写法：`"terminal": { "hotkey": { "key": "`", "modifiers": ["option"] } }`。

### 1. 删除

- `launchApp`：
  - 从 `BridgeRequest`（`BridgeProtocol.swift`）和 `Bridge.swift` 里删掉；
  - 网页再发它，按白名单之外的动作处理，回复 `unknown-action`；
  - 如果 `applicationURL` 之类的辅助函数只有它在用，一并删掉；`openProjectWith` 照旧要用的保留。
- 应用图标：
  - 删掉 `AppIcons.swift`、`AppIconsTests.swift`；
  - 删掉 `AppState` 里的 `exportAppIcons` / `withAppIcons` 和相关队列；
  - 删掉 `AppDelegate` 里的调用；
  - `ConfigReply.makeConfig` / `make` 和 `PageEvent.config` 去掉 `iconIDs` 参数，`apps` 每项只剩 `id`、`name`。
- **不删除**磁盘上已有的 `media/app-icons/` 目录（不做删除文件的功能），日志里也不用提它。

### 2. `terminal.hotkey`

- **配置模型**：`AppConfig` 加可选的 `terminal`，里面是可选的 `hotkey: { key: String, modifiers: [String] }`。
  - 旧的 `config.json` 没有这一项，照常能读；
  - M7 写回 `config.json` 时，用户写的 `terminal` 要原样保留。写一个测试：读进来再写回，`terminal` 还在。
- **新建 `Sources/DesktopShell/HotKey.swift`**，写成纯函数：
  - 把配置解析成 `(keyCode: UInt32, modifiers: UInt32, display: String)`，键码用 Carbon 的 `kVK_*`，修饰键用 `cmdKey` / `optionKey` / `controlKey` / `shiftKey`；
  - 同时告诉调用方是否因为写得不对而用了默认值。
- **`key` 支持的写法**（大小写不敏感，去掉首尾空白）：
  - `a`–`z`、`0`–`9`；
  - `` ` ``、`-`、`=`、`[`、`]`、`;`、`'`、`,`、`.`、`/`、`\`；
  - `space`、`tab`、`return`、`escape`；
  - `f1`–`f12`。
  - 键码按 US 键盘的物理位置（`kVK_ANSI_*`）。
- **`modifiers`**：
  - 取值为 `command`、`option`、`control`、`shift`，至少一个，不能重复，不认识的取值算写错；
  - 只有 `shift` 不行（会和打字冲突），算写错。
- **默认值**：没有 `terminal` 或 `hotkey` 时用 ⌥`，不记日志；写错时也用 ⌥`，并记一行日志，只写"terminal hotkey invalid, using default"，不写原文。
- **显示文字**：修饰键按 ⌃ ⌥ ⇧ ⌘ 的顺序排，后面跟键：
  - 字母大写，例如 `⌘⇧T`；
  - `space` 显示 `Space`、`tab` 显示 `Tab`、`return` 显示 `↩`、`escape` 显示 `⎋`；
  - 功能键显示 `F1`–`F12`；
  - 符号原样，例如 `⌥`` `。
- **`getConfig` 回复和 `config` 推送**：`config` 里加 `"terminal": {"hotkey": <显示文字>}`，总是有值（默认就是 `"⌥`"`）。
- **测试**（`Tests/DesktopShellTests/HotKeyTests.swift`，新建）至少覆盖：
  - 默认值；
  - 每一类键各举一例的键码；
  - 修饰键组合和显示顺序；
  - 写错的几种情况：空 `modifiers`、只有 `shift`、未知修饰键、重复修饰键、未知键、`key` 为空。

## 允许修改的文件

- `Sources/DesktopShell/HotKey.swift`（新建）
- `Sources/DesktopShell/Config.swift`、`Sources/DesktopShell/ConfigStore.swift`、`Sources/DesktopShell/AppState.swift`、`Sources/DesktopShell/AppDelegate.swift`、`Sources/DesktopShell/Bridge.swift`、`Sources/DesktopShell/BridgeProtocol.swift`（修改）
- `Sources/DesktopShell/AppIcons.swift`、`Tests/DesktopShellTests/AppIconsTests.swift`（删除）
- `Tests/DesktopShellTests/HotKeyTests.swift`（新建）
- `Tests/DesktopShellTests/BridgeTests.swift`、`Tests/DesktopShellTests/PageEventTests.swift`、`Tests/DesktopShellTests/ConfigStoreTests.swift`（修改）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不注册快捷键，不建终端面板，不改网页。
- 不删除磁盘上的 `media/app-icons/`。
- 日志不写配置里快捷键的原文。

## 验收标准

**可执行的检查**（实现者自测，审查者复验）：

- [ ] `swift build` 无错误、无警告
- [ ] `scripts/test.sh` 全部通过，其中有 `HotKeyTests`
- [ ] `grep -rn "launchApp\|AppIcons\|iconUrl\|app-icons\|iconIDs" Sources Tests/DesktopShellTests` 没有输出
- [ ] `git diff --name-only main...task/M8-02` 只有上面"允许修改的文件"
- [ ] （审查者复验）打包启动后，用 Web 检查器（`DESKTOPSHELL_DEVTOOLS=1`）或日志确认：
  - `getConfig` 回复里 `config.terminal.hotkey` 是 `"⌥`"`，`apps` 里没有 `iconUrl`；
  - 页面发 `launchApp` 被回复 `unknown-action`。

**用户手动验证**：

- [ ] 打包启动（`scripts/bundle.sh --open`）后桌面一切照旧。启动栏（M8-01 合并前还在）的图标会变成名字的第一个字，属预期；日志里没有新的错误。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由审查者填写（Claude Code，或没参与实现的另一个 Codex 会话） ===== -->

## 审查记录

- **审查者**：
- **结论**：
- **意见**：
