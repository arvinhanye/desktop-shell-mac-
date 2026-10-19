# M4-06: 系统状态

- **状态**：done
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

- **改动摘要**：基于已完成 M4-05 的 `main`（`abfe3ad`）建立 `task/M4-06`，仅修改允许的 5 个文件。新增系统状态卡片：CPU/内存一位小数、电量整数及供电文案、内存/电量条、低电量提示、右对齐的 24 样本 CPU 折线、缺失值显示和退订清理。CSS 原样采用定稿；`main.js` 仅增加 `WIDGETS` 项。复用现有 `systemStats` 推送，不增加采样定时器，不写 store 或暂停状态。
- **自测结果**：
  - 基线 `scripts/test-web.sh`：308/308 PASS。纯函数 29 项先全部确认断言失败再实现，随后 29/29 PASS；组件行为新增 8 项先全部确认挂载断言失败再实现。
  - 最终 `node --test Tests/web/stats.test.mjs`：**37/37 PASS**；`scripts/test-web.sh`：**345/345 PASS，0 FAIL，0 SKIP**。覆盖 0/1/2/24/超过 24 个样本、0/100 坐标、本地滚动历史、重复数值与无关 store 更新、初始/非有限/缺失数值、各电源状态、20% 边界、退订和重新挂载。
  - CSS `awk ... | diff -B` 零差异，`node --check web/widgets/stats.js` 和 `git diff --check` 通过；范围核对仅 5 个允许文件，任务需求/验收标准/正式审查记录保持原样。
  - 浏览器实际页面（mock，临时端口 18767）：控制台 0 warning、0 error；观察到数值持续更新，折线由右侧 3 点、22 点增长至 24 点铺满宽度，后续保持 24 点。重新加载后历史从空开始。
  - 临时隔离测试页（端口 18768，导入实际组件及 Bridge）：按钮通过 `shell.receive` 推送 15% 用电池、50% 充电、20% 用电池、无电池和连续 25 次样本，分别验证警告显隐、供电文案、空电量条及 24 点上限；直接向隔离 store 提供缺失值，验证三个“—”、空条和空折线。低电量提示出现时该组件未改变隔离 store 的 `paused`，暂停仍由原生策略负责。
  - 与设计稿页面对照，正常和低电量各 13 个选择器的采样计算样式一致，警告色为定稿的 `rgb(246, 205, 138)`；1792×1120 预览截图已检查。透明页的白底不是原生壁纸/毛玻璃效果。
  - 独立只读复核：37/37、全量 345/345、CSS 一致；另验证真实 Bridge → store → widget 连续推送/清理路径，未发现 P1/P2，不替代 Claude Code 正式审查。
  - 证据位于 `/tmp/desktopshell-m4-06-check/`（`baseline-web.log`、`red-pure.log`、`red-widget.log`、`final-stats.log`、`final-web.log`、`browser-styles.json`、`normal.png`、`low-battery.png`），未入 git。临时服务和测试页已关闭，浏览器尺寸已恢复。
  - 本次只改网页，未执行 Swift 构建或原生 GUI 验收；活动监视器数值对照、真实电源小字变化、原生运行两分钟后的折线，仍由用户按上方清单手动验证。
- **疑问 / 偏离**：
  - 无范围或视觉偏离。防御性处理无效 CPU 样本时清空历史，后续从新样本重新增长，避免将缺失值画成 0 或跨缺口连线；正常 Bridge 已校验 CPU 为 0–100 的有限数字。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**通过**，已合并到 `main`。代码审查和自动验收见下；用户手动验证 2026-10-19 完成（见最后）。
- **复验结果**（Claude Code，2026-10-19，在 `34f487e` 的独立检出上执行；打包在主目录的同一提交上执行）：
  - [x] `stats.css` 和 `design.css` 对应的一节逐行一致；`stats.js` 里没有 `setInterval`、`setTimeout`、`innerHTML`、`paused`
  - [x] 只改了允许的 5 个文件；`git diff --check` 通过
  - [x] `scripts/test-web.sh` 345 项全部通过（没有 Swift 改动）
  - [x] 内置浏览器（按 1792 × 1120 模拟视口）：推送和效果图相同的数值（CPU 18.4、内存 57.5、电量 85 接电源），卡片位置、尺寸、标题、三行的标签、折线、进度条、数值小字，相对卡片的位置、尺寸、字号、颜色和效果图**逐项一致**；推送"用电池 15%"后，卡片变高、电量条变成警告色 `rgb(246, 205, 138)`、省电提示出现，同样和效果图低电量状态逐项一致；页面上没有因此出现 `data-paused`（组件不写暂停状态）
  - [x] 折线：连推 30 个样本后保持 24 个点，从 x = 0 铺到 x = 60，首尾坐标符合公式；面积从第一个点的 x 落到底边。"接电源在充电"显示"90% 充电中"；`level` 为 `null` 显示"—"、进度条为空；控制台没有输出
  - [x] `scripts/bundle.sh --open` 后日志正常：`stats: sampling every 5s`、`power: paused=false`、`getConfig` 正常
- **意见**：
  - 只订阅一次 `systemStats`，没有自己的定时器；历史只在新推送时追加，最多 24 个，靠右排；缺失样本时清空历史重新开始，不会把缺口画成 0（交付记录写明了，合理）。低电量判断是"用电池且小于 20"，和 `PowerPolicy` 一致。
  - 数值、小字都用 `textContent`；进度条用 `style.transform`；SVG 用 `createElementNS` 建，结构和效果图一致。
- **手动验证**（2026-10-19，用户在 Claude Code 打包启动的 `34f487e` 上验证）：
  - [x] CPU、内存的数值和"活动监视器"相符（用户目测）
  - [x] 两分钟后折线铺满整个宽度（用户目测；应用 `00:27:07` 启动）
  - [x] 拔掉电源变"% 用电池"，插回去变"% 充电中"：`pmset -g log` 记录 `00:28:59 Using Batt`、`00:29:15 Using AC`，和用户的操作对得上
