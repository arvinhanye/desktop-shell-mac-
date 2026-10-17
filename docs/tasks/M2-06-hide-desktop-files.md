# M2-06: 菜单栏"隐藏桌面文件"

- **状态**：todo
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
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
