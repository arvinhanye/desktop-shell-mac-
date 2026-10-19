# M4-03: 时钟和问候语

- **状态**：todo
- **里程碑**：M4
- **依赖**：M4-02（必须已合并到 `main`）
- **分支**：task/M4-03

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

桌面左上角显示大号日期、月份、竖排星期、时间和中文日期（时钟）；第二列顶部右对齐显示"<问候>，<称呼>"和祝福语（问候语）。时钟每分钟更新一次，同时写入 store 的 `now` 和 `phase`，整个页面跟着时段换配色。

## 背景与约束

- 先读 `docs/design/README.md` 的"组件的共同写法"和"store 里的键"。照着做的部分：`docs/design/index.html` 里 `data-widget="clock"`、`data-widget="greeting"` 两节的 DOM；`design.css` 里 `clock.css`、`greeting.css` 两节；`mockup.js` 的 `renderClock` 是文字格式的参考。
- AGENTS.md：组件清单第 1、6 条；"配置文件示例"下面关于 `greetings` 和 `user.name` 的说明；联动规则表"时钟更新 `phase`"和"时钟每分钟更新"两行。
- 这两个组件直接写在壁纸上，没有底板，也不可点击：不加 `.card`、不加 `data-hit`，点击穿透给访达。

### 1. 时钟（`web/widgets/clock.js`、`clock.css`）

- 导出的纯函数：
  - `phaseForHour(hour)`：6–11 点 `morning`，12–17 点 `day`，18–20 点 `evening`，其余 `night`。
  - `clockText(date)` → `{ weekday, day, month, time, date }`：`weekday` 是英文星期全称大写（`SUNDAY`），`day` 是两位数的日（`08`），`month` 是英文月份全称大写（`SEPTEMBER`），`time` 是 24 小时制 `HH:mm`，`date` 是 `10月18日 星期日`（月、日不补零）。都按本地时间。
  - `msUntilNextMinute(date)`：到下一分钟开始还有多少毫秒。
- `mount`：建好 DOM，立即渲染一次，并 `store.set({ now: <这一分钟开始的时间戳>, phase })`。
- 更新：用一次性的 `setTimeout(…, msUntilNextMinute(new Date()) + 50)` 等到下一分钟，到点后渲染、写 store、再排下一次。不用 `setInterval`，不按秒刷新。
- 页面重新变为可见（`document` 的 `visibilitychange`）时立刻重新渲染、写 store，并重排定时器（防止休眠或页面隐藏期间定时器被推迟）。
- 暂停（`paused`）时照常更新：时钟不是动画。
- `phase` 只由时钟写；`main.js` 已经会把它设成 `<html data-phase>`，不用再改 `main.js` 的这部分。
- 清理函数：清掉定时器，移除 `visibilitychange` 监听。

### 2. 问候语（`web/widgets/greeting.js`、`greeting.css`）

- 导出的纯函数 `greetingFor(greetings, hour)`：按 `from` 升序（复制一份再排序，不改原数组）取最后一个 `from <= hour` 的项；一个都没有（例如列表从 6 点开始，现在是 3 点）→ 取 `from` 最大的那一项（前一天延续下来的）；列表为空 → `null`。
- 订阅 `config` 和 `now`，小时取自 `now`（`now` 为 `null` 时用当前时间）。
- 显示：`.greeting-title` 里是问候 `title`、逗号 `，`、`.greeting-name`（`config.user.name`，强调色）；`user.name` 为 `null` 时逗号和名字都隐藏（`hidden`），只显示问候。`.greeting-wish` 是 `wish`。
- `config` 还没到或 `greetingFor` 返回 `null`：组件内容为空，不显示占位文字。
- 文字一律用 `textContent`。

### 3. 接入

- `web/js/main.js` 的 `WIDGETS` 加上 `'clock'`、`'greeting'`（时钟在前）。

### 4. 测试

- `Tests/web/clock.test.mjs`：
  - `phaseForHour`：0、5、6、11、12、17、18、20、21、23 点。
  - `clockText`：固定一个日期（例如 2026 年 9 月 9 日 7:05，星期三 → `WEDNESDAY`、`09`、`SEPTEMBER`、`07:05`、`9月9日 星期三`），再加一个 12 月 31 日 23:59。
  - `msUntilNextMinute`：整分时是 60000；第 59.95 秒时是 50。
- `Tests/web/greeting.test.mjs`：AGENTS.md 示例的 7 条在 0、5、6、12、18、19、20、21、23 点各取到哪一条；乱序输入结果一样且原数组没被改；列表从 6 点开始时 3 点取到最后一项；空列表返回 `null`。

## 允许修改的文件

- `web/widgets/clock.js`、`web/widgets/clock.css`、`web/widgets/greeting.js`、`web/widgets/greeting.css`（新建）
- `web/js/main.js`（只改 `WIDGETS`）
- `Tests/web/clock.test.mjs`、`Tests/web/greeting.test.mjs`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不按秒刷新，不加任何持续动画。
- 组件 CSS 和 `design.css` 对应的一节不一致（多、少、改都不行）。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `scripts/test-web.sh` 全部通过，包含上面列出的新测试
- [ ] 两个样式文件和定稿一致，下面两条命令都没有输出：

  ```bash
  awk -v t=web/widgets/clock.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/clock.css
  awk -v t=web/widgets/greeting.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/greeting.css
  ```

- [ ] `git diff --name-only main...task/M4-03` 只包含"允许修改的文件"
- [ ] （Claude Code 复验）浏览器打开 `http://127.0.0.1:8765/`：控制台没有错误；时钟、问候语的位置、字体、字号和 `docs/design/` 效果图（`http://127.0.0.1:8765/design/`，"实际尺寸"）一致；`<html>` 的 `data-phase` 和当前时段相符

**用户手动验证**（`scripts/bundle.sh --open`；先按 M4-01 在 `config.json` 里加好 `user.name`）：

- [ ] 桌面左上角：粉色渐变的大号日期、白色月份、竖排英文星期、时间和下面的细线、中文日期，和 `assets/design-screenshots/01-夜晚.jpg` 的版式、字体一致
- [ ] 第二列顶部右对齐："<问候>，Arvin"（名字是粉色）和祝福语
- [ ] 等到下一分钟：时间跟着变，和菜单栏的时钟一致
- [ ] 合上盖子睡几分钟再打开：时间马上是对的
- [ ] 先选中一个访达图标，再点日期或问候语 → 图标取消选中（点击交给了访达，和点桌面空白处一样）；从日期上开始拖动 → 出现访达的框选框

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
