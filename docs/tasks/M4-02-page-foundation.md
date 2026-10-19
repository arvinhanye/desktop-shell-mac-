# M4-02: 页面基础：定稿 token、字体、底板样式和滚动淡出

- **状态**：review
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

- **改动摘要**：基于已合并 M4-01 的 `main`（`ec42673`）在 `task/M4-02` 实现。原样同步定稿 token、5 个字体声明和基础卡片/滚动淡出样式；保留其余基础规则及 CSP。新增 4 个共享状态键与可清理的 `scroll-hints`；移除自检面板，组件列表留空；导航仅允许 `shell` scheme。mock 对齐效果图的 6 个项目、7 个应用（含无图标 Figma）、13 条提醒及初始外观，保留用户/角色/问候/素材和动作、事件行为。
- **RED → GREEN**：修改前网页 158/158、Swift 161/161 通过。先补测试，确认网页 21 个预期失败（新状态、滚动提示、mock 数据），原 srcdoc 例外导致导航专项 1 个预期失败；定稿 token 比对失败、字体文件尚不存在。完成实现后网页 177/177、Swift 161/161（18 suites）通过，0 跳过。覆盖 1px 容差、上下越界滚动、被动监听、尺寸/子节点变化、重复清理及已排队回调、日期跨年和新增提醒 id 唯一性。
- **自动检查**：`scripts/test-web.sh`、`scripts/test.sh`、`swift build` 成功；构建日志无 warning/error。两个 `cmp` 无输出；任务单 `awk | grep` 无遗漏行；禁止项 `backdrop-filter` / `devpanel` / `srcdoc` 的三个 grep 均无匹配；`git diff --check` 通过。共 17 个改动文件，均在任务范围及下述单行例外内；额外检查确认原 base.css 非 card 规则、Swift 非导航代码、任务需求部分不变。
- **浏览器自测**：使用隔离端口 `127.0.0.1:18765`，正式首页空白、`#desktop` 无子组件；控制台 error/warn 均为 0；样式加载顺序 fonts → tokens → base，`--column-width` 为 `360px`。5 个字体 URL 逐个 HTTP GET 均返回 200 且非空。空白页面没有使用字体的文本，浏览器会按需请求字体；这里验证的是正式页声明/资源可访问性，不将 HTTP 检查冒充该页自动发起了 5 个字体请求，实际使用字体后的浏览器网络复验留给审查。
- **待人工验收**：运行 `scripts/bundle.sh --open`，确认桌面只剩视频；访达图标可点选、框选、双击；菜单栏各项正常。此轮未启动正式 `.app`，未操作提醒事项权限或真实数据，浏览器/单元测试不替代桌面验收。
- **疑问 / 偏离**：任务单漏列 `Tests/web/bridge.test.mjs`；用户已明确批准仅把第 147 行的提醒数量断言从 5 更新为 13，已精确按此执行，其他内容不变。任务需求及审查记录保持原样。
- **独立复核**：只读复核覆盖全部 17 个改动文件，未发现高/中严重性问题；复核者独立重跑网页 177/177，并核对样式精确同步、单行范围例外、清理生命周期及 RED/GREEN 证据。此记录为实现侧自查，不代替 Claude Code 的正式审查。
- **验证日志**：`/tmp/desktopshell-m4-02-check/` 保存 baseline、red、green、build 和字体 HTTP 结果（临时本机证据，不入 git）。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**代码审查通过，自动验收全部通过，待用户手动验证**（见最后一项）。用户确认后合并到 `main`。
- **复验结果**（Claude Code，2026-10-18，在 `5474cbe` 的独立检出上执行；打包在主目录的同一提交上执行）：
  - [x] `cmp` 两个文件都没有输出；`design.css` 里 `base.css` 那一节的每一行都在 `base.css` 里
  - [x] `backdrop-filter`、`devpanel`（`web/ Sources/ Tests/`）、`srcdoc`（`web/ Sources/`）三个 `grep` 都没有输出
  - [x] `swift build` 零警告零错误；`scripts/test.sh` 161 项、`scripts/test-web.sh` 177 项全部通过；`git diff --check` 通过
  - [x] 改动 17 个文件，除 `Tests/web/bridge.test.mjs` 外都在"允许修改的文件"里（见下）
  - [x] 内置浏览器打开 `http://127.0.0.1:8765/`：控制台没有任何输出；样式表顺序 `fonts.css → tokens.css → base.css`；`--column-width` 是 `360px`，`--card-fill-opacity` 是 `1`，没有 `data-glass`；`#desktop` 里没有组件。空白页本身不会请求字体，所以用 `document.fonts.load` 逐个触发：5 个字体都是 `loaded`，网络请求 5 个都是 200
  - [x] 在同一个页面里对真实 DOM 试了 `installScrollHints`：空列表没有 class；内容超出后 `more-below`；滚到中间两个都有；到底只剩 `more-above`；`-webkit-mask-image` 生效；清理后再滚动，class 不再变化
  - [x] `scripts/bundle.sh --open`：日志正常（`icons: exported=2/2`、`reminders: access=granted`、`getConfig … voices=54 icons=2`），没有导航被拦的记录
- **意见**：
  - 样式、token、字体原样复制；`base.css` 只删了旧 `.card`、追加定稿那一节，其他规则没动。
  - `WebNavigationPolicy` 只剩"scheme 是 `shell` 就放行"，srcdoc 测试改成在所有来源、目标框架组合下都拒绝。`allows` 的另外三个参数现在用不到，按任务单不动调用方，保留无妨。
  - `scroll-hints.js` 的 `MutationObserver` 多观察了 `subtree`（任务单只要求 `childList`），只会多触发几次判断，无害。注意它只观察列表本身的尺寸：列表里的内容因为字体加载而变高时不会重新判断，要等下一次滚动或增删节点。目前影响很小，M4-04、M4-05 的浏览器检查里留意一下。
  - mock 数据和效果图 `mockup.js` 完全一致（没装的应用沿用效果图的 id `missing`，任务单写的是"没装的 Figma"，接受）。
  - **范围例外**：`Tests/web/bridge.test.mjs` 的提醒条数从 5 改成 13。这是任务单漏列的文件（mock 换数据必然影响它），用户已同意，只改了这一行，接受。
- **待用户手动验证**：
  - [ ] 现在桌面上运行的就是这一版：桌面只剩视频（组件从 M4-03 起加回来）；访达图标能点、能框选、能双击打开；菜单栏各项照常
