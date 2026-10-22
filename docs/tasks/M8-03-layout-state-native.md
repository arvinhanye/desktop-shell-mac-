# M8-03: 布局持久化与原生菜单入口

- **状态**：todo
- **里程碑**：M8
- **依赖**：M8-02 本地实现与自查通过
- **分支**：task/M8-03（接续 M8-02，记录起点 SHA）
- **依据**：已确认方案第 4.2/4.3 节及 M8-00 计划；Codex 经用户同意编制。

## 目标与接口

- UiState 新增 layoutPreset（standard/work-first）和八键 widgetVisibility（clock/greeting/projects/launcher/todos/stats/character/visualizer，Bool）。旧文件全部显示、标准布局；非法文件单项按默认值恢复，保留其余外观字段。
- `saveUiState` 在原参数之外接受 `layoutPreset?: String`、`widgetVisibility?: [String:Bool]`。null、未知预设/组件、非真正布尔值、空显隐补丁或全空请求 invalid。部分显隐键基于当前内存合并，多屏不同键操作互不覆盖。
- `UiStateUpdate.apply` 与 `AppState.updateAppearance` 增加默认 nil 的 layoutPreset/visibility 参数，原调用兼容；真实写盘成功才广播，失败恢复原状态。getConfig 回复和 uiState 事件均返回完整 layoutPreset/widgetVisibility。
- 新增 `web/js/layout-state.js`：`DISPLAY_WIDGETS`、`defaultVisibility()`、`normalizeLayoutState(ui)`，复用于初始状态、回复规范化、事件和 mock，不包含 DOM 副作用。
- `PageEvent.openLayout()` 精确返回 `{event:"openLayout"}`；不进入 PageEventCache。网页验证事件无额外字段，设置 layoutOpen=true、appearanceOpen=false、editingProjectId=null。
- 新增原生菜单“桌面布局…”，调用 `ScreenManager.openLayoutAtPointer()`；选鼠标所在已存在窗口的屏幕，否则主屏；无匹配窗口则不执行，日志仅状态。`WidgetWindow.requestOpenLayout()` 转交容器，不调用 makeKey/activate。
- `LayoutPresentation.swift` 定义可测试纯值状态：`requestOpen() -> Bool`（是否立即交付）、`beginLoad(generation: Int)`、`didBecomeReady(generation: Int) -> Bool`、`clear()`。ready=false 时请求合并为一次 pending；旧代回调忽略；已消费后重载不重弹。
- WebContainer 在当前 pageGeneration 的 main.js import 成功且既有 onPageLoaded 完成后交付 pending；未成功就绪前不交付；窗口停止清除意图。使用现有 generation，避免导航开始与 reload 重复消耗。

## 允许修改的文件

- `Sources/DesktopShell/{UiStateStore,AppState,BridgeProtocol,Bridge,AppDelegate,ScreenManager,DesktopWindow,WebContainer}.swift`
- `Sources/DesktopShell/LayoutPresentation.swift`（新建，含屏幕纯选择函数）
- `Tests/DesktopShellTests/{UiStateStoreTests,BridgeTests,PageEventTests}.swift`、`Tests/DesktopShellTests/LayoutPresentationTests.swift`（新建）
- `web/js/{bridge,mock,store}.js`、`web/js/layout-state.js`（新建）
- `Tests/web/{bridge,mock,store,linkage}.test.mjs`、`Tests/web/layout-state.test.mjs`（新建）
- 本任务单的状态及交付记录。

## 实施步骤与自动验收

- [ ] RED：UiStateStoreTests 断言旧文件默认、混合有效/无效布局字段不丢 avatar/background/voice/desktopIconsHidden、完整往返、失败回滚。
- [ ] RED：BridgeTests/PageEventTests 断言严格 Bool 和键校验、局部显隐更新、两次不同键更新都保留、只有成功保存才广播、公开状态无路径。
- [ ] RED：LayoutPresentationTests 断言 ready 请求即发、未 ready 多次请求只在就绪后发一次、旧代就绪忽略、重载不重弹、clear 后无遗留；屏幕选择覆盖负坐标、鼠标屏优先、主屏兜底及无屏。
- [ ] RED：前端测试断言旧 uiState 规范化、完整布局推送、无额外字段 openLayout、面板互斥；mock 合约与 Swift 相同。
- [ ] 运行 `scripts/test.sh --filter LayoutPresentationTests` 及 `node --test Tests/web/layout-state.test.mjs Tests/web/bridge.test.mjs`，记录因缺实现产生的 RED。
- [ ] GREEN：实现模型、白名单、局部合并、菜单路由和一次性事件；瞬时事件不参与 replay。
- [ ] GREEN：`scripts/test.sh`、`scripts/test-web.sh`、`swift build`、`git diff --check`；子代理只读自查、本地提交。

## 用户手动验证

- [ ] M8-04 接入面板后检查菜单条目打开鼠标屏上的面板，不切换前台应用、不自动接管键盘。
- [ ] 页面加载中点菜单，加载完成后仅打开一次；重载后不自行再弹；断开屏幕后不转移旧打开意图。

## 交付记录

- **改动摘要**：尚未实施。
- **自测结果**：尚未执行。
- **疑问 / 偏离**：无。

## 审查记录

- **审查者**：待正式独立审查。
- **结论**：待审查。
- **意见**：子代理结果仅作实现自查。
