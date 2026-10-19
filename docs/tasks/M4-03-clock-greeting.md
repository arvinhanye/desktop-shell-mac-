# M4-03: 时钟和问候语

- **状态**：review
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

- **改动摘要**：基于已完成 M4-02 的 `main`（`b6816df`）建立 `task/M4-03`。新增时钟与问候语，DOM/ARIA、两份 CSS 均遵循定稿；两个组件无 `.card` / `data-hit`。`main.js` 仅将 `WIDGETS` 设为 `['clock', 'greeting']`，其余逻辑保持原样。
- **时钟实现**：本地日期格式化；立即写入整分钟 `now` 与 `phase`；一次性 `setTimeout` 对齐下一分钟加 50ms，再按当前实际时间重排。恢复可见时立即重绘并替换旧定时器；不因 `paused` 停止。清理时移除监听/定时器，已排队回调也不会恢复更新。
- **问候语实现**：复制、排序后按小时选取，凌晨缺少早期条目时沿用前一天最后一条；订阅 `config` 与 `now`。配置未到或列表为空时清空内容；无称呼时隐藏逗号和名字，配置恢复后重新显示。动态文本仅使用 `textContent`；清理时退订两个键。
- **RED → GREEN**：修改前网页基线 177/177 PASS；先补 35 项测试和空实现，确认 35/35 为预期断言失败（不是导入或语法错误）；实现后 `scripts/test-web.sh` 212/212 PASS、FAIL 0、SKIP 0。新增测试涵盖所有指定小时/日期边界、整分/59.95 秒调度、跨午间和跨年校时、暂停仍更新、重复清理及过期回调、乱序且冻结的问候数组、null 名称、空配置、零时间戳与 HTML 字面文本。
- **多时区与样式验证**：UTC、Asia/Shanghai、America/New_York 下新增测试各 35/35 PASS；任务单两条 `awk | diff -B` 均无输出。未加入轮询、持续动画或额外样式。最终差异限定在允许的 8 个文件；任务需求、正式审查栏及其他文件保持原样。
- **浏览器验证**：在仅本机的 `127.0.0.1:18766` 打开正式页面，与 `/design/index.html` 的“实际尺寸”参考核对：11 组组件/文本元素的位置、尺寸、字体、字号、颜色等计算样式完全一致，差异 0；正式页 error/warn 0，`.card, [data-hit]` 数量为 0。初次读取本地 20:55，整分钟后自动显示 20:56，`data-phase=evening`，问候为“晚上好，Arvin”。正式页透明背景在浏览器中呈白底，视频仍由原生窗口提供。
- **独立复核**：只读复核覆盖 8/8 文件；独立重跑网页 212/212 PASS，并复核三时区、样式、生命周期与范围，无已确认代码缺陷。此为实现侧复核，不替代 Claude Code 正式审查。
- **待人工验收**：本次未启动正式 `.app`，未修改运行时配置。请按任务单先配置 `user.name`，运行 `scripts/bundle.sh --open`；核对真实壁纸上效果、与菜单栏同步、合盖恢复、日期/问候语点击穿透及 Finder 框选。IAB 浏览器和模拟时钟测试不等同于 Safari/原生桌面验收。
- **疑问 / 偏离**：无范围偏离；测试比任务列出的纯函数检查额外覆盖挂载与清理生命周期，仍仅放在两份获准的新测试文件内。
- **本机证据**：`/tmp/desktopshell-m4-03-check/` 保存基线、RED、GREEN、三时区日志、浏览器样式比对 JSON 和截图；不入 git。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**代码审查通过，自动验收全部通过，待用户手动验证**（见最后）。用户确认后合并到 `main`。
- **复验结果**（Claude Code，2026-10-18，在 `2a7d849` 的独立检出上执行；打包在主目录的同一提交上执行）：
  - [x] `clock.css`、`greeting.css` 和 `design.css` 对应的一节逐行一致（两条 `awk | diff -B` 都没有输出）
  - [x] 只改了允许的 8 个文件；`git diff --check` 通过；两个组件里没有 `setInterval`、`innerHTML`、`requestAnimationFrame`、`.card`、`data-hit`
  - [x] `scripts/test-web.sh` 212 项全部通过；新加的两份测试在 `TZ=UTC`、`Asia/Shanghai`、`America/New_York` 下各 35 项全部通过（没有 Swift 改动，未跑 `scripts/test.sh`）
  - [x] 内置浏览器：效果图按"实际尺寸"量出 10 个元素（两个组件外壳、星期、日、月、时间、细线、中文日期、问候、祝福语）相对 `#desktop` 的位置、尺寸、字体、字号、字间距，正式页面逐项比较，**差异为 0**；控制台没有任何输出；页面上没有可点击区域
  - [x] 浏览器里恰好跨过 21:00：时间自动变成 `21:00`，`data-phase` 从 `evening` 变成 `night`（称呼的颜色、底板变量跟着变），祝福语从 20 点那条换成 21 点那条
  - [x] `scripts/bundle.sh --open` 后日志正常
- **意见**：
  - 时钟按任务单用一次性定时器对齐整分（加 50 毫秒），每次到点按实际时间重排；页面重新可见时立即重画并替换旧定时器；清理后已排队的回调不再生效。`now` 用"减去秒和毫秒"得到整分，避开夏令时折返时重建本地时间的问题，做法好。
  - 问候语复制后排序，凌晨没有更早的条目时取最后一条；`config`、`now` 各订阅一次，`immediate` 让首次渲染跑两遍，无害。
  - DOM 结构、`aria-label` 和效果图一致；文字都用 `textContent`。
- **待用户手动验证**（现在桌面上运行的就是这一版；`config.json` 里已有 `user.name`）：
  - [ ] 左上角的日期、月份、竖排星期、时间、细线、中文日期，和 `assets/design-screenshots/01-夜晚.jpg` 的版式、字体一致；第二列顶部右对齐"晚上好，Arvin"（名字粉色）和祝福语
  - [ ] 等到下一分钟，时间跟着变，和菜单栏的时钟一致
  - [ ] 合上盖子睡几分钟再打开，时间马上是对的
  - [ ] 先选中一个访达图标，再点日期或问候语 → 图标取消选中；从日期上开始拖动 → 出现访达的框选框
