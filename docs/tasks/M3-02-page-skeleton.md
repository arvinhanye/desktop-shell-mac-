# M3-02: 页面骨架（tokens、交互基线、组件注册、点击区域上报、自检面板）

- **状态**：todo
- **里程碑**：M3
- **依赖**：M3-01（必须已合并到 `main`）
- **分支**：task/M3-02

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

正式页面替换 M2 测试页：`tokens.css` 搭好变量结构（中性深色占位值），`base.css` 落实交互基线，组件通过注册机制挂载，所有卡片的矩形自动上报给 Swift 做点击穿透，安全区域写进 CSS 变量。页面上挂一个"骨架自检"调试面板组件，在浏览器（mock）和 `.app` 里都能打开。另外提供一个本地开发服务器，在浏览器里开发时也能读到 `media/`。

自检面板是 M3 的验收工具，后面几个 Swift 任务（M3-03 到 M3-06）都用它做手动验证；M4 再决定移除或只在 mock 模式下显示。

## 背景与约束

- 先读 `AGENTS.md`：核心架构、窗口要求（点击穿透、安全区域、隐藏桌面文件）、设计规范（含"桌面组件交互基线"）、开发方式。
- 本任务是**占位外观**，正式的视觉在 M3.5 定。下面给出的 token 数值照抄，**不要自己调整视觉**；组件 CSS 里不允许出现写死的颜色值或尺寸值。
- **不使用 `backdrop-filter`**（AGENTS.md 已排除）。
- 页面运行在两种环境：`.app` 里是 `shell://app/index.html`；浏览器里是开发服务器 `http://127.0.0.1:8765/`。两种环境下 `/media/...` 都能访问。
- 当前 Swift 端（M3-03 之前）的消息处理器不带回复，`getConfig` 拿不到数据；这时页面要照常显示，自检面板显示"未获取到配置"。

### 1. `web/index.html`（整体重写）和删除 `web/m2-check.js`

```html
<!doctype html>
<html lang="zh-CN" data-phase="day">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="Content-Security-Policy" content="default-src 'self' shell:; img-src 'self' shell: data:; object-src 'none'; base-uri 'none'; form-action 'none'">
  <title>DesktopShell</title>
  <link rel="stylesheet" href="styles/tokens.css">
  <link rel="stylesheet" href="styles/base.css">
  <script type="module" src="js/main.js"></script>
</head>
<body>
  <main id="desktop"></main>
</body>
</html>
```

- 页面里**不写内联脚本和内联样式**（CSP 不允许）。JS 里改样式一律用 CSSOM（`el.style.setProperty(...)`、`el.style.transform = ...`），不要用 `setAttribute('style', ...)`。
- 如果 CSP 在 WKWebView 的 `shell://` 下挡掉了正常资源（控制台出现 CSP 报错），停下来在交付记录里说明，不要自行放宽。

### 2. `web/styles/tokens.css`（照抄）

```css
/* 设计规范：所有颜色、字体、尺寸、阴影、动效只在这里定义。
   M3 为中性深色占位值，M3.5 设计定稿后替换数值。 */
:root {
  /* 文字 */
  --color-text: rgb(255 255 255 / 0.92);
  --color-text-muted: rgb(255 255 255 / 0.64);
  --color-text-faint: rgb(255 255 255 / 0.40);

  /* 强调色与状态 */
  --color-accent: rgb(160 172 196);
  --color-accent-contrast: rgb(18 20 26);
  --color-selected-bg: rgb(255 255 255 / 0.14);
  --color-selected-border: var(--color-accent);
  --color-highlight: var(--color-accent);
  --color-success: rgb(132 200 152);
  --color-warning: rgb(230 192 112);
  --color-danger: rgb(232 120 120);
  --color-focus-ring: rgb(255 255 255 / 0.80);

  /* 面板 */
  --color-card-bg: rgb(22 24 30 / 0.62);
  --color-card-bg-hover: rgb(34 37 46 / 0.70);
  --color-card-border: rgb(255 255 255 / 0.12);
  --color-panel-bg: rgb(18 20 26 / 0.92);
  --color-overlay: rgb(0 0 0 / 0.35);
  --color-shadow: rgb(0 0 0 / 0.35);
  --color-debug: rgb(255 96 96 / 0.85);

  /* 字体 */
  --font-sans: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
  --font-serif: "Songti SC", "STSong", serif;
  --font-mono: ui-monospace, "SF Mono", Menlo, monospace;
  --text-xs: 11px;
  --text-sm: 12px;
  --text-md: 14px;
  --text-lg: 16px;
  --text-xl: 20px;
  --text-2xl: 28px;
  --text-display: 48px;
  --weight-regular: 400;
  --weight-medium: 500;
  --weight-bold: 600;
  --leading-tight: 1.2;
  --leading-normal: 1.5;
  --shadow-text: 0 1px 2px rgb(0 0 0 / 0.5);

  /* 间距 */
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 20px;
  --space-6: 24px;
  --space-8: 32px;
  --space-10: 40px;

  /* 形状 */
  --radius-sm: 6px;
  --radius-md: 10px;
  --radius-lg: 16px;
  --radius-full: 9999px;
  --border-width: 1px;
  --focus-ring-width: 2px;
  --focus-ring-offset: 2px;
  --shadow-card: 0 4px 16px var(--color-shadow);
  --shadow-raised: 0 12px 32px var(--color-shadow);

  /* 布局 */
  --card-padding: var(--space-4);
  --card-gap: var(--space-3);
  --widget-gap: var(--space-4);
  --safe-top: 0px;      /* 由 main.js 按 store.safeArea 覆盖 */
  --safe-right: 0px;
  --safe-bottom: 0px;
  --safe-left: 0px;

  /* 层级 */
  --z-widgets: 1;
  --z-panel: 10;
  --z-overlay: 20;

  /* 动效 */
  --duration-fast: 120ms;
  --duration-normal: 200ms;
  --duration-slow: 400ms;
  --ease-standard: cubic-bezier(0.2, 0, 0, 1);

  /* 自检面板（M3 调试用） */
  --devpanel-width: 360px;
  --devpanel-avatar-size: 48px;
  --devpanel-spectrum-height: 40px;
}

/* 时段主题（store.phase → <html data-phase>）。
   占位：只换强调色，便于肉眼确认切换生效。M3.5 定稿后替换。 */
:root[data-phase="morning"] { --color-accent: rgb(204 184 150); }
:root[data-phase="day"]     { --color-accent: rgb(160 172 196); }
:root[data-phase="evening"] { --color-accent: rgb(204 156 160); }
:root[data-phase="night"]   { --color-accent: rgb(140 150 200); --color-card-bg: rgb(14 16 22 / 0.70); }
```

### 3. `web/styles/base.css`

base.css 和组件 CSS 一样，**只引用 token**，不写死颜色和尺寸（`0`、百分比、无单位数字和关键字可以用）。需要的规则：

- `html, body`：无外边距，宽高 100%，背景透明，`overflow: hidden`。
- `body`：`font-family: var(--font-sans)`，`color: var(--color-text)`，`font-size: var(--text-md)`，`line-height: var(--leading-normal)`，`-webkit-font-smoothing: antialiased`；`user-select: none`（同时写 `-webkit-user-select`）；`cursor: default`。
- `input, textarea, [contenteditable="true"]`：可以选中文字，`cursor: text`。
- `img, svg, video, a`：`-webkit-user-drag: none`。
- `button, [role="button"], a[href], label[for], select, summary`：`cursor: pointer`。`button` 继承字体和颜色。
- `:focus-visible`：`outline: var(--focus-ring-width) solid var(--color-focus-ring)`，`outline-offset: var(--focus-ring-offset)`。
- `#desktop`：`position: fixed`，`top/right/bottom/left` 分别取 `var(--safe-top)` 等四个变量。组件都放在它里面。
- `#desktop[data-debug-safe-area]`：用 `outline: var(--border-width) dashed var(--color-debug)` 画出安全区域（自检面板开关）。
- `.widget`：组件外壳，`position: absolute`（具体位置由各组件自己的 CSS 用 token 指定，正式布局在 M3.5 定）。
- `.card`：基础卡片——`background: var(--color-card-bg)`，`border: var(--border-width) solid var(--color-card-border)`，`border-radius: var(--radius-lg)`，`box-shadow: var(--shadow-card)`，`padding: var(--card-padding)`。
- **暂停**：`:root[data-paused] *, :root[data-paused] *::before, :root[data-paused] *::after { animation-play-state: paused !important; }`。

### 4. `web/js/widgets.js`（组件注册）

```js
export async function mountWidgets(container, names, ctx, { load } = {})
// load 默认为 name => import(new URL(`../widgets/${name}.js`, import.meta.url))
// 返回成功挂载的组件名数组
```

- 组件模块的默认导出：`{ name, css?, mount(host, ctx) }`。`name` 必须等于请求的名字；`css` 是相对 `web/widgets/` 的文件名（例如 `'devpanel.css'`）；`mount` 可以返回一个清理函数（M3 用不到，先存下来）。
- 对 `names` 里的每个名字（只允许 `/^[a-z][a-z0-9-]*$/`）：
  1. 先按顺序在 `container` 里建好外壳 `<section class="widget" data-widget="<name>">`，保证页面顺序不受加载快慢影响。
  2. 各自独立加载：动态 `import`；有 `css` 时插入 `<link rel="stylesheet">`（地址用 `new URL(\`../widgets/${css}\`, import.meta.url)`），等它 `load` 或 `error` 之后再 `mount`，避免闪一下没样式的内容。
  3. 任何一步失败（模块加载失败、默认导出不合规、`mount` 抛错）：`console.error(\`组件 ${name} 加载失败\`, error)`，移除它的外壳，**其他组件不受影响**。
- `ctx` 原样传给每个组件，内容是 `{ store, bridge, hitRegions }`。

### 5. `web/js/hit-regions.js`（点击区域上报）

```js
export function toRegions(rects, viewport)              // 纯函数，供测试
export function installHitRegions({ send, root = document, win = window })
// 返回 { schedule(), last }   last 是最近一次上报的 regions（只读）
```

- **`toRegions(rects, viewport)`**：`rects` 是 `{x, y, width, height}` 数组，`viewport` 是 `{width, height}`。
  - 丢掉任何一个值不是有限数、宽或高 ≤ 0、完全在视口外的矩形。
  - 向外取整：左上角 `floor`，右下角 `ceil`；再裁到视口 `[0, 0, width, height]` 以内。
  - 输出 `[[x, y, w, h], …]`，去掉完全相同的项，保持原顺序。
  - 超过 64 个时只保留前 64 个并 `console.warn`（Swift 端超过 64 个会整条拒绝）。
- **`installHitRegions`**：
  - 区域来源：`root.querySelectorAll('.card, [data-hit]')`，排除 `[data-hit="none"]` 和计算样式 `visibility` 不是 `visible` 的元素；`display: none` 的元素矩形为 0，会被 `toRegions` 丢掉。
  - 触发重新计算：窗口 `resize`；`ResizeObserver`（观察每个区域元素和 `documentElement`）；`MutationObserver`（`root` 的子树增删，以及 `class`、`style`、`hidden`、`data-hit` 属性变化，变化后重新收集要观察的元素）；`document` 上捕获阶段的 `transitionend`、`animationend`；`load` 和 `document.fonts.ready`；外部调用 `schedule()`。
  - 同一帧内的多次触发合并成一次（`requestAnimationFrame`）。结果和上一次上报的完全一样时不发送。
  - 发送：`send(regions)`；失败只忽略（bridge 已经打印警告）。

### 6. `web/js/main.js`（页面入口）

- 注册 `contextmenu` 监听，一律 `preventDefault()`。注册 `dragstart` 监听：目标不在 `input`、`textarea`、`[contenteditable="true"]` 里时 `preventDefault()`。
- `const bridge = createBridge(store, { target: window, now: () => performance.now() })`，**必须在第一个 `await` 之前**（保证 Swift 推送事件时 `window.shell.receive` 已经存在）。
- 根元素同步（都用 `immediate: true` 订阅）：
  - `safeArea` → `documentElement.style.setProperty('--safe-top', \`${top}px\`)` 等四个；同时调用 `hitRegions.schedule()`。
  - `phase` → `documentElement.dataset.phase`（只接受四个合法值，其他值忽略并警告）。
  - `paused` → `documentElement.toggleAttribute('data-paused', paused)`。
- `const hitRegions = installHitRegions({ send: regions => bridge.send('setHitRegions', { regions }) })`。
- 组件列表写成常量 `const WIDGETS = ['devpanel']`（M4 往里加），`await mountWidgets(document.getElementById('desktop'), WIDGETS, { store, bridge, hitRegions })`，然后 `await bridge.start()`。

### 7. `web/widgets/devpanel.js` + `devpanel.css`（骨架自检面板）

放在安全区域左上角（`top`、`left` 用 `var(--widget-gap)`，宽 `var(--devpanel-width)`，最大高度不超出安全区域，内容多时面板内部滚动），根元素是 `.card`。所有文字用中文。各部分（订阅 store 实时更新）：

1. **标题**："骨架自检"，旁边显示模式（`native` / `mock`）。
2. **状态**：`ready`、`paused`（为 `true` 时用 `--color-warning`）、`phase`、`safeArea` 四个数、当前点击区域个数（`hitRegions.last.length`）。
3. **外观**：`ui` 的三个字段；当前头像的图片（`ui.avatarId` 在 `media.avatars` 里找到时显示，尺寸 `var(--devpanel-avatar-size)`，圆形，`draggable="false"`）。
4. **系统状态**：电量、是否充电、是否用电池、CPU、内存百分比；`systemStats` 为 `null` 时显示"未收到"。
5. **律动**：12 根竖条，按 `audioSpectrum.bands` 用 `transform: scaleY(...)` 显示。用 `requestAnimationFrame` 刷新，**只在 `paused` 为 `false` 且页面可见时运行**；超过 200 毫秒没有新数据时各条衰减到 0。条的颜色用 `--color-accent`，高度 `var(--devpanel-spectrum-height)`。
6. **配置**：`ready` 之后显示。`config` 为 `null` 时显示"未获取到配置"。否则显示角色名、问候条数、头像和背景数量；每个项目一行：项目名、"Finder"按钮（`openProject`），以及该项目 `apps` 里每个应用一个"用 <应用名> 打开"按钮（`openProjectWith`）；每个应用一个"启动 <应用名>"按钮（`launchApp`）。再加按钮："随机头像"、"随机背景"（`saveUiState` 只带一个键，id 从 `media` 里随机挑）、"恢复默认外观"（`saveUiState`，两个键都传 `null`）。`saveUiState` 成功后用回复值写入 `store.ui`。
   **提醒事项**：显示 `todosAccess`、`todos` 条数，以及按 `projectId` 统计的条数（例如"desktop-shell 1 · 未关联 6"）；列出前 5 条（勾选框 + 标题 + 到期时间 + 关联的项目 id），点勾选框发送 `setTodoDone`；一个按钮"新增测试提醒"，发送 `addTodo`，`text` 为 `DesktopShell 自检 <时:分:秒>`，不带 `projectId`。按钮旁边注明"native 模式下会写入系统提醒事项的默认列表，测完请在提醒事项里删掉"。勾选和新增之后不需要自己改 store，等 `todos` 事件推送过来。
7. **非法请求自检**：一个按钮"发送非法请求"，依次发送下面 7 条并把结果列出来（预期的错误码写在括号里，结果和预期一致时打 ✓）：
   - `{action: 'deleteFile'}`（`unknown-action`）
   - `openProject`，`projectId: '../etc'`（`invalid`）
   - `openProject`，`projectId: 'desktop-shell'`，多带一个 `path: '/'`（`invalid`）
   - `launchApp`，`appId: 'no-such-app'`（`not-found`）
   - `saveUiState`，`avatarId: 'no-such-avatar'`（`not-found`）
   - `setTodoDone`，`todoId: 'no-such-todo'`，`done: true`（`not-found`）
   - 仅 native 模式：建一个隐藏的 `<iframe srcdoc="">`，用父页面的脚本调用 `iframe.contentWindow.webkit.messageHandlers.shell.postMessage({action: 'getConfig'})`，用完移除 iframe（`untrusted`，验证 Swift 拒绝子框架的消息）。mock 模式下这一条显示"跳过"。

   M3-03 之前在 `.app` 里点这个按钮，结果不符合预期是正常的。
8. **键盘输入**：一个文本输入框，占位文字"点这里测试键盘输入"（键盘焦点的 Swift 部分在 M3 之后单独处理，这里只放输入框）。
9. **时段**：四个按钮"早晨 / 白天 / 傍晚 / 夜晚"，点击写入 `store.phase`。
10. **调试开关**："显示安全区域"（切换 `#desktop` 的 `data-debug-safe-area`）、"显示点击区域"（按 `hitRegions.last` 画出每个区域的虚线框：固定定位、`pointer-events: none`、`z-index: var(--z-overlay)`、`outline` 用 `--color-debug`；区域变化时重画）。仅 mock 模式下再显示："模拟声音"（`bridge.mock.setSound`）、"模拟暂停"（`bridge.mock.setPaused`）、"模拟提醒事项未授权"（勾选时 `bridge.mock.setTodosAccess('denied')`，取消时 `'granted'`）。
11. **最近结果**：最近 6 次 bridge 调用的结果，例如"✓ launchApp safari"、"✗ openProject：unknown-action"；最近收到的事件名和时间（`audioSpectrum` 不逐条列出，只显示累计条数）。

### 8. `scripts/serve-web.mjs`（本地开发服务器）

- 运行：`node scripts/serve-web.mjs [--port 8765]`，只监听 `127.0.0.1`，启动后打印地址。不依赖任何 npm 包。
- 路由（和 `shell://` 的约定保持一致）：`/` → `web/index.html`；`/media/<path>` → 运行时素材目录（`$DESKTOPSHELL_SUPPORT_DIR/media`，没设置时用 `~/Library/Application Support/DesktopShell/media`）；`/design/<path>` → `docs/design/<path>`（M3.5 用）；其他 → `web/<path>`。
- 路径安全照 `SchemeResolver`：URL 解码后按 `/` 分段，任何一段为空或以 `.` 开头 → 404；`realpath` 之后必须仍在对应根目录之内；只返回普通文件（目录、不存在 → 404）。不列目录。
- `Content-Type` 照 `SchemeResolver.mimeType` 的表（文本类型加 `; charset=utf-8`）。
- 支持单段 `Range`（`bytes=a-b`、`bytes=a-`、`bytes=-n`）→ 206 和 `Content-Range`；无法满足 → 416；没有 `Range` → 200，带 `Accept-Ranges: bytes`。（Safari 播放 mp4/mp3 需要。）
- 只接受 `GET`、`HEAD`，其他方法 → 405。所有响应带 `Cache-Control: no-store`，改完文件刷新就能看到。

### 9. 顺带改进 M3-01 的报错日志（M3-01 审查意见）

- `web/js/store.js`：监听器抛错时 `console.error('store: listener failed', error)`，把错误对象一起打印出来，方便看到出错位置。
- `web/js/bridge.js`：忽略事件时的警告带上事件名，例如 `bridge: ignored invalid event safeArea`；事件名不是字符串时写 `?`。**只打印事件名，不打印事件内容**（`todos` 里有提醒标题）。
- 同步更新 `Tests/web/` 里断言这两条日志的测试（如果有）。这两个文件除此之外不做任何修改。

### 10. 测试

- `Tests/web/hit-regions.test.mjs`：`toRegions` 的向外取整、裁到视口、丢掉非法和视口外的矩形、去重、超过 64 个时截断并警告。

## 允许修改的文件

- `web/index.html`（重写）
- `web/m2-check.js`（删除）
- `web/styles/tokens.css`、`web/styles/base.css`（新建）
- `web/js/main.js`、`web/js/widgets.js`、`web/js/hit-regions.js`（新建）
- `web/widgets/devpanel.js`、`web/widgets/devpanel.css`（新建）
- `Tests/web/hit-regions.test.mjs`（新建）
- `web/js/store.js`、`web/js/bridge.js`、`Tests/web/store.test.mjs`、`Tests/web/bridge.test.mjs`（修改：**只限**第 9 节的两处日志）
- `scripts/serve-web.mjs`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 除第 9 节的两处日志外，不修改 `store.js`、`bridge.js`、`mock.js`（M3-01 的接口不够用时在交付记录里提出）。
- 不修改任何 Swift 文件。
- 不使用 `backdrop-filter`，不引入外部字体、图片或脚本。
- 不调整给定的 token 数值，不在组件 CSS 和 base.css 里写死颜色或尺寸。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `scripts/test-web.sh` 全部通过（含 M3-01 的测试）
- [ ] 硬编码检查没有输出：
  ```bash
  grep -nE "#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(|\b[0-9]*\.?[0-9]+(px|rem|em|vh|vw|ms|s)\b" web/styles/base.css web/widgets/*.css
  ```
- [ ] `grep -rn "backdrop-filter" web/` 没有输出；`grep -rnE "<script>|style=" web/index.html` 没有输出
- [ ] `git diff --name-only main...task/M3-02` 只包含"允许修改的文件"，`web/m2-check.js` 已删除
- [ ] 开发服务器（先运行 `node scripts/serve-web.mjs`）：
  - `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8765/` → `200`
  - `curl -sI http://127.0.0.1:8765/js/main.js | grep -i content-type` → `text/javascript; charset=utf-8`
  - `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8765/media/avatars/1.png` → `200`
  - `curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8765/media/..%2fconfig.json'` → `404`
  - `curl -s --path-as-is -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8765/../AGENTS.md'` → `404`
  - `curl -s -D - -o /dev/null -H 'Range: bytes=0-99' http://127.0.0.1:8765/media/video/aemeath.mp4 | grep -iE '^HTTP|content-range'` → `206` 和 `bytes 0-99/<文件大小>`
  - `curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8765/` → `405`
- [ ] 浏览器打开 `http://127.0.0.1:8765/`：控制台没有错误；自检面板显示 `mock`、`ready = true`、角色名"爱弥斯"、头像 30、背景 63、`safeArea` 为 25 / 0 / 80 / 0；`systemStats` 每 5 秒变化；律动条在动
- [ ] 浏览器里点"模拟暂停"：`<html>` 带上 `data-paused`，律动条停住并回到 0；再点一次恢复
- [ ] 浏览器里的提醒事项：显示 `granted`、5 条；点第一条的勾选框，它的勾选状态马上变化；点"新增测试提醒"，条数变成 6；勾"模拟提醒事项未授权"，显示 `denied`、0 条，这时点"新增测试提醒"结果栏显示 `failed`；取消勾选后恢复
- [ ] 浏览器里点"发送非法请求"：前 6 条全部 ✓，第 7 条显示"跳过"
- [ ] 浏览器控制台执行下面的代码，控制台出现一条"组件 no-such-widget 加载失败"，自检面板仍在：
  ```js
  const { mountWidgets } = await import('/js/widgets.js');
  await mountWidgets(document.getElementById('desktop'), ['no-such-widget'], {});
  ```
- [ ] `scripts/bundle.sh` 打包成功，`build/DesktopShell.app/Contents/Resources/web/` 里有新页面的全部文件，没有 `m2-check.js`，也没有 `Tests/`

**用户手动验证**：

- [ ] 用 **Safari** 打开 `http://127.0.0.1:8765/`（先运行 `node scripts/serve-web.mjs`）：
  - 自检面板在左上角，数据和上面描述的一致；点"早晨 / 白天 / 傍晚 / 夜晚"，律动条的颜色跟着变（占位主题只换强调色）
  - 勾"显示安全区域"：出现红色虚线框，上边离顶部 25、下边离底部 80；勾"显示点击区域"：自检面板外面套一个红色虚线框
  - 在面板上右键不弹菜单；拖动选择面板上的文字选不中；头像图片拖不动；输入框里的文字可以选中
- [ ] 运行 `scripts/bundle.sh --open`（此时 Swift 还没有 M3-03）：
  - 自检面板显示 `native`、"未获取到配置"（预期，M3-03 之后才有数据）；面板可能被菜单栏挡住一点（预期，安全区域推送在 M3-05）
  - 面板上的按钮、勾选框都能点；点面板外的空白处，能正常选中、框选、双击打开访达桌面图标；从面板外框选经过面板不会被打断
  - 在面板上和空白处右键：面板上不弹菜单，空白处弹出的是访达的桌面菜单
  - 菜单栏"隐藏桌面文件"后，空白处单击、右键都没有反应，面板照常可用

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
