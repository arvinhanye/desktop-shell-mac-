# M4-08: 音频律动

- **状态**：todo
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

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
