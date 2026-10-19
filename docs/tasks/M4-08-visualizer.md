# M4-08: 音频律动

- **状态**：review
- **里程碑**：M4
- **依赖**：M4-07（必须已合并到 `main`）
- **分支**：task/M4-08

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

桌面底部中间偏右显示冰晶心形装饰条，两侧各 12 根冰蓝色柱子跟着 `audioSpectrum` 跳动；没有声音、暂停时柱子落回静止高度。这一步只接 mock 的频谱，Swift 端的系统音频捕获在 M5.5 做，所以在应用里柱子暂时是静止的。

## 背景与约束

- 先读 `docs/design/README.md` 的"组件的共同写法"。照着做的部分：`index.html` 里 `visualizer` 一节；`design.css` 里 `visualizer.css` 一节；`mockup.js` 的律动条部分（只看结构，它的频谱是自己编的，正式组件不编数据）。
- AGENTS.md：组件清单第 8 条；推送事件 `audioSpectrum`（有声音时约 30 次/秒，静音或暂停时不推送）；联动规则表"`paused` 变化"一行。`bridge.js` 在暂停时会把 `store.audioSpectrum` 设成 `null`，暂停期间收到的频谱也会丢掉。
- M3-02 审查记录写给 M4 的要求：没有东西要画时停下循环（不只是暂停时）；同一帧的更新合并在一个 `requestAnimationFrame` 里。M3.5 探针实测：60 帧/秒空转时网页进程约 13%、WindowServer 再多约 10%，所以只在收到新频谱时才画。
- 律动条只是装饰：不加 `.card`、不加 `data-hit`（`design.css` 里已经是 `pointer-events: none`），`host` 上设 `aria-hidden="true"`。

### 1. 显示（`web/widgets/visualizer.js`、`visualizer.css`）

- DOM 照 `index.html`：`.viz-bars.left`（12 个 `span`）+ `.viz-bars.right`（12 个 `span`）+ `img.viz-ornament`（`src="/media/ornaments/heart.png"`、`alt=""`、`draggable="false"`）。
- 两侧共用同一组 `bands`：第 `i` 个频段对应两侧各自的第 `i` 个 `span`。左侧是 `row-reverse`，所以两侧的低频都在靠近心形的一边。
- 柱子高度：`span.style.transform = scaleY(<值>)`，值是 `max(band, 静止高度)`。静止高度在 `mount` 时从 CSS 变量 `--viz-bar-rest` 读一次（`getComputedStyle(document.documentElement)`）。
- 归零：删掉行内的 `transform`（`style.removeProperty('transform')`），回到 CSS 里的静止高度。

### 2. 什么时候画

- 订阅 `audioSpectrum` 和 `paused`。
- 收到新的频谱：如果这一帧还没排过，就排一个 `requestAnimationFrame`，在里面用**最新**的那组数据写 24 根柱子；一帧只写一次。
- 静音：Swift 静音时不推送。每次收到频谱后重设一个 250 毫秒的一次性定时器，到点还没有新数据就归零。
- `paused` 变成真，或者 `audioSpectrum` 变成 `null`：立刻归零，取消排着的帧和定时器。
- 除此之外没有任何循环：没有数据进来时，既没有 `requestAnimationFrame` 也没有定时器在跑。
- 把这些写成可测试的 `createVisualizer({ bars, raf, cancelRaf, setTimer, clearTimer, rest })` 之类的形式，`mount` 里传入真实的实现。
- 清理函数：取消帧和定时器，退订。

### 3. 接入

- `main.js` 的 `WIDGETS` 加上 `'visualizer'`。

### 4. 测试（`Tests/web/visualizer.test.mjs`）

用假的 `raf` 和定时器：

- 一帧内连着来 3 组频谱，只排了一次帧，写进去的是最后一组。
- 值的处理：低于静止高度的用静止高度；两侧同一位置的值相同。
- 最后一组数据之后 250 毫秒归零，并且之后没有任何排着的帧或定时器。
- `paused` 为真、`audioSpectrum` 为 `null` 时立刻归零。
- 清理之后再推频谱，不再排帧。

## 允许修改的文件

- `web/widgets/visualizer.js`、`web/widgets/visualizer.css`（新建）
- `web/js/main.js`（只改 `WIDGETS`）
- `Tests/web/visualizer.test.mjs`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 组件自己不产生频谱数据（mock 已经会推送），不做 M5.5 的系统音频捕获。
- 不用持续运行的 `requestAnimationFrame` 循环或 `setInterval`。
- 组件 CSS 和 `design.css` 对应的一节不一致。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `scripts/test-web.sh` 全部通过，包含上面列出的新测试
- [ ] 下面的命令没有输出：

  ```bash
  awk -v t=web/widgets/visualizer.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/visualizer.css
  ```

- [ ] `grep -n "setInterval" web/widgets/visualizer.js` 没有输出
- [ ] `git diff --name-only main...task/M4-08` 只包含"允许修改的文件"
- [ ] （Claude Code 复验）浏览器打开 `http://127.0.0.1:8765/`（mock 每 33 毫秒推一次频谱）：控制台没有错误；心形和柱子的位置、大小和效果图一致，柱子在跳；在控制台执行 `shell.receive({ event: 'paused', paused: true })` → 柱子立刻落回静止，之后性能面板里没有持续的帧；`shell.receive({ event: 'paused', paused: false })` → 又跳起来

**用户手动验证**（`scripts/bundle.sh --open`）：

- [ ] 桌面底部中间偏右显示心形装饰条，两侧柱子是静止的短条（应用里还没有真实频谱，M5.5 才接上）
- [ ] 心形装饰条的位置点击能穿透给访达
- [ ] "活动监视器"里 DesktopShell 网页进程的 CPU 在桌面静止时接近 0

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：从已合并 M4-07 的最新 `main`（`fc40f1c`）建立 `task/M4-08`。新增 `createVisualizer`（`update` / `setPaused` / `dispose`）及同步挂载：同帧合并绘制最新 12 频段，两侧逐项镜像；静止高度仅在挂载时读取 CSS；每次频谱重设 250ms 一次性计时，静音、暂停、null 和销毁均移除行内 transform 并取消待执行工作，过期回调不影响新数据。DOM 纯装饰、不进入点击区域。CSS 原样取定稿，`main.js` 只在 WIDGETS 注册。
- **TDD 记录**：完整网页基线 387/387 PASS。16 项新增测试在占位实现下 RED 为 13 FAIL / 3 PASS；实现后定向 16/16 PASS。覆盖同帧最后一组、频段索引与静止下限、最后更新后 249/250ms 边界、静音取消未绘帧、pause/null、恢复等待新数据、过期帧/计时器隔离、卸载退订、初始暂停及一次性 CSS 读取。
- **最终自动检查**：`scripts/test-web.sh` 403/403 PASS（0 FAIL / 0 SKIP）；任务单 CSS 比对无输出；`grep -n "setInterval" web/widgets/visualizer.js` 无输出；`git diff --check` 通过。本任务恰为允许的 5 文件，规范、设计、其他组件及任务单需求/正式审查部分保持原样。
- **浏览器验证**：普通入口 `http://127.0.0.1:8765/` 独立页面的 error/warn 为空；心形加载成功（原图宽 1280）、两侧各 12 根柱子行内值逐项相同，频谱随 mock 更新，静止下限为 0.02。另用仓库外临时验收页嵌入真实入口（1792×1120，按 60% 展示），通过公开 `shell.receive` 验证 pause：24 根柱子的行内变换全部清除，稍后仍为 0/24；恢复后重新成为 24/24。无待执行帧/计时器由确定性调度测试验证，本轮未录制浏览器性能面板。
- **验证环境记录**：临时 iframe 容器曾出现 MutationObserver 的 Node 类型报错，故容器不作为“控制台无错误”的证据；普通入口另开独立页面检查无报错。容器初次从父页面构造暂停消息，被 bridge 的同环境普通对象校验拒绝；验收页改在子页面环境创建消息后暂停/恢复通过。产品 bridge 与源码未为这些验收环境问题改变。
- **构建与签名包**：`scripts/bundle.sh --open` 的 release 构建、Info.plist 检查及固定证书严格验证通过，应用已重启并确认进程存在。包内 `visualizer.js`、`visualizer.css`、`main.js` 与工作区逐字相同。应用路径 `/Users/arvinhan/Desktop/desktop-shell/build/DesktopShell.app`。本任务无 Swift 改动，本轮未重复原生单测，不沿用旧测试计数作本轮结果。
- **独立自查**：子代理只读核对全部 5 文件、调度和 bridge 输入契约，未发现 P0/P1/P2 问题；独立定向测试 16/16 PASS、CSS 比对和 diff 检查通过、无 setInterval。此结论不代替 Claude Code 正式复验。
- **本机证据**：`/tmp/desktopshell-m4-08-check/` 保存 baseline、RED、GREEN、最终网页测试与打包日志、普通入口 DOM/控制台记录、暂停/恢复记录、截图及临时验收页；不进入 Git。
- **疑问 / 偏离与待验收**：无范围扩展或新增视觉决定；现有 bridge 已验证并规范化 12 个频段，组件只消费频谱，不生成模拟数据、不实现系统音频捕获。原生应用静止短条是 M5.5 接入前的预期；真实 Finder 点击穿透、原生位置和静止网页进程 CPU 仍按上面的 3 项清单手动验证。状态交付 `review`，待 Claude 正式复验。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**代码审查通过，自动验收全部通过，待用户手动验证**（只剩两项目测，见最后）。用户确认后合并到 `main`。
- **复验结果**（Claude Code，2026-10-19，在 `79b30dc` 的独立检出上执行；打包在主目录的同一提交上执行）：
  - [x] `visualizer.css` 和 `design.css` 对应的一节逐行一致；`visualizer.js` 里没有 `setInterval`，不加 `.card`、`data-hit`
  - [x] 只改了允许的 5 个文件；`git diff --check` 通过；`scripts/test-web.sh` 403 项全部通过（没有 Swift 改动）
  - [x] 内置浏览器（1792 × 1120）：组件位置（离 `#desktop` 左 840、底 2，640 × 178，中心在中线右边 264）、心形装饰条、左右两组柱子的位置尺寸和每根柱子的间距，和效果图**逐项一致**；心形图加载成功（1280 × 213）；`aria-hidden="true"`、`pointer-events: none`，不在点击区域里；控制台没有输出
  - [x] 实际运行（mock 每 33 毫秒推一次频谱）：给 `requestAnimationFrame` 计数，运行时每秒 31 次（和频谱推送一致，没有额外的循环），24 根柱子都有高度且左右同位置相同；推送 `paused: true` 后立刻全部回到静止（去掉行内 `transform`），之后 1 秒内 `requestAnimationFrame` **0 次**；恢复后重新跳动
  - [x] `scripts/bundle.sh --open`（`07:33:20`）日志正常，包里的 `visualizer.js`、`visualizer.css` 和源码一致
  - [x] **静止时的 CPU**（原本是用户手动项，Claude Code 实测）：应用启动时一起起来的 WebKit 网页进程（`07:33:28` 启动）每 2 秒采样一次、共 10 次，0.0–0.6%；对应的 WebKit GPU 进程 0.0–0.5%
- **意见**：
  - 调度做法和任务单一致：新频谱只排一帧、帧里写最新的一组；每次频谱重设 250 毫秒的一次性定时器，没新数据就归零；暂停、`audioSpectrum` 为 `null`、卸载都会立刻归零并取消排着的帧和定时器，过期的回调不会生效。静止高度只在挂载时从 `--viz-bar-rest` 读一次。
  - 静音 250 毫秒后归零、静止高度下限这两点在浏览器里没法单独触发（mock 一直推频谱），由单元测试覆盖（含 249 / 250 毫秒边界）。
- **待用户手动验证**（现在桌面上运行的就是这一版）：
  - [ ] 桌面底部中间偏右显示心形装饰条，两侧柱子是静止的短条（应用里还没有真实频谱，M5.5 才接上）
  - [ ] 在心形装饰条和柱子上点击、拖动 → 点击穿透给访达（和点桌面空白处一样）
