# M8-04: 终端页 terminal.html 和 xterm.js（网页）

- **状态**：todo
- **里程碑**：M8
- **依赖**：M8-01（用到同步后的 `web/styles/tokens.css` 里的终端 token 和 `base.css` 的 `.key-hint`）。和 M8-02、M8-03 互不依赖；M8-05 依赖本任务
- **分支**：task/M8-04

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

新建终端面板里加载的页面 `web/terminal.html`：照定稿画出标题栏和终端区，用 xterm.js 显示终端，按 AGENTS.md 的"终端页"动作和事件和 Swift 通信。在普通浏览器里打开时用一个回显的假终端，方便调样式。

在应用里真正跑起来要等 M8-05。

## 背景与约束

- 先读：
  - AGENTS.md：Bridge 接口里"终端页 → Swift""Swift → 终端页""终端会话"三块，"安全要求"里终端页的几条，"技术探针"的终端面板探针（xterm.js 一段）；
  - `docs/design/README.md` 开头"M8 改版"一节。
- 定稿：
  - `docs/design/index.html` 里 `.terminal-panel` 那一块就是本页面的全部 DOM（外面的 `.mock-terminal-window` 不是）；
  - 放大 / 还原、收起按钮的图标照 `mockup.js` 里的 `MAX_ICON` / `RESTORE_ICON` 和 `index.html` 里收起按钮的 SVG；
  - 样式是 `design.css` 的 `web/terminal/terminal.css` 一节；
  - `mockup.css` 里 `.mock-xterm` 那几条是效果图用的，不要抄。
- **Codex 不自行做视觉决定**。

### 1. 第三方文件（`web/vendor/`）

原样下载，不改内容：

| 放到 | 来源 | SHA-256 |
|---|---|---|
| `web/vendor/xterm/xterm.js` | `https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/lib/xterm.js` | `1f991ac3b4b283ebf96e60ae23a00a52765dd3a2e46fa6fdda9f1aab032f7495` |
| `web/vendor/xterm/xterm.css` | `https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.css` | `ba8e6985669488981ccf40c0cefe3aba80722cb6c92de7ad628b0bd717faf2b6` |
| `web/vendor/xterm/LICENSE` | `https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/LICENSE` | `b569f629d00f2626a8100df2a1798210535621e42164dfd426a6fe5aac7b0ccd` |
| `web/vendor/xterm-addon-fit/addon-fit.js` | `https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.js` | `bdaefa370b1bfc42ee88d46fe6072400902a4d4b2d45cd93438dda9b23c97089` |
| `web/vendor/xterm-addon-fit/LICENSE` | `https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/LICENSE` | `e256f01188af527e4d06d21d06fbf785ae9c50d4b328bf03cbe0ba7f0aa4228f` |

下载不了（没有网络）就停下，在交付记录里说明，由 Claude Code 放进来。

### 2. 页面（`web/terminal.html`）

- **CSP**：`xterm.js` 要动态插入 `<style>`，所以比 `index.html` 多放宽一项：

  ```
  default-src 'self' shell:; style-src 'self' shell: 'unsafe-inline'; img-src 'self' shell: data:; object-src 'none'; base-uri 'none'; form-action 'none'
  ```

  如果 xterm 还要别的放宽，停下来在交付记录里说明。
- **引用顺序**：
  - 样式：`styles/tokens.css`、`styles/fonts.css`、`styles/base.css`、`vendor/xterm/xterm.css`、`terminal/terminal.css`；
  - 脚本：`vendor/xterm/xterm.js`、`vendor/xterm-addon-fit/addon-fit.js` 两个普通脚本（它们把 `Terminal`、`FitAddon` 挂在全局），然后是 `<script type="module" src="terminal/terminal.js">`。
- **body** 里只有 `.terminal-panel`，DOM 照定稿：
  - `.terminal-meta` 初始为空；
  - `kbd.key-hint` 初始为空，并设 `hidden`；
  - 放大按钮初始是"放大"的图标、`title` 和 `aria-label`。
- `terminal.css` 照抄 `design.css` 的 `web/terminal/terminal.css` 一节。
- 和桌面页一样禁用右键菜单（`contextmenu` 事件 `preventDefault`）。不引用 `keyboard-focus.js`、`hit-regions.js`、`glass-regions.js`：面板整块接收鼠标、整块垫毛玻璃，键盘由 Swift 管。

### 3. 脚本（`web/terminal/terminal.js`）

可测试的部分写成导出的纯函数。

- **xterm 的设置从 tokens 读**（用 `getComputedStyle(document.documentElement)` 读 CSS 变量）：
  - `fontFamily` ← `--font-mono`；
  - `fontSize` ← `--terminal-font-size` 的数值；
  - `lineHeight` ← `--terminal-line-height`；
  - `theme`：`background: 'rgba(0,0,0,0)'`，`foreground` ← `--terminal-fg`，`cursor` ← `--terminal-cursor`，`cursorAccent` ← `--terminal-cursor-text`，`selectionBackground` ← `--terminal-selection`，16 个 ANSI 颜色 ← `--ansi-*`（`black` … `brightWhite`）；
  - 另外：`allowTransparency: true`、`cursorBlink: true`、`scrollback: 5000`。
  - 写一个纯函数：输入一个"按变量名取值"的函数，输出 xterm 的设置，单独测试。
- 用 FitAddon 让终端铺满 `.terminal-screen`：页面尺寸变化（`ResizeObserver`）时重新 `fit()`。
- **发给 Swift**：`window.webkit.messageHandlers.shell.postMessage({action, …})`，和桌面页同一个名字，失败都要接住。
  - 第一次 `fit()` 以后：`terminalReady {cols, rows}`，只发一次；
  - `term.onData`：`terminalInput {data}`。超过 65536 个字符的内容分成几段依次发送，不要截断；
  - `term.onResize`：`terminalResize {cols, rows}`，尺寸真的变了才发；
  - 放大按钮：`toggleTerminalMaximize`。按钮的样子以收到的 `terminalState.maximized` 为准，不自己猜；
  - 收起按钮：`hideTerminal`。
- **收 Swift 的事件**：定义 `window.shell.receive(event)`，按 `event.event` 分发；不认识的事件、字段类型不对的事件，丢弃并 `console.warn`。
  - `terminalOutput`：把 base64 的 `data` 转成 `Uint8Array` 交给 `term.write`，不要先转成字符串（UTF-8 字符可能被切在两块之间）；
  - `terminalExited`：写一行 `\r\n\x1b[2m[shell 已退出，按任意键重新开始]\x1b[0m\r\n`，`.terminal-meta` 恢复成 shell 名；
  - `terminalState`：
    - `hotkey` 写进 `kbd`，非空字符串时显示；
    - `shell` 记下来，作为标题的默认值；
    - `maximized` 决定按钮的图标、`title` 和 `aria-label`（"放大" / "还原"）；
    - `visible` 从 `false` 变成 `true` 时 `term.focus()`，变成 `false` 时 `term.blur()`。
- **标题**：`term.onTitleChange` 收到非空标题时显示在 `.terminal-meta`，空标题时显示 shell 名。
- **在普通浏览器里**（没有 `window.webkit?.messageHandlers?.shell`）：
  - 不发消息，换成一个假终端：打一行暗色的"浏览器预览：没有真实的 shell，输入会原样显示"，再打一个 `$ ` 提示符；
  - 输入原样回显，回车换行后再打 `$ `，退格删一个字符；
  - 按钮在本地切换放大的样子，收起按钮只打一行 `console.info`；
  - `terminalState` 当作收到 `{visible: true, maximized: false, hotkey: '⌥`', shell: 'zsh'}`。
  - 方便用 `node scripts/serve-web.mjs` 打开 `http://127.0.0.1:8765/terminal.html` 调样式。

### 4. 测试（`Tests/web/terminal-page.test.mjs`，新建）

不依赖真的 xterm，用假的 term 对象。至少覆盖：

- tokens → xterm 设置；
- base64 → 字节，包括被切开的多字节字符；
- `terminalReady` 只发一次；
- 超长输入分段；
- 每个事件的处理，以及丢弃格式不对的事件；
- `visible` 变化时的聚焦和失焦；
- 标题的默认值和恢复；
- 浏览器模式下的回显。

## 允许修改的文件

- `web/terminal.html`、`web/terminal/terminal.js`、`web/terminal/terminal.css`（新建）
- `web/vendor/xterm/xterm.js`、`web/vendor/xterm/xterm.css`、`web/vendor/xterm/LICENSE`、`web/vendor/xterm-addon-fit/addon-fit.js`、`web/vendor/xterm-addon-fit/LICENSE`（新建，原样下载）
- `Tests/web/terminal-page.test.mjs`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改 `web/index.html`、桌面页的组件和 `web/js/` 里的文件；终端页不引用 `bridge.js`、`store.js`。
- 不修改 `web/vendor/` 里的第三方文件。
- 不从网络加载任何东西（第三方文件都在本地）。
- 不在页面里打印终端内容到控制台。

## 验收标准

**可执行的检查**（实现者自测，审查者复验）：

- [ ] `scripts/test-web.sh` 全部通过，其中有 `terminal-page.test.mjs`
- [ ] `shasum -a 256 web/vendor/xterm/* web/vendor/xterm-addon-fit/*` 和上表一致
- [ ] 下面这条命令没有输出：

  ```bash
  awk -v t=web/terminal/terminal.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | grep -v '^   ' | diff -B - web/terminal/terminal.css
  ```

  （定稿那一节开头有三行缩进的说明注释，比较时去掉。）
- [ ] `grep -n "http" web/terminal.html web/terminal/terminal.js` 没有输出
- [ ] `git diff --name-only main...task/M8-04` 只有上面"允许修改的文件"
- [ ] （审查者复验）`node scripts/serve-web.mjs`，Safari 打开 `http://127.0.0.1:8765/terminal.html`，窗口拉到大约 1760 × 450：
  - 标题栏和效果图（`/design/index.html` 打开终端）一致：图标、"终端"、`zsh`、`⌥``、放大和收起按钮；
  - 输入中英文都能回显，中文占两格；
  - 点放大，图标换成还原；
  - Web 检查器的控制台没有错误，也没有 CSP 报错。

**用户手动验证**：本任务没有，并到 M8-05。

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
