# M9-02: 去掉 launchApp、openProjectWith、apps 和应用图标导出，配置里加终端快捷键（Swift）

- **状态**：review
- **里程碑**：M9
- **依赖**：M9-01（网页先不再需要 `config.apps`，否则本任务停发 `apps` 后网页会把配置当成格式不对丢掉）。和 M9-03、M9-04 互不依赖；M9-05 依赖本任务（用到 `HotKey.swift` 和 `config.terminal`）
- **分支**：task/M9-02

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

- Swift 端去掉只给启动栏用的东西：`launchApp` 动作、启动时导出应用图标、`getConfig` 里的 `apps[].iconUrl`。
- 去掉项目的"用应用打开"（2026-10-23 用户定）：`openProjectWith` 动作、`updateProject` 的 `appId`、`getProjectEditOptions` 的 `project.appId`、`getConfig` 里的 `apps` 和项目的 `apps`，新项目也不再写 `apps`。
- `config.json` 认识新的可选项 `terminal.hotkey`，解析成快捷键的键码、修饰键和显示文字；`getConfig` 和推送的 `config` 带上 `terminal.hotkey` 的显示文字。

本任务**不注册**快捷键（M9-05 做），也不碰终端。

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
  - `ConfigReply.makeConfig` / `make` 和 `PageEvent.config` 去掉 `iconIDs` 参数（`apps` 整个去掉，见下一条）。
- **不删除**磁盘上已有的 `media/app-icons/` 目录（不做删除文件的功能），日志里也不用提它。
- `openProjectWith` 和 `apps`（照 AGENTS.md 里标着 M9 的部分）：
  - 从 `BridgeRequest` 和 `Bridge.swift` 删掉 `openProjectWith`，网页再发它回复 `unknown-action`；只有它用的查应用 URL 的辅助函数一并删掉；
  - `updateProject` 带 `appId` 算 `invalid`；`AppState.updateProject`、`ProjectPreferences.updating` 去掉应用相关的参数和逻辑；
  - `getProjectEditOptions` 的回复去掉 `project.appId`（`AppState` 和 `RemindersStore` 里组装回复的地方都要改）；
  - `ConfigReply` 的 `config` 不再有 `apps`，项目不再有 `apps`；
  - `ProjectEditing.newProject` 不再写 `apps`；
  - `AppConfig` 去掉顶层 `apps` 和 `Project.apps`，`Config.example` 也去掉；`ConfigStore.filtered` 里过滤应用的部分删掉；
  - 旧的 `config.json` 里还有 `apps` 时照常能读。改写 `config.json`（M7 / M8 的按字段合并）时，文件里的 `apps` 和项目的 `apps` 原样保留。写一个测试：带 `apps` 的旧文件改名一个项目后，两处 `apps` 都还在。

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
- `Sources/DesktopShell/ProjectPreferences.swift`、`Sources/DesktopShell/ProjectEditing.swift`、`Sources/DesktopShell/RemindersStore.swift`（修改，只限去掉应用相关的部分）
- `Sources/DesktopShell/AppIcons.swift`、`Tests/DesktopShellTests/AppIconsTests.swift`（删除）
- `Tests/DesktopShellTests/HotKeyTests.swift`（新建）
- `Tests/DesktopShellTests/BridgeTests.swift`、`Tests/DesktopShellTests/PageEventTests.swift`、`Tests/DesktopShellTests/ConfigStoreTests.swift`、`Tests/DesktopShellTests/ProjectPreferencesTests.swift`、`Tests/DesktopShellTests/ProjectEditingTests.swift`（修改）
- 其他因为上面的删除而编译不过的现有测试文件（只改受影响的部分，在交付记录里逐个列出）
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
- [ ] `grep -rn "launchApp\|AppIcons\|iconUrl\|app-icons\|iconIDs\|openProjectWith\|appId\|bundleId" Sources Tests/DesktopShellTests` 没有输出
- [ ] `git diff --name-only main...task/M9-02` 只有上面"允许修改的文件"
- [ ] （审查者复验）打包启动后，用 Web 检查器（`DESKTOPSHELL_DEVTOOLS=1`）或日志确认：
  - `getConfig` 回复里 `config.terminal.hotkey` 是 `"⌥`"`，没有 `apps`，项目里也没有 `apps`；
  - 页面发 `launchApp`、`openProjectWith` 被回复 `unknown-action`。

**用户手动验证**：

- [ ] 打包启动（`scripts/bundle.sh --open`）后桌面一切照旧（M9-01 已合并，没有启动栏）；项目"访达"能打开；编辑项目改名后，`config.json` 里原有的 `apps` 还在；日志里没有新的错误。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：删除应用打开动作、应用图标导出及配置投影中的应用字段；项目编辑仅保留名称和提醒绑定。新增纯函数 `HotKey.resolve`，支持规定的 US 物理键、Carbon 修饰键及默认回退；公开配置和推送始终包含快捷键文字。无效快捷键（包括字段类型错误）只回退快捷键并记录固定日志，旧项目配置仍正常加载。
- **自测结果**：`scripts/test.sh` 303/303（30 suites）通过；`swift build` 通过且无警告；规定的旧符号 grep 无输出，`git diff --check` 通过。回归覆盖旧顶层 / 项目 `apps`、完整 `terminal`（含未知字段）在项目改名后原样保留，公开字段、旧动作拒绝、快捷键键码及错误回退。日志：`build/m9-validation/M9-02/`。除明确列出的测试外，仅因删除参数修改 `FileDropTrackingTests.swift` 的项目构造参数、`TodoItemsTests.swift` 的项目更新调用。独立子代理对该分支的最终自查未发现可操作缺陷（只算实现者自查，不替代正式审查）。未启动打包应用；真实桌面 / Finder / 项目改名验收及审查者 Web 检查器复验仍待完成。
- **疑问 / 偏离**：从最新远端主线 `5cc84ec` 建分支，本地 main 在另一工作树中未移动。快捷键显示采用正文明确规定的 ⌃ ⌥ ⇧ ⌘ 顺序，例中的 `⌘⇧T` 按该顺序显示为 `⇧⌘T`，不影响实际键码。旧协议字符串在回归测试中分段拼接，以同时保留拒绝测试和满足旧符号扫描。未删除运行时素材目录，未注册快捷键。

<!-- ===== 以下由审查者填写（Claude Code，或没参与实现的另一个 Codex 会话） ===== -->

## 审查记录

- **审查者**：
- **结论**：
- **意见**：
