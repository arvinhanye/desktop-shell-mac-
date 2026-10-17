# M2-06: 菜单栏"隐藏桌面文件"

- **状态**：changes-requested
- **里程碑**：M2（用户追加的小功能）
- **依赖**：M2-05（必须已合并到 `main`，本任务基于它的 VideoWindow / WidgetWindow）
- **分支**：task/M2-06

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

菜单栏增加勾选项"隐藏桌面文件"。勾选后访达的桌面图标被视频盖住，只看到壁纸和组件；再点一次图标恢复。切换是瞬间完成的，**不修改访达设置、不重启访达**，选择在重启应用后保持。

## 背景与约束

- 先读 `AGENTS.md` 的"窗口要求"（"隐藏桌面文件"一条）和"配置文件示例"里关于 `ui.json` 的说明。
- 做法（**第三轮修订**，见下方说明）：

  | 状态 | VideoWindow 层级 | VideoWindow `ignoresMouseEvents` | WidgetWindow 接收点击 | 效果 |
  |---|---|---|---|---|
  | 显示桌面文件（默认） | 图标层 −1 | `true` | 按组件区域动态切换（M2-05 的点击穿透） | 图标在视频上面，可以点 |
  | 隐藏桌面文件 | 图标层 +1（和 WidgetWindow 同层，排在它下面） | **`true`** | **始终接收**（不再穿透） | 视频盖住图标；空白处的点击落在网页的透明背景上，什么都不发生；VideoWindow 永远不会被点到，所以永远不会被提到组件窗口前面 |

  - 切换时先 `orderFront` VideoWindow，再 `orderFront` 同一屏幕的 WidgetWindow。新接入的屏幕按当前状态创建。
  - **第三轮修订的原因**：第一轮让 VideoWindow 在隐藏时接住点击，用户实测点一下空白处，macOS 就把它提到同层最前面，盖住组件。第二轮改成"点击后再把组件窗口排回去"，用户实测**点击时测试面板会闪烁**：点击的瞬间视频窗口先被提上来，然后才被排回去。所以第三轮从根上避免：**不让 VideoWindow 接收任何点击**，隐藏时由最上面的 WidgetWindow 接住全部点击。这个配置在点击穿透探针的第一版中实测过（35 次空白点击都由网页接住，面板没有闪烁）。
  - 具体要求：
    1. **删除第二轮加的代码**：`VideoWindow.sendEvent(_:)` 重写和 `onMouseDown` 回调、`ScreenManager` 的 `restoreWidgetOrder` 和 `didBecomeActiveNotification` 监听。
    2. `VideoWindow` 在两种状态下都是 `ignoresMouseEvents = true`，`setDesktopIconsHidden(_:)` 只改层级。
    3. `HitTestController` 增加开关 `passThroughEnabled: Bool`（默认 `true`）：为 `false` 时，所有 WidgetWindow 一律 `ignoresMouseEvents = false`，鼠标事件和区域更新都不再切换它；改回 `true` 时立刻按 M2-05 的规则重新判断一次。隐藏桌面文件时设为 `false`，显示时设为 `true`；启动时按 `ui.json` 的状态设置。
    4. **禁用网页右键菜单**：WidgetWindow 接住空白处的右键后，WKWebView 会弹出自带的菜单（例如"重新载入"）。在测试页加 `document.addEventListener('contextmenu', e => e.preventDefault())`。（M3 的正式页面也要这样做，Claude Code 会写进 M3 任务单。）
  - 显示桌面文件时，WidgetWindow 和 `HitTestController` 的行为与 M2-05 完全一致。
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
- `Sources/DesktopShell/HitTestController.swift`（修改：第三轮新增 `passThroughEnabled` 开关）
- `web/index.html`（修改：第三轮禁用右键菜单）
- `Tests/DesktopShellTests/UiStateStoreTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。**不运行 `defaults write com.apple.finder`、不 `killall Finder`、不发 AppleScript 给访达**，不以任何方式修改访达或系统设置。
- 不修改 `HitTesting`、`Bridge`、`PowerMonitor` 的逻辑；`HitTestController` 只增加 `passThroughEnabled` 开关，其余逻辑不变。
- 测试不碰真实的用户目录。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 全部通过；`UiStateStoreTests` 覆盖：文件不存在、正常读写往返、缺少字段用默认值、多余字段被忽略、JSON 损坏返回默认值、`save` 能创建不存在的目录
- [ ] `git diff --name-only main...task/M2-06` 只包含"允许修改的文件"
- [ ] `grep -rnE "com.apple.finder|killall|NSAppleScript|osascript" Sources/` 没有输出
- [ ] **（第三轮补充）** `grep -nE "sendEvent|onMouseDown" Sources/DesktopShell/DesktopWindow.swift` 和 `grep -n "didBecomeActiveNotification" Sources/DesktopShell/ScreenManager.swift` 都没有输出（第二轮的重排代码已删除）
- [ ] 用临时支持目录运行，`ui.json` 里写入 `"desktopIconsHidden": true` 后启动：`CGWindowListCopyWindowInfo` 显示 VideoWindow 和 WidgetWindow 都在 −2147483602，并且按屏幕上的前后顺序 WidgetWindow 排在 VideoWindow 前面；访达图标窗口（−2147483603）在它们下面
- [ ] 同样的检查，`desktopIconsHidden` 为 `false` 时 VideoWindow 回到 −2147483604
- [ ] 运行前后 `defaults read com.apple.finder CreateDesktop` 的输出一致

**用户手动验证**（运行 `.build/debug/DesktopShell`）：

- [ ] 菜单栏 →"隐藏桌面文件"：桌面图标立刻消失，只剩视频和测试面板；菜单项打勾；访达窗口（如果开着）没有被关闭
- [ ] 隐藏状态下：点空白处、双击空白处、右键空白处都没有反应（不会选中或打开看不见的文件）；测试面板的"播放测试语音"仍然能用
- [ ] **（审查后补充）** 隐藏状态下重启应用，在空白处单击、双击、右键各几次，**测试面板一直可见，没有任何闪烁**；右键不弹出菜单；Claude Code 读窗口列表确认组件窗口始终排在视频窗口前面
- [ ] **（第三轮补充）** 切回显示桌面文件后，图标仍然可以单击选中、框选、双击打开（点击穿透恢复正常）
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

### 第二轮（2026-10-17）

- **修订内容**：
  - VideoWindow 重写 `sendEvent(_:)`，先完成 `super` 处理，再针对左键、右键和其他鼠标按下通知 ScreenManager；鼠标抬起和移动等事件不触发回调。
  - ScreenManager 仅在隐藏模式下，通过 `order(.above, relativeTo: video.windowNumber)` 将同一显示器的 WidgetWindow 排回 VideoWindow 上方；应用收到 `didBecomeActiveNotification` 时，对所有当前窗口对执行相同重排。没有引入定时器。
  - 新建窗口对自动绑定按下回调，回调弱引用 ScreenManager 并按 display ID 查找当前窗口对；关闭窗口时清空回调，停止管理时移除应用激活监听。
- **验证结果**：
  - 修改前 `scripts/test.sh` 基线 **73/73 通过**；修改后最终 `swift build` 退出码 0，构建日志经 `grep -iE 'warning|error'` 检查无输出，`scripts/test.sh` **73/73 通过**（8 个 suite）。本轮没有新增纯逻辑单元测试声明。
  - 使用实际 AppKit 窗口和生产 ScreenManager 编写临时原生回归脚本。脚本先主动将视频窗口排到组件前面，复现已确认的错误顺序，再向 VideoWindow 传入鼠标事件或发送进程内激活通知，使用 `CGWindowListCopyWindowInfo` 验证处理后的真实窗口顺序。取样前让事件循环完成窗口列表刷新，避免把异步刷新误判为结果。
  - 同一回归脚本在修复前 **13/19 通过、6 项预期失败**，修复后 **19/19 通过**；六项对应左键、双击左键、右键、其他鼠标按下、应用激活和重新创建窗口后的按下恢复。绿色结果示例：Widget #3207 在 index 21、Video #3206 在 index 22；刻意反转后，按下处理将组件恢复到前面。
  - 脚本同时验证正常鼠标事件仍传到 contentView、非按下事件不重排、显示模式保持原有层级与穿透属性，以及停止后不重新显示已关闭窗口、ScreenManager 可以释放。测试仅使用一块实际显示器；激活是进程内通知，鼠标事件直接传入 `sendEvent(_:)`，不等同于实际用户切换应用或物理点击验收。
  - 原有原生菜单与持久化回归重新执行，**15/15 通过**，包括启动恢复、切换、保留其他 UI 字段、保存失败仍应用模式、暂停菜单独立及退出关闭。测试数据仍使用临时支持目录。
  - `git diff --check` 通过；源码禁用命令检查无输出；本轮两个实现文件的 `Timer` / `asyncAfter` 检查无输出。独立只读复核未发现已确认的 Critical / Important / Minor 代码缺陷。
  - 本轮日志和临时原生检查源码位于 `/tmp/ds-m2-06-review2/`：`baseline-tests.log`、`order-red.log`、`order-green.log`、`build.log`、`final-tests.log`、`menu.log`、`WindowOrderChecks.swift`、`run-order-checks.sh`。
- **范围与剩余验收**：
  - 本轮仅修改 DesktopWindow.swift、ScreenManager.swift 及本任务状态与交付记录；WidgetWindow、HitTesting、HitTestController、Bridge、PowerMonitor 的逻辑保持原样；任务需求和审查记录保持原样。
  - 仍需按手动清单验证：隐藏模式重启后，从其他应用切回，反复单击、双击、右键和其他鼠标按键点击壁纸空白处，测试面板始终可见且可操作，隐藏的文件不被触发；多显示器与 Spaces 切换也需实机复验。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **第三轮结论**：**需修改**。第二轮的"点击后重排"实现正确，但用户实测**点击时测试面板会闪烁**：点击的瞬间视频窗口先被提上来，然后才被排回去。这是 Claude Code 第二轮给的修法本身有缺陷，不是 Codex 的实现问题。
- **修改要求**（第三轮，2026-10-17）：按需求部分重写后的"做法"实现：删除第二轮的重排代码；VideoWindow 始终不接收鼠标；`HitTestController` 增加 `passThroughEnabled` 开关，隐藏时让 WidgetWindow 接住全部点击；测试页禁用右键菜单。允许修改的文件新增 `HitTestController.swift` 和 `web/index.html`。修改后推送分支、状态改回 `review`，在交付记录末尾追加"第三轮"小节。
- **第二轮结论**：**需修改**。下面的风险经用户实测确认存在。
- **问题**：用户在隐藏状态下重启应用，点一下空白处后测试面板消失。Claude Code 读窗口列表确认：视频窗口（3159）排到了组件窗口（3162）前面（屏幕顺序 #21 对 #22），两者同在 −2147483602。原因是隐藏状态下点击落在 VideoWindow 上，macOS 把它提到了同层最前面。
- **修改要求**（第二轮，2026-10-17）：按需求部分"背景与约束"里新补充的"点击会打乱顺序"四点实现：VideoWindow 在鼠标按下后通知 ScreenManager，ScreenManager 把同一屏幕的 WidgetWindow 用 `order(.above, relativeTo:)` 排回视频窗口上方；应用被激活时也重排。允许修改的文件不变（`DesktopWindow.swift`、`ScreenManager.swift` 足够）。修改后推送分支、状态改回 `review`，在交付记录末尾追加"第二轮"小节。
- **第一轮结论**：代码审查通过，可执行检查全部通过；等用户手动验证后合并（重点是下面这个风险）。
- **复验结果**（Claude Code，2026-10-17）：
  - [x] touch 源码后强制重编，零警告零错误；`scripts/test.sh` 73/73 通过（新增 10 个）
  - [x] 改动范围是 5 个允许的文件和本任务单；`HitTesting`、`HitTestController`、`Bridge`、`PowerMonitor` 没有改动；源码里没有 `com.apple.finder`、`killall`、`NSAppleScript`、`osascript`
  - [x] `ui.json` 为 `desktopIconsHidden: true` 时启动：两个窗口都在 −2147483602，组件窗口（较晚创建）在屏幕上排在视频窗口前面，访达图标 −2147483603 在下面
  - [x] 为 `false` 时启动：组件窗口 −2147483602 → 访达图标 −2147483603 → 视频窗口 −2147483604
  - [x] 运行前后 `defaults read com.apple.finder CreateDesktop` 一致（该键不存在）
- **待用户验证的风险**：隐藏模式下视频窗口和组件窗口同层，macOS 点击窗口时可能把被点的窗口提到同层最前面。如果点空白处（落在视频窗口上）让视频窗口跑到组件窗口前面，组件就会被盖住。Codex 验证了切换后的顺序，没有验证"点击视频窗口之后"的顺序，需要实测。
- **意见**：
  - `UiStateStore` 对缺失、`null`、类型错误、损坏都有回退，保存失败不影响当前切换；切换时总是先排视频、再排组件，新接入的屏幕继承当前状态。实现简洁。
