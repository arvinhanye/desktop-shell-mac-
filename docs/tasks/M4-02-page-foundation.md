# M4-02: 页面基础：定稿 token、字体、底板样式和滚动淡出

- **状态**：todo
- **里程碑**：M4
- **依赖**：M4-01（必须已合并到 `main`：`store.js`、`mock.js` 两个任务都改）
- **分支**：task/M4-02

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

正式页面换上 M3.5 定稿的 token、字体和底板样式，准备好组件共用的滚动淡出和 store 状态，mock 数据换成效果图的数据；删掉 M3 的自检面板，以及只为它开的导航例外。做完后页面上暂时一个组件都没有：桌面上只剩视频（组件从 M4-03 起逐个加回来），浏览器里是一张空白页，但字体已经能加载。

## 背景与约束

- 先读 `docs/design/README.md`：开头的文件表，以及"组件的共同写法""store 里的键"两节；`docs/design/design.css` 开头 `web/styles/base.css` 那一节；AGENTS.md "设计规范"。
- M3-03 审查记录里写给 M4 的要求：去掉自检面板时，同时删掉 `WebNavigationPolicy` 里的 `about:srcdoc` 例外，让导航规则恢复成"只允许 `shell://`"。

### 1. 样式

- `docs/design/tokens.css` 原样复制成 `web/styles/tokens.css`（替换 M3 的占位值）；`docs/design/fonts.css` 原样复制成 `web/styles/fonts.css`。复制时不调整任何数值。
- `web/styles/base.css`：删掉 M3 的 `.card` 规则，把 `design.css` 里 `base.css` 那一节原样追加进来；其他现有规则（交互基线、`#desktop` 安全区域、`.widget`、`[data-paused]`、`[hidden]`）保留不动。
- `web/index.html`：在 `styles/tokens.css` 前面加一行 `styles/fonts.css`。CSP 不改（字体和音频都走 `default-src 'self' shell:`）。

### 2. store（`web/js/store.js`）

`initialState` 加四个键，含义和谁来写见 README 的"store 里的键"：`now: null`、`appearanceOpen: false`、`voiceRequest: 0`、`voicePlaying: false`。

### 3. 删掉自检面板和导航例外

- 删除 `web/widgets/devpanel.js`、`web/widgets/devpanel.css`；`web/js/main.js` 的 `WIDGETS` 改成空数组（后面的任务逐个往里加）。
- `BridgeProtocol.swift` 的 `WebNavigationPolicy.allows`：去掉 `about:srcdoc` 那一支，只保留"`url` 的 scheme 是 `shell` 就放行"。不改 `WebContainer.swift` 的调用方式。
- 自检面板里的各项检查在 M3 已经验收过，不需要搬到别处。

### 4. 滚动淡出（新建 `web/js/scroll-hints.js`）

```js
export function scrollHintState({ scrollTop, clientHeight, scrollHeight })  // → { above, below }
export function installScrollHints(list, { win = window } = {})              // → 清理函数
```

- 判断规则照效果图 `mockup.js` 的 `updateScrollHints`：`scrollHeight - clientHeight > 1` 才算能滚动；能滚动且 `scrollTop > 1` → `above`；能滚动且 `scrollTop + clientHeight < scrollHeight - 1` → `below`。
- `installScrollHints` 按结果给列表切换 `more-above`、`more-below` 两个 class。什么时候重新判断：安装时一次；`scroll`（passive）；列表尺寸变化（`ResizeObserver` 观察列表本身）；列表子节点增删（`MutationObserver`，`childList`）。不轮询。
- 清理函数断开两个观察器、移除滚动监听。

### 5. mock 数据换成效果图的数据（`web/js/mock.js`）

- `config.projects`、`config.apps`、提醒事项换成 `docs/design/mockup.js` 里的示例：6 个项目、6 个应用加一个没装的 Figma（`iconUrl: null`）、13 条提醒（日期仍按"今天"往前后推算）。应用的 `iconUrl` 用 `/media/app-icons/<id>.png`。
- 初始 `uiState` 改成 `{ avatarId: '1', backgroundId: 'folder-01', voiceEnabled: true }`，和效果图一致。
- `user`、`character`、`greetings`、`media`（含 `voices`）保持 M4-01 的样子；mock 的其余行为（各个动作的校验、模拟事件）不变。
- 这样浏览器里看到的数据和效果图、`assets/design-screenshots/` 的截图一致，后面每个组件都拿它对照。

### 6. 测试

- `Tests/web/scroll-hints.test.mjs`（新建）：`scrollHintState` 的边界（不能滚动、刚好差 1 像素、在顶部、在中间、在底部）；`installScrollHints` 用假的列表和观察器对象验证：滚动后 class 切换，清理之后不再响应、观察器已断开。
- `Tests/web/store.test.mjs`：四个新键存在，初始值正确。
- `Tests/web/mock.test.mjs`：跟上新的 mock 数据。
- `Tests/DesktopShellTests/BridgeTests.swift`：srcdoc 的测试改成"`about:srcdoc` 不管从哪里发起都拒绝"；其余导航测试不变。

## 允许修改的文件

- `web/index.html`、`web/styles/tokens.css`、`web/styles/base.css`、`web/js/main.js`、`web/js/store.js`、`web/js/mock.js`（修改）
- `web/styles/fonts.css`、`web/js/scroll-hints.js`（新建）
- `web/widgets/devpanel.js`、`web/widgets/devpanel.css`（删除）
- `Sources/DesktopShell/BridgeProtocol.swift`（修改：只动 `WebNavigationPolicy`）
- `Tests/web/scroll-hints.test.mjs`（新建），`Tests/web/store.test.mjs`、`Tests/web/mock.test.mjs`、`Tests/DesktopShellTests/BridgeTests.swift`（修改）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改 `docs/design/` 里的文件。
- 不加组件；`base.css` 里除了 `design.css` 那一节，不加新样式。
- 不用 CSS `backdrop-filter`；不在正式页面里放视频或效果图外壳（`mockup.css` 的内容）。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `cmp docs/design/tokens.css web/styles/tokens.css` 和 `cmp docs/design/fonts.css web/styles/fonts.css` 都没有输出
- [ ] 下面的命令没有输出（`design.css` 里 `base.css` 那一节的每一行都在 `base.css` 里）：

  ```bash
  awk -v t=web/styles/base.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | grep . | grep -Fxv -f web/styles/base.css
  ```

- [ ] `grep -rn "backdrop-filter" web/` 没有输出；`grep -rn "devpanel" web/ Sources/ Tests/` 没有输出；`grep -rn "srcdoc" web/ Sources/` 没有输出（`BridgeTests.swift` 里"拒绝 srcdoc"的测试除外）
- [ ] `scripts/test-web.sh`、`scripts/test.sh` 全部通过；`swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `git diff --name-only main...task/M4-02` 只包含"允许修改的文件"
- [ ] （Claude Code 复验）`node scripts/serve-web.mjs` 后在浏览器打开 `http://127.0.0.1:8765/`：控制台没有错误；网络请求里 5 个字体文件都是 200；`getComputedStyle(document.documentElement).getPropertyValue('--column-width')` 是 `360px`

**用户手动验证**：

- [ ] `scripts/bundle.sh --open`：桌面上只剩视频（这是预期的，组件从 M4-03 开始加回来）；访达图标照常能点、能框选、能双击打开；菜单栏各项照常

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
