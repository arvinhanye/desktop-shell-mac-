# M4-05: 待办（系统提醒事项）

- **状态**：todo
- **里程碑**：M4
- **依赖**：M4-04（必须已合并到 `main`；用到时钟写的 `now` 和项目卡片写的 `selectedProject`）
- **分支**：task/M4-05

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

第二列的"待办"卡片显示系统提醒事项：所有列表的未完成提醒，加上今天完成的（划掉显示，排在最后）；可以勾选、取消勾选，可以在输入框里新增。选中某个项目时只显示它对应列表里的提醒，新增的提醒也放进那个列表。没有授权时显示提示。

## 背景与约束

- 先读 `docs/design/README.md` 的"组件的共同写法""store 里的键"和"定稿之外补充的状态和文案"（待办的几种权限状态和报错文字都在那里）。照着做的部分：`index.html` 里 `todos` 一节；`design.css` 里 `todos.css` 一节；`mockup.js` 的 `renderTodos`、`dueLabel` 和输入框的 `keydown` 处理。
- AGENTS.md：组件清单第 4 条；Bridge 的 `addTodo`、`setTodoDone` 和推送事件 `todos`；联动规则表"选中某个项目卡片 → 待办"一行。
- M3 审查记录里写给 M4 的要求：
  - 今天完成的提醒排在最后（Swift 已经排好），组件要显示它们，划掉，并且可以再点一下取消完成（M3-07）。
  - 输入框的焦点由 `keyboard-focus.js` 统一处理，组件不调用 `focusInput` / `blurInput`，也不自己处理 Esc。拼音候选框开着时，第一次 Esc 关掉候选框、第二次才退出输入框——`keyboard-focus.js` 判断了 `isComposing`，已经是这样，组件不要破坏它（M3-08）。
- **自测不碰用户真实的提醒事项**（同 M3-07）：用户的提醒事项会同步到 iPhone。自测只用浏览器里的 mock；需要真实写入的检查（勾选、新增、项目列表）全部留给用户手动验证。
- 不提供删除。

### 1. 卡片顶部

- `.card-head`：`h2.card-title`"待办" + `span.card-meta`：选中了项目 → `只看「<项目名>」`；没选中 → `全部列表`。
- `.todo-hint`：选中的项目 `hasReminders` 为 `false` → "这个项目没有对应的提醒事项列表，新增的提醒会放进默认列表"；否则为空（空的时候 CSS 会隐藏它）。出错时临时显示错误文字（见第 4、5 节），错误清除后恢复原来的提示。

### 2. 权限

按 `todosAccess` 显示（文案见 README 的表）：

- `granted`：显示输入框和列表。
- `unknown`（还没收到第一次推送）：输入框隐藏，列表为空，不显示文字。
- `notDetermined`：输入框隐藏；列表里一个 `li.todo-denied`，内容是"正在等待提醒事项权限 / 在弹出的对话框里点「允许」"。
- `denied`、`restricted`、`writeOnly`：输入框隐藏；`li.todo-denied`，内容是效果图的原文"还不能读取提醒事项 / 到「系统设置 → 隐私与安全性 → 提醒事项」里允许 DesktopShell"。

### 3. 列表

- 选中了项目 → 只显示 `projectId` 等于它的提醒；没选中 → 全部。
- 顺序保持推送来的顺序（Swift 已经排好：未完成的按到期时间在前，今天完成的在后）。先列未完成的；有今天完成的，就加一个 `li.todo-section`"今天完成"，再列完成的。
- 每一条：`li.todo`（完成的加 `.done`）> `button.todo-check`（`aria-label` 未完成时"完成"、完成时"取消完成"，里面是 `mockup.js` 里的勾号 SVG）+ `div` > `span.todo-text`，未完成且有到期时间的再加 `span.todo-due`。完成的不显示到期时间。
- 没有可显示的提醒：一个 `li.todo-empty`"没有待办。在上面输入一条，按回车保存"。
- 到期文字用导出的纯函数 `dueLabel(due, now)`，按**本地日历**算（把 `YYYY-MM-DD` 拆成年月日再 `new Date(y, m - 1, d)`；不要用 `new Date('YYYY-MM-DD')`，它按 UTC 解析，会差一天）：
  - 和今天差 0 天"今天"、1 天"明天"、-1 天"昨天"，其余"M月D日"（不补零）；有 `time` 时后面加一个空格和 `HH:mm`。
  - 过期：日期在今天之前，或者是今天并且 `time` 早于现在的时分 → `span` 加 `.overdue`，文字前面加"已过期 "。只有日期、日期是今天的不算过期。
- 订阅 `now`：每分钟重新算到期文字和过期状态（跨过午夜时"今天""明天"也跟着变）。
- 推送来了重新渲染列表时：不碰输入框（它不在列表里），保持列表的滚动位置。
- 列表用 `installScrollHints`。

### 4. 勾选

- 点 `.todo-check` → 这一行立刻显示成目标状态，发 `setTodoDone { todoId, done }`。请求没回来之前，这一行的按钮再点忽略。
- 成功：不用做别的，Swift 会推送新的 `todos`。
- 失败：这一行恢复原状，`.todo-hint` 显示"没能更新这条提醒，请再试一次"。
- 做法建议：渲染时叠加一张"正在提交的勾选状态"表，请求结束后删掉对应的项，再按 store 的数据重新渲染。

### 5. 新增

- 在输入框里按回车（`event.isComposing` 为真时不处理，那是在选拼音候选词）：
  - 文字去掉首尾空白后为空 → 什么都不做。
  - 超过 500 个字（按字素数，用 `Intl.Segmenter`）→ `.todo-hint` 显示"最多 500 个字"，不发请求。
  - 否则发 `addTodo { text, projectId }`：选中了项目就带上它的 id（没有对应列表时 Swift 会放进默认列表）；没选中就不带 `projectId`。
- 请求没回来之前再按回车不重复发。
- 成功：如果输入框里还是刚才发出去的那段文字，就清空。不自己往列表里插数据，等 Swift 推送。
- 失败：保留输入框里的文字，`.todo-hint` 显示"没能添加，请再试一次"。
- 错误文字在输入框内容变化，或下一次操作成功后清除。

### 6. 接入

- `main.js` 的 `WIDGETS` 加上 `'todos'`。

### 7. 测试（`Tests/web/todos.test.mjs`）

- `dueLabel`：今天、明天、昨天、其他日期；带时间和不带时间；今天已过的时间和未到的时间；只有日期的今天不算过期；跨月、跨年（12 月 31 日看 1 月 1 日是"明天"）。
- 筛选和分组（例如 `visibleTodos(todos, selectedProject)` 返回未完成和完成两组）：没选中、选中有提醒的项目、选中没有提醒的项目；保持原顺序。
- 权限对应的显示（例如 `accessView(access)`）：六种取值各显示什么。
- 字数：`graphemeCount` 对中文、emoji、组合字符；500 和 501 的边界。
- 卡片顶部文字（例如 `scopeText`、`hintText`）：没选中、选中有列表的项目、选中没有列表的项目。

## 允许修改的文件

- `web/widgets/todos.js`、`web/widgets/todos.css`（新建）
- `web/js/main.js`（只改 `WIDGETS`）
- `Tests/web/todos.test.mjs`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。不提供删除，不新增 Bridge 动作。
- 不往用户真实的提醒事项里新增、勾选或修改任何提醒。
- 不在组件里调用 `focusInput` / `blurInput`，不另外处理 Esc。
- 不用 `innerHTML` 插入提醒标题。
- 组件 CSS 和 `design.css` 对应的一节不一致。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `scripts/test-web.sh` 全部通过，包含上面列出的新测试
- [ ] 下面的命令没有输出：

  ```bash
  awk -v t=web/widgets/todos.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/todos.css
  ```

- [ ] `grep -n "focusInput\|blurInput" web/widgets/todos.js` 没有输出
- [ ] `git diff --name-only main...task/M4-05` 只包含"允许修改的文件"
- [ ] （Claude Code 复验）浏览器打开 `http://127.0.0.1:8765/`（mock 数据）：控制台没有错误；卡片和效果图一致（过期的红字、"今天完成"分组、划掉的完成项）；勾选、取消勾选、回车新增都生效；选中 DesktopShell 只剩它的 4 条（3 条未完成、1 条今天完成），选中"旅行照片整理"出现没有列表的提示；在控制台执行 `shell.receive({ event: 'todos', access: 'denied', items: [] })` 切到未授权，显示和 `assets/design-screenshots/07-提醒事项未授权.jpg` 一致

**用户手动验证**（`scripts/bundle.sh --open`）：

- [ ] 待办里的提醒和 Mac "提醒事项"应用里的一致（所有列表的未完成提醒，加上今天完成的），带到期时间的显示到期时间，过期的是红字
- [ ] 勾选一条 → 它划掉、移到"今天完成"下面，"提醒事项"应用里也变成已完成；再点一下 → 恢复
- [ ] 点输入框，用拼音输入一句中文，按回车 → 出现在列表里，也出现在"提醒事项"的默认列表里；之前在前台的应用没有被切走
- [ ] 输入拼音时候选框开着，按一次 Esc → 只关掉候选框；再按一次 Esc → 退出输入框，键盘回到原来的应用（在原来的应用里接着打字能打进去）
- [ ] 选中配置了 `remindersList` 的项目 → 只显示那个列表的提醒，标题右边显示"只看「…」"；新增一条 → 进了那个列表。选中没有配置列表的项目 → 显示"这个项目没有对应的提醒事项列表……"
- [ ] 在 iPhone 上勾选一条，过一会儿桌面上跟着变
- [ ] 在"系统设置 → 隐私与安全性 → 提醒事项"里关掉 DesktopShell，重启应用 → 显示"还不能读取提醒事项"；验证完重新打开

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
