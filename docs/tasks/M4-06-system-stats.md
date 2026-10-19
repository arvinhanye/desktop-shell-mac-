# M4-06: 系统状态

- **状态**：todo
- **里程碑**：M4
- **依赖**：M4-05（必须已合并到 `main`）
- **分支**：task/M4-06

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

第一列的"系统状态"卡片显示 CPU（数值和最近两分钟的折线）、内存和电量；用电池且电量低于 20% 时，电量条变成警告色，卡片底部出现省电提示。

## 背景与约束

- 先读 `docs/design/README.md` 的"组件的共同写法"和"定稿之外补充的状态和文案"（数值缺失、没有电池、电量小字）。照着做的部分：`index.html` 里 `stats` 一节；`design.css` 里 `stats.css` 一节；`mockup.js` 的 `renderStats`（折线的算法）。
- AGENTS.md：组件清单第 5 条；推送事件 `systemStats`（每 5 秒一次）；联动规则表"`systemStats` 显示使用电池且电量低"一行。
- 暂停由 Swift 统一决定（`PowerPolicy`，含低电量），组件**不写** `paused`，只负责显示提示。

### 1. 显示

- DOM 照 `index.html`：`.card.stats-card` > `.card-head`（`h2.card-title`"系统状态"）+ 三行 `.stat-row`（CPU、内存、电量）+ `p.power-hint`（文字照效果图："电量低于 20%，已暂停背景视频和动画来省电"）。
- 数值格式：CPU 和内存是一位小数加 `<small>%</small>`（`small` 用 `createElement` 建，不用 `innerHTML`）；电量是整数，后面的小字按 README 的表：用电池"% 用电池"，接电源在充电"% 充电中"，接电源没在充电"% 电源"。
- 进度条：内存、电量的 `.stat-bar > span` 用 `transform: scaleX(<百分比 / 100>)`。
- 低电量：`onBattery` 为真、`level` 不为 `null` 且小于 20 → 卡片加 `.low-battery`；否则去掉。
- 还没收到 `systemStats`、某个数值不是有限数字、`level` 为 `null`：照 README 的表显示"—"和空进度条，不能出现 `NaN`。

### 2. CPU 折线

- 每收到一次 `systemStats` 就把 `cpu` 追加到历史里，最多保留 24 个（5 秒一个，正好两分钟）。不另开定时器。
- 导出的纯函数 `sparkPoints(history)` → `{ line, area }`，分别给 `polyline` 和 `polygon` 的 `points`。SVG 的 `viewBox` 是 `0 0 60 26`（照 `index.html`）：
  - 第 `i` 个点（共 `n` 个）靠右排：`x = 60 - (n - 1 - i) × 60 / 23`，`y = 26 - v / 100 × 24 - 1`，保留两位小数。
  - `area` 是 `<第一个点的 x>,26 <line> 60,26`。
  - 少于 2 个点时两个都是空字符串（不画）。
- 历史只在内存里，页面重新加载后从空开始。

### 3. 接入

- `main.js` 的 `WIDGETS` 加上 `'stats'`。

### 4. 测试（`Tests/web/stats.test.mjs`）

- `sparkPoints`：0、1、2、24 个点；超过 24 个时只用最后 24 个（或者由追加函数保证）；数值 0 和 100 的坐标。
- 电量显示（例如 `batteryView(battery)`）：用电池 15%（低电量）、用电池 20%（不算低）、充电 50%、接电源没充电、`level` 为 `null`。
- 数值格式（例如 `formatPercent`）：正常值、`NaN`、`undefined`。

## 允许修改的文件

- `web/widgets/stats.js`、`web/widgets/stats.css`（新建）
- `web/js/main.js`（只改 `WIDGETS`）
- `Tests/web/stats.test.mjs`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不写 store 的 `paused`，不另开采样定时器。
- 组件 CSS 和 `design.css` 对应的一节不一致。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `scripts/test-web.sh` 全部通过，包含上面列出的新测试
- [ ] 下面的命令没有输出：

  ```bash
  awk -v t=web/widgets/stats.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/stats.css
  ```

- [ ] `git diff --name-only main...task/M4-06` 只包含"允许修改的文件"
- [ ] （Claude Code 复验）浏览器打开 `http://127.0.0.1:8765/`（mock 每 5 秒推一次）：控制台没有错误；数值每 5 秒变一次，折线从右边长出来；在控制台执行 `shell.receive({ event: 'systemStats', battery: { level: 15, charging: false, onBattery: true }, cpu: 20, memory: { usedBytes: 1, totalBytes: 2, percent: 50 } })` → 出现省电提示、电量条变色，和 `assets/design-screenshots/06-电量低和暂停.jpg` 一致

**用户手动验证**（`scripts/bundle.sh --open`）：

- [ ] CPU、内存的数值和"活动监视器"大致相符；接着电源时电量小字是"% 电源"或"% 充电中"
- [ ] 两分钟后折线铺满整个宽度
- [ ] 拔掉电源：小字变成"% 用电池"。（电量低于 20% 的效果不用专门放电去测，浏览器里已经验过）

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
