# M7-04: 输入框支持复制、粘贴等编辑快捷键

- **状态**：review
- **里程碑**：M7
- **依赖**：无。只改 `AppDelegate.swift` 和一个新文件，和 M7-03 的文件不冲突，前后都行
- **分支**：task/M7-04

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

在待办、项目的输入框里，⌘V 粘贴、⌘C 复制、⌘X 剪切、⌘A 全选、⌘Z 撤销、⇧⌘Z 重做都能用，和普通 Mac 应用一样。M7 的"粘贴文件夹路径"离不开这一条。

## 背景与约束

- **用户报告**（2026-10-21，M7-03 验收时）：项目和待办的输入框都不能复制粘贴。
- **原因**（Claude Code 查明）：
  - 普通 Mac 应用的这些快捷键，是由菜单栏"编辑"菜单里各菜单项的快捷键分派的：⌘V 对应 `paste:`，沿响应链送到当前的第一响应者，也就是 WKWebView。
  - DesktopShell 是 `LSUIElement` 应用，代码里从没设过 `NSApp.mainMenu`，只有菜单栏图标的菜单。所以 ⌘V 这类按键没有菜单项接手，WebView 也不处理，按下去什么都不发生。
  - 网页又在 `main.js` 里禁用了右键菜单（AGENTS.md "桌面组件交互基线"），所以用右键粘贴也不行。
  - 这个问题从 M3-08（组件窗口能获得键盘）起就存在。
- **做法**：给应用设一个**看不见的主菜单**，里面放标准的"编辑"菜单。`LSUIElement` 应用不显示菜单栏，但 `NSApp.mainMenu` 里的快捷键仍然会被分派。组件窗口在输入框获得焦点时是 key window（M3-08），按键会走到这里。
  - 不改"不激活应用"的做法，不调用 `NSApp.activate`。
  - 不恢复右键菜单。

### 1. 编辑菜单（新建 `Sources/DesktopShell/EditMenu.swift`）

```swift
enum EditMenu {
    /// 返回一个只有"编辑"子菜单的主菜单，交给 NSApp.mainMenu。
    static func makeMainMenu() -> NSMenu
}
```

- "编辑"子菜单里的项目，按顺序：

  | 标题 | action | 快捷键 |
  |---|---|---|
  | 撤销 | `undo:` | ⌘Z |
  | 重做 | `redo:` | ⇧⌘Z |
  | 分隔线 | | |
  | 剪切 | `cut:` | ⌘X |
  | 拷贝 | `copy:` | ⌘C |
  | 粘贴 | `paste:` | ⌘V |
  | 全选 | `selectAll:` | ⌘A |

- `target` 都是 `nil`，沿响应链送给第一响应者。

### 2. 接线（`AppDelegate.swift`）

- 在 `applicationDidFinishLaunching` 里设 `NSApp.mainMenu = EditMenu.makeMainMenu()`，放在建窗口之前。
- 不改菜单栏图标的菜单。

### 3. 如果主菜单的做法在不激活的面板上不起作用

在桌面上验证时，如果按 ⌘V 没有反应，就说明主菜单的快捷键没有分派到不激活的面板。这时在 `WidgetWindow`（`DesktopWindow.swift`）里改写 `performKeyEquivalent(with:)` 作为后备：

- 只处理 Command 加 Z / ⇧Z / X / C / V / A 这几个组合；
- 用 `NSApp.sendAction(_:to: nil, from:)` 发出上表对应的 action；
- 其余按键交给 `super`。

用了后备方案的话，在交付记录里写明，`DesktopWindow.swift` 也算在允许修改的范围里。先试第 1、2 节的做法，不要两种都做。

### 4. 测试

- 新建 `Tests/DesktopShellTests/EditMenuTests.swift`：用 `@MainActor` 建菜单，断言这些内容：
  - 有一个子菜单；
  - 子菜单的项目顺序、`action`、`keyEquivalent` 和 `keyEquivalentModifierMask` 和上表一致；
  - 所有项目的 `target` 都是 `nil`。
- 用了后备方案的话：把"按键 → action"的对应关系写成纯函数，补测试。

## 允许修改的文件

- `Sources/DesktopShell/EditMenu.swift`（新建）
- `Sources/DesktopShell/AppDelegate.swift`（修改）
- `Sources/DesktopShell/DesktopWindow.swift`（只在用第 3 节的后备方案时修改）
- `Tests/DesktopShellTests/EditMenuTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不调用 `NSApp.activate`，不改组件窗口获得和交还键盘的逻辑（M3-08）。
- 不改网页：不恢复右键菜单，不在 JS 里自己处理 ⌘V。
- 不让菜单栏出现别的菜单，状态栏图标的菜单保持不变。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build` 无错误、无警告
- [ ] `scripts/test.sh` 全部通过
- [ ] `scripts/bundle.sh` 成功
- [ ] `git diff --name-only main...task/M7-04` 只有上面"允许修改的文件"

**用户手动验证**（用主仓库的 `build/DesktopShell.app`）：

- [ ] 在别的应用里拷贝一段文字，点项目输入框，⌘V → 文字贴进去了
- [ ] 待办输入框里同样能 ⌘V
- [ ] 输入框里打几个字：⌘A 全选，⌘C 拷贝，再到别的应用里 ⌘V 能贴出来；⌘X 剪切后输入框变空；⌘Z 撤销、⇧⌘Z 重做都有效
- [ ] 用拼音输入法打中文照常（候选框位置正常，回车上屏）
- [ ] 不受影响的情况：
  - 输入框没有焦点时（例如刚在桌面空白处点了一下），⌘V 不会把东西贴到组件里；
  - 在别的应用里 ⌘C / ⌘V 照常；
  - 按 Esc 后键盘回到原来的应用。
- [ ] 菜单栏里没有多出 DesktopShell 的菜单，前台应用的菜单栏保持原样

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
  - 从最新 `main` / `origin/main`（`00268d0`）建立 `task/M7-04`。
  - 新增 `@MainActor EditMenu.makeMainMenu()`：唯一“编辑”子菜单依次为撤销、重做、分隔线、剪切、拷贝、粘贴、全选；六个标准 action 使用 nil target，快捷键与修饰键严格按任务表设置，保留 AppKit 自动菜单验证。
  - `applicationDidFinishLaunching` 第一行设置主菜单，早于窗口创建。`AppDelegate.swift` 只有这一行变化，状态栏图标菜单保持原样；未修改网页、窗口焦点、激活逻辑或 DesktopWindow.swift。
- **自测结果**：
  - 基线 PASS：`scripts/test.sh` 254/254（27 suites）。
  - RED：先写 EditMenuTests，确认缺少 EditMenu 实现导致编译失败。
  - 中间失败与诊断：首次全量 255/256，失败来自新测试额外假设父菜单项也必须保持 nil action/target。临时 AppKit 探针确认设置 submenu 会自动给父项绑定 `submenuAction:` 与 NSMenu target；修正该父容器断言，保留六个编辑命令及分隔线的 nil target 检查。未为消除该失败修改生产菜单逻辑。
  - GREEN：`scripts/test.sh` 256/256 PASS（28 suites）；新增 2 项覆盖菜单唯一性、项目顺序、分隔线、action、keyEquivalent、modifier mask、nil target、独立工厂对象与不替换当前主菜单的行为。
  - 网页回归 `scripts/test-web.sh` 474/474 PASS，0 FAIL / 0 SKIP；无网页修改。
  - `swift build` PASS，无错误或警告；`scripts/bundle.sh` release PASS，固定 DesktopShell Self-Signed 签名、plist 与 designated requirement 验证通过，产物 `/Users/arvinhan/Desktop/desktop-shell/build/DesktopShell.app`。
  - `git diff --check`、4 文件范围检查 PASS；接线位于 ScreenManager 创建之前，状态栏菜单逐字保持基线。子代理只读自查未发现阻塞缺陷，仅算交付前自查，不是正式审查。
  - 尚未执行桌面手动验收：两个输入框的粘贴、全选/拷贝/剪切、撤销/重做、拼音输入、无焦点时不误贴、其他应用快捷键、Esc 交还键盘及菜单栏不变。本次未启动 DesktopShell、未读写用户剪贴板或真实配置；测试只在测试进程构造 AppKit 菜单。
- **疑问 / 偏离**：
  - 无范围扩展。按任务先交付主菜单方案，未提前实现 performKeyEquivalent 后备；仅在主仓库打包应用的桌面验收确认主菜单分派无效后，再启用第 3 节方案并补纯函数测试。
  - 交付为 review，仅提交并推送 task/M7-04，不合并或推送 main。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **审查者**：Codex（独立会话，2026-10-21；未参与实现）
- **审查对象**：`main...task/M7-04`，基线 `00268d0`，实现提交 `4d19d6d`。
- **结论**：通过。代码审查、自动复验和用户桌面手动验收均通过，未发现需退回的缺陷。用户已明确同意提交审查记录、合并到 `main` 并推送 `origin`。
- **复验结果**：
  - 在独立临时检出中执行，未改业务代码、未启动临时应用、未操作登录项。
  - `swift build` PASS，无编译错误或警告。
  - `scripts/test.sh` PASS：256 tests / 28 suites。
  - `scripts/test-web.sh` PASS：474/474，0 FAIL / 0 SKIP。
  - `scripts/bundle.sh` PASS：release 构建、plist 校验、固定证书签名和 designated requirement 验证均成功。
  - `git diff --check` 和文件范围检查 PASS：4 个变更文件均在允许范围内，任务需求部分未改动。
  - 审阅覆盖 4/4 文件，0 跳过。OCR delegate 用于文件与规则解析；另行完整检查其默认排除的测试和任务单。菜单顺序、selector、快捷键、修饰键、nil target、MainActor 隔离及启动接线符合任务要求；状态栏菜单、Bridge 白名单、网页和窗口焦点逻辑保持原样。
- **桌面验收与证据**：
  - 用户针对完整清单回复“通过”：项目和待办输入框 ⌘V；⌘A / ⌘C / ⌘X / ⌘Z / ⇧⌘Z；跨应用复制粘贴；中文拼音候选框和上屏；失焦后不误贴；Esc 交还键盘；前台应用菜单栏保持原样。
  - 审查者补充核对：运行日志显示加载主仓库 `/Users/arvinhan/Desktop/desktop-shell/build/DesktopShell.app/Contents/Resources/web`，同一进程记录了 5 组 `focusInput ok` / `blurInput ok`。日志仅佐证运行来源和焦点消息，快捷键内容及中文候选框结果以用户实测为依据。
  - 主仓库应用二进制含 `EditMenu.makeMainMenu`，`LSUIElement=true`，designated requirement 使用既定固定证书。沙盒内签名校验曾返回 `CSSMERR_TP_NOT_TRUSTED`；在正常钥匙串访问环境重验通过（`valid on disk` / `satisfies its Designated Requirement`），未修改证书或信任设置。
  - 主菜单方案桌面验收通过，无需第 3 节后备分派。
- **流程记录**：
  - 首次提交并推送命令因授权确认被权限审核拦截，未执行；用户随后明确同意提交、合并和推送。获取远端后确认 `main` 与 `origin/main`、`task/M7-04` 与对应远端分支分别一致。
  - 自动复验日志：`/private/tmp/m7-04-review-build.log`、`/private/tmp/m7-04-review-tests.log`、`/private/tmp/m7-04-review-web.log`、`/private/tmp/m7-04-review-bundle.log`。
