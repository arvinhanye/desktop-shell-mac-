# M2-06: 菜单栏"隐藏桌面文件"

- **状态**：review
- **里程碑**：M2（用户追加的小功能）
- **依赖**：M2-05（必须已合并到 `main`，本任务基于它的 VideoWindow / WidgetWindow）
- **分支**：task/M2-06

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

菜单栏增加勾选项"隐藏桌面文件"。勾选后访达的桌面图标被视频盖住，只看到壁纸和组件；再点一次图标恢复。切换是瞬间完成的，**不修改访达设置、不重启访达**，选择在重启应用后保持。

## 背景与约束

- 先读 `AGENTS.md` 的"窗口要求"（"隐藏桌面文件"一条）和"配置文件示例"里关于 `ui.json` 的说明。
- 做法：只改 VideoWindow 的层级和是否接收鼠标。

  | 状态 | VideoWindow 层级 | VideoWindow `ignoresMouseEvents` | 效果 |
  |---|---|---|---|
  | 显示桌面文件（默认） | 图标层 −1 | `true` | 图标在视频上面，可以点 |
  | 隐藏桌面文件 | 图标层 +1（和 WidgetWindow 同层） | `false` | 视频盖住图标；空白处的点击被视频窗口接住，**不会点到看不见的图标** |

  - 隐藏时 VideoWindow 和 WidgetWindow 在同一层，必须保证 **WidgetWindow 在上面**：改完 VideoWindow 的层级后，先 `orderFront` VideoWindow，再 `orderFront` 同一屏幕的 WidgetWindow。新接入的屏幕也要按当前状态创建。
  - WidgetWindow 和 `HitTestController` 的行为完全不变：鼠标在组件上时组件照常可以点。
  - 遮挡判断（`PowerMonitor`）仍然只看 VideoWindow，不需要改。
- **`UiStateStore.swift`**（新建，配单元测试）：

  ```swift
  struct UiState: Codable, Equatable {
      var avatarId: String? = nil
      var backgroundId: String? = nil
      var voiceEnabled: Bool = true
      var desktopIconsHidden: Bool = false
  }
  struct UiStateStore {
      let supportDir: URL
      func load() -> UiState          // 不抛错
      func save(_ state: UiState) throws
  }
  ```

  - 文件是 `supportDir/ui.json`。
  - `load()`：文件不存在 → 返回默认值；JSON 损坏 → `NSLog` 记录并返回默认值；缺少某些字段 → 这些字段用默认值（自定义 `init(from:)`，用 `decodeIfPresent`）；多余的字段忽略。
  - `save`：创建 `supportDir`（含中间目录），格式化写入（`prettyPrinted` + `sortedKeys`），用 `.atomic` 写。
  - 本任务只用到 `desktopIconsHidden`，其他字段先定义好，留给 M3/M4。
- **菜单栏**：在"暂停动画"下面加"隐藏桌面文件"，勾选状态（`.on/.off`）表示当前是否隐藏。启动时从 `ui.json` 读取并应用；点击时切换、立即应用到所有屏幕、保存到 `ui.json`（保存失败只记录日志，不影响切换）。切换时打印 `NSLog("DesktopShell: desktop icons hidden=%@", ...)`。

## 允许修改的文件

- `Sources/DesktopShell/UiStateStore.swift`（新建）
- `Sources/DesktopShell/DesktopWindow.swift`（修改：VideoWindow 提供切换方法）
- `Sources/DesktopShell/ScreenManager.swift`（修改：保存当前状态，应用到现有和新建的窗口，保证窗口顺序）
- `Sources/DesktopShell/AppDelegate.swift`（修改：菜单项、启动时读取、点击时保存）
- `Tests/DesktopShellTests/UiStateStoreTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。**不运行 `defaults write com.apple.finder`、不 `killall Finder`、不发 AppleScript 给访达**，不以任何方式修改访达或系统设置。
- 不修改 `HitTesting`、`HitTestController`、`Bridge`、`PowerMonitor` 的逻辑。
- 测试不碰真实的用户目录。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过；`UiStateStoreTests` 覆盖：文件不存在、正常读写往返、缺少字段用默认值、多余字段被忽略、JSON 损坏返回默认值、`save` 能创建不存在的目录
- [ ] `git diff --name-only main...task/M2-06` 只包含"允许修改的文件"
- [ ] `grep -rnE "com.apple.finder|killall|NSAppleScript|osascript" Sources/` 没有输出
- [ ] 用临时支持目录运行，`ui.json` 里写入 `"desktopIconsHidden": true` 后启动：`CGWindowListCopyWindowInfo` 显示 VideoWindow 和 WidgetWindow 都在 −2147483602，并且按屏幕上的前后顺序 WidgetWindow 排在 VideoWindow 前面；访达图标窗口（−2147483603）在它们下面
- [ ] 同样的检查，`desktopIconsHidden` 为 `false` 时 VideoWindow 回到 −2147483604
- [ ] 运行前后 `defaults read com.apple.finder CreateDesktop` 的输出一致

**用户手动验证**（运行 `.build/debug/DesktopShell`）：

- [ ] 菜单栏 →"隐藏桌面文件"：桌面图标立刻消失，只剩视频和测试面板；菜单项打勾；访达窗口（如果开着）没有被关闭
- [ ] 隐藏状态下：点空白处、双击空白处、右键空白处都没有反应（不会选中或打开看不见的文件）；测试面板的"播放测试语音"仍然能用
- [ ] 再点一次"隐藏桌面文件"：图标立刻回来，可以正常选中、双击打开
- [ ] 隐藏后退出应用再启动：仍然是隐藏状态；恢复显示后再重启：仍然是显示状态

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
  - 新增 UiState 四个字段及 UiStateStore。读取缺失文件直接返回默认值；缺失/null 字段各自回退默认值；损坏 JSON、字段类型错误和读取失败记录日志后整份回退，不重写原始文件。保存创建中间目录，使用 prettyPrinted、sortedKeys 和 atomic 写入。
  - VideoWindow 提供隐藏模式切换：隐藏时升至图标层 +1 并接收鼠标，显示时恢复图标层 −1 并穿透。WidgetWindow 的逻辑保持不变。
  - ScreenManager 保存当前模式，统一应用到现有及新建窗口对；应用时先显示 VideoWindow、再显示 WidgetWindow，保证同层时组件在前。
  - 菜单在“暂停动画”下增加“隐藏桌面文件”。启动读取 ui.json 后应用模式及勾选；点击立即切换全部屏幕并保存，保留头像、背景和语音字段。保存失败只记录日志，当前模式与菜单勾选仍保持一致。
- **自测结果**（2026-10-17）：
  - 从与 origin/main 一致的最新 main（`5f48487`）创建 `task/M2-06`。基线 **63/63**；新增 **10 个 UiStateStore 测试声明**，空实现触发 11 条预期失败；实现后及最终 `scripts/test.sh` 均 **73/73 通过**，共 8 个 suite。
  - 新测试覆盖缺失文件且读取无写入、四字段往返及覆盖、缺字段和 null 默认值、多余字段忽略且保留原文、损坏/类型错误回退、自动创建目录、格式化及键排序、支持目录被文件占用、ui.json 被目录占用时的错误传播和原始内容保护。所有夹具均使用临时目录。
  - `swift build` 退出码 0；构建日志经 `grep -iE 'warning|error'` 检查无输出。规定的 `grep -rnE 'com.apple.finder|killall|NSAppleScript|osascript' Sources/` 无输出；`git diff --check` 通过。
  - 原生菜单/生命周期检查先在未接线实现上复现缺少菜单及启动未恢复隐藏模式；接线后 **15/15 通过**。检查实际菜单顺序、目标 action、勾选和窗口模式、保存其他 UI 字段、同进程生命周期重启、重新创建窗口继承当前模式、保存失败仍切换、暂停菜单独立性及退出关闭。
  - 原生检查通过实际 VideoWindow/WidgetWindow 的 windowNumber 匹配 `CGWindowListCopyWindowInfo` 顺序：隐藏启动、菜单切换、重新创建窗口时均是组件在前、视频在后；例如 Widget #3017 在 index 24，Video #3016 在 index 25。鼠标拦截检查验证的是 ignoresMouseEvents 属性，不等同于真实桌面点击已验收。
  - 另外构建并运行实际 `.build/debug/DesktopShell`，使用独立临时支持目录并复用 `/tmp/ds-support/media`。本机一块屏幕：隐藏时两个窗口均为 **−2147483602**，Finder 图标 **−2147483603** 在其下；显示时视频恢复 **−2147483604**，组件仍为 **−2147483602**。
  - 将实际菜单 action 保存的两份 ui.json 分别用于跨进程检查：隐藏模式 PID 34110 → 34120、显示模式 PID 34131 → 34141，每次都结束前一个进程再启动，**4/4 窗口层级检查通过**，两次启动之间不改 ui.json，文件内容也保持原样。所有测试进程均已结束。
  - 运行前后读取 `defaults read com.apple.finder CreateDesktop`，均为该键不存在，退出码均为 1、stdout 均为空，stderr 除工具自动附加的时间戳/PID 外诊断一致。没有写入该设置，没有重启或向 Finder 发送脚本。
  - 独立只读检查未发现已确认的 Critical / Important / Minor 代码缺陷。完整日志、窗口数据、菜单保存样本和临时检查源码位于 `/tmp/ds-m2-06-validation/`。
- **疑问 / 偏离**：
  - 无范围偏离，改动仅含允许的 5 个实现/测试文件及本任务状态、交付记录；AGENTS.md、CLAUDE.md、任务需求和审查记录均保持原样。
  - 真实空白处单击/双击/右键不触发隐藏图标、组件按钮与语音仍可用，以及多显示器热插拔和 Spaces 切换后的顺序，仍按手动清单验收。新窗口继承状态已通过重新创建窗口验证，尚未实际插拔第二块屏幕。
  - 按本任务明确限制，Bridge、HitTesting、HitTestController 和 PowerMonitor 逻辑未修改。最新规范中的 Bridge 来源校验与遮挡防抖是现有实现的后续事项，不纳入本次菜单功能；ui.json 仍按应用独占管理，不增加并发写入合并或未知字段保留机制。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
