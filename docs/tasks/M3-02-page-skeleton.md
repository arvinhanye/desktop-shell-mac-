# M3-02: 页面骨架（tokens、交互基线、组件注册、点击区域上报、自检面板）

- **状态**：changes-requested
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

### 11. 审查后补充：空闲时不做多余的工作（2026-10-17）

审查时实测发现两处在没有变化时仍然按帧率干活的地方（详见"审查记录"）。项目在 Intel Mac 上常驻桌面，要求省电，这两处都要改：

1. **点击区域只在可能影响组件矩形的变化时重新计算**（`hit-regions.js`）。现在 `MutationObserver` 监听整个页面所有元素的 `style` / `class` 变化，律动条每一帧改 `transform` 都会触发一次重新计算。改为先过滤变化记录，抽成纯函数并导出供测试：

   ```js
   export function affectsHitRegions(records, selector = '.card, [data-hit]')
   ```

   - 属性变化：只有目标元素本身匹配 `selector`，或者它的子孙里有匹配 `selector` 的元素（例如组件外壳、`#desktop`），才算有影响。区域元素**内部**元素的变化不算：它们如果改变了区域元素的尺寸，`ResizeObserver` 会捕获。
   - 子节点增删：增加或删除的节点里，有元素本身匹配 `selector` 或者包含匹配的元素，才算有影响。只换文字、或增删不含区域元素的节点（例如结果列表、点击区域的调试虚线框）不算。
   - 其余触发（`resize`、`load`、`transitionend`、`animationend`、字体加载、外部 `schedule()`）保持不变。
   - 在 `Tests/web/hit-regions.test.mjs` 里用假的变化记录测试 `affectsHitRegions`：区域元素自身的 `style` 变化 → 有影响；区域元素内部的 `style` 变化 → 没有；区域元素祖先的 `class` 变化 → 有；增加一个 `.card` → 有；增加一个包含 `.card` 的外壳 → 有；删除一个 `.card` → 有；只增删文字或普通元素 → 没有。

2. **律动条没有东西要画时停止动画循环**（`devpanel.js`）。现在只要没暂停、页面可见，`requestAnimationFrame` 就一直按帧率运行，没有声音时也一样。在 `.app` 里，M5.5 之前根本没有 `audioSpectrum`，这个循环会永远空转。改为：
   - 收到新的 `audioSpectrum`（订阅 store）、没有暂停、页面可见时，才启动循环。
   - 各条衰减到 0（最后一份数据超过 400 毫秒）之后，画完这一帧就**不再**请求下一帧。
   - `drawDiagnostics` 不再每帧调用，只在 `scheduleDiagnostics` 里调用。"audioSpectrum 累计"的文字在收到事件时用 `scheduleDiagnostics` 合并到下一帧更新。
   - 暂停和页面隐藏时的行为不变（立刻归零、不运行循环）。

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
- [ ] **（审查后补充）** 浏览器里打开页面，**保持页面在前台可见**，控制台执行下面的代码。预期 `withSound.hitRegions` 不超过 2（修改前约 28），`silent.raf` 和 `silent.hitRegions` 都不超过 1（修改前 `raf` 约 60）：
  ```js
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  let frames = 0, collects = 0;
  const raf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = cb => { frames++; return raf(cb); };
  const qsa = Document.prototype.querySelectorAll;
  Document.prototype.querySelectorAll = function (s) { if (s === '.card, [data-hit]') collects++; return qsa.call(this, s); };
  const rate = async () => { const f = frames, c = collects; await sleep(2000); return { raf: (frames - f) / 2, hitRegions: (collects - c) / 2 }; };
  const sound = [...document.querySelectorAll('label')].find(l => l.textContent === '模拟声音').querySelector('input');
  const withSound = await rate();
  sound.click(); await sleep(1000);
  const silent = await rate();
  sound.click();
  ({ withSound, silent })
  ```
- [ ] **（审查后补充）** 上面的代码跑完、重新勾上"模拟声音"后，律动条马上恢复跳动；"模拟暂停"时仍然立刻归零

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
  - 从已合并 M3-01 的 `main`（`27f5619`）创建 `task/M3-02`。替换 M2 测试页，逐字采用本任务的 HTML/CSP 和 token 数值，删除 `m2-check.js`。
  - 新增交互基线、组件独立加载/失败隔离、每帧合并和去重的点击区域上报、安全区域/时段/暂停状态同步；补齐可见性仅由 CSS 改变时的重新计算。
  - 自检面板接入配置、外观、系统状态、12 频段律动、提醒事项、非法请求、输入框和调试开关。暂停或页面隐藏时停止律动 RAF；无新频谱超过 200ms 后衰减至零。结果与事件日志各保留最近 6 条，音频事件仅累计计数。
  - 新增仅监听 `127.0.0.1` 的零依赖开发服务器：web/media/design 路由、解码路径检查、realpath 根目录约束、普通文件限制、MIME、GET/HEAD、单段 Range 和 no-store。
  - 完成指定日志改进；经用户追加授权，另增加 `bridge.subscribeEvents(listener)`：只回调事件名，覆盖 native 和 mock 的实际 receive，不把 getConfig/saveUiState 回复或本地状态写入当作推送；监听器独立取消，异常隔离，不暴露事件内容。
- **自测结果**：
  - **PASS** `scripts/test-web.sh`：134/134，0 FAIL、0 SKIP。RED→GREEN 已分别验证日志断言、点击区域模块、CSS visibility 变化和事件观察接口；最终回归全部通过。
  - **PASS** `scripts/test.sh`：76/76（9 suites），0 FAIL。
  - **PASS** 任务要求的三项 grep 检查均无输出；HTML 与 tokens.css 和任务代码块逐字一致；`git diff --check` 无输出。无 Swift、mock、AGENTS.md、CLAUDE.md 或其他任务文件修改。
  - **PASS** 任务列出的 7 个 curl 检查：首页 200，JS 为 `text/javascript; charset=utf-8`，头像 200，两项目录穿越 404，视频 Range 为 206 / `bytes 0-99/14515867`，POST 为 405。
  - **PASS** 临时 Node 集成测试 3/3：服务器真实 HTTP 路由、编码穿越、符号链接逃逸、HEAD、Range/416/空文件；组件顺序、CSS 等待、清理函数保存、模块/导出/mount 失败隔离。测试和日志位于 `/tmp/ds-m3-02-validation/`，未新增 npm 依赖或扩大仓库文件范围。
  - **PASS** Chrome 实页：控制台 error 为空；mock、ready、角色/素材数量、安全区域符合预期；系统状态持续更新；暂停后 data-paused 生效且 12 条归零，恢复后重新律动，关闭声音后归零；提醒勾选、新增至 6 条、denied 清空与 failed 提示、恢复授权均验证；非法请求前 6 条全部 ✓，子框架项跳过；头像加载、时段变量、调试框、输入框验证通过。
  - **PASS** `scripts/bundle.sh`：release 构建、固定证书签名及 designated requirement 验证通过；产物 `build/DesktopShell.app` 的 web 资源齐全，无 `m2-check.js`、无 `Tests/`。
  - **PASS** 临时原生 WKWebView 集成程序使用实际 `ShellSchemeHandler` / `SchemeResolver` 和最终打包资源：`shell://app/index.html` 加载成功，三份样式加载，native / ready / 未获取到配置正确，面板宽 360、点击区域 1，CSP violation 为 0。旧式无回复处理器产生预期的 getConfig 错误日志。真实模块导入失败只记录一条“组件 no-such-widget 加载失败”，失败外壳移除、自检面板保留；合成事件验证右键和非输入区域拖拽被阻止，输入区域拖拽保留。
  - **待手动验证**：任务单列出的 Safari 目测、文字/图片真实拖拽，以及正式 `.app` 中 Finder 桌面点击穿透、框选、右键、隐藏桌面文件菜单交互。原生集成程序与合成事件不替代这些实际 GUI 验收。
- **疑问 / 偏离**：
  - 用户于本轮明确回复“允许补事件观察接口和测试”，因此 `bridge.js` / `bridge.test.mjs` 除指定日志外增加上述只传事件名的观察接口及 3 项测试；任务需求区保持原文。事件记录含重复收到的事件，即使对应 store 值未变化；非字符串事件名记为 `?`，不代表该事件通过数据校验。
  - 临时 HTTP 测试首次监听端口受沙箱限制，按权限流程重跑通过；临时原生程序首次编译的 MainActor 入口错误已修正后重跑通过。两者均非产品失败，未降低检查条件。
  - 独立只读复核发现的两项问题（CSS 可见性缓存、事件与状态混淆）均已建立失败测试并修正；没有遗留实现问题。Safari/Finder 手动门禁保留，未计作通过。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

### 第一轮（Claude Code，2026-10-17）

- **结论**：**需修改**（两处空闲时的多余工作，见下）。其余部分通过；Safari 和 `.app` 的手动验证等修改完再一起做。
- **复验结果**（在 `origin/task/M3-02` 的独立检出上执行）：
  - [x] `scripts/test-web.sh`：134 项全部通过
  - [x] 硬编码检查、`backdrop-filter`、内联脚本和样式检查都没有输出；`git diff --check` 通过
  - [x] 改动文件都在允许范围内（`bridge.js` 的 `subscribeEvents` 是你在 Codex 那边授权追加的，见下），`web/m2-check.js` 已删除
  - [x] `tokens.css` 与任务单代码块**逐字一致**（脚本比对）
  - [x] 开发服务器 7 项 curl 检查全部符合预期；另外 `/.git/config`、`/media/avatars/`（目录）、错误的百分号编码都是 404，超出范围的 `Range` 是 416，只监听 `127.0.0.1`，带 `Cache-Control: no-store`
  - [x] 内置浏览器（mock）：控制台没有错误；`mock`、`ready = true`、爱弥斯、问候 7 条、头像 30、背景 63、安全区域 25 / 0 / 80 / 0；非法请求前 6 条 ✓、第 7 条跳过；模拟暂停时 `<html data-paused>` 且律动条归零，取消后恢复；提醒事项勾选、新增后 6 条、未授权时 `denied · 0 条` 且新增返回 `failed`、恢复授权正常；切到"夜晚"后 `data-phase="night"`、强调色 `rgb(140 150 200)`；`mountWidgets` 加载不存在的组件只报一条"组件 no-such-widget 加载失败"、不留外壳、面板仍在；`--safe-top` / `--safe-bottom` 为 `25px` / `80px`
  - [x] `scripts/bundle.sh` 打包、签名通过，`Resources/web/` 里 11 个文件齐全，没有 `m2-check.js` 和 `Tests/`
- **需修改的两处**（已写进第 11 节和验收标准；根源在我写的任务单，不是实现失误：任务单要求 `MutationObserver` 监听 `style`，也没要求律动循环空闲时停下）：
  1. **点击区域每帧重新计算**：mock 有声音时，实测 `collect()`（`querySelectorAll` + 每个区域元素的 `getComputedStyle` 和 `getBoundingClientRect`）每秒约 **28 次**，没声音时约 0.5 次。原因是律动条每帧改 `style.transform`，被全页面的 `MutationObserver` 捕获。M4 的律动组件会一直这样改样式，所以要在骨架这一层修掉。
  2. **律动循环空转**：mock 关掉声音后，自检面板的 `requestAnimationFrame` 仍然每秒约 **60 次**。`.app` 里 M5.5 之前没有频谱数据，这个循环会一直空转。
- **其他意见**：
  - `bridge.subscribeEvents` 只回调事件名、不暴露内容、监听器出错互不影响，设计合适，接受。它是网页内部接口，不影响 Bridge 白名单。
  - 日志改进（M3-01 审查意见）已按要求完成。
  - 开发服务器的路径检查和 `SchemeResolver` 同一套规则（解码后逐段检查、`realpath` 后确认仍在根目录内、只返回普通文件），Range 用 `BigInt` 处理大数，读流在客户端断开时会关闭。
  - 组件注册按顺序先建外壳、各自独立加载、等样式加载完再挂载，失败时移除外壳，符合要求。
  - **写进 M4 的要求**：律动组件和其他有持续动画的组件，都要做到"没有东西要画时停止循环"，不能只在暂停时停。
