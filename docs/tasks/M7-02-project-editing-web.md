# M7-02: 项目卡片的添加输入框、移除按钮和拖入提示（网页）

- **状态**：todo
- **里程碑**：M7
- **依赖**：无。和 M7-01 互不依赖：本任务用 mock 开发，Swift 端的动作在 M7-01 里做。M7-03 依赖本任务
- **分支**：task/M7-02

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

照 2026-10-21 定稿，给项目卡片加上三样东西：

- "＋ 粘贴文件夹路径，或把文件夹拖进来"的输入框；
- 行尾点两次才生效的移除按钮；
- 文件夹拖到卡片上方时的提示层。

`bridge.js` 处理新的推送事件 `config` 和 `projectDrop`，mock 能模拟增删。做完后在浏览器里就能完整试用；在应用里，等 M7-01 合并后输入框和移除按钮才真正生效，拖入要等 M7-03。

## 背景与约束

- 先读 AGENTS.md 里标着 M7 的部分（Bridge 动作 `addProject` / `removeProject`、错误码、推送事件 `config` / `projectDrop`），以及 `docs/design/README.md`：
  - "组件的共同写法"；
  - "定稿之外补充的状态和文案"里标着 M7 的五行，加上"`config.projects` 为空"那一行的新文案；
  - "store 里的键"里的 `config`、`projectDrop`。
- 定稿：
  - `docs/design/index.html` 的 `projects` 一节：新的 DOM，包括 `#project-meta`、`.project-add`、`.project-hint`、`.project-drop`；
  - `design.css` 的 `projects.css` 一节；
  - `mockup.js` 里"添加和移除项目"那一段，作交互参考，正式组件按本任务单写。
- 键盘：输入框的焦点交给 `web/js/keyboard-focus.js`，组件不调用 `focusInput` / `blurInput`（README "组件的共同写法"）。
- **Codex 不自行做视觉决定**：样式、文案都照定稿和 README。

### 1. 样式和 token

- `web/widgets/projects.css` 换成 `design.css` 里 `projects.css` 那一节的最新内容，核对命令见验收标准。
- `web/styles/tokens.css` 只同步本次定稿新增和改动的 token：
  - 新增 `--glow-drop`、`--drop-fill`、`--drop-dim-opacity`、`--icon-lg`；
  - `--projects-height` 改成 `300px`，`--todos-top` 改成 `538px`；
  - 数值和注释照 `docs/design/tokens.css`。
- **不要**顺手同步 `--avatar-ring-*`、`--voice-ring-dim`、`--ease-breathe`：它们属于暂缓的 M4-11。

### 2. 组件（`web/widgets/projects.js`）

- **DOM**：照 `index.html`。
  - 标题右边的 `.card-meta` 已经有了，用来显示"没能打开"，继续沿用它显示"已添加…""已移除…""没能移除"。
  - 输入框带 `spellcheck="false"`、`autocomplete="off"`。
  - 卡片上加 `data-drop="projects"`，给 M7-03 的拖入区域上报用；本任务不上报。
- **添加**：
  - 在输入框里按回车（输入法组字时不算），先去掉首尾空白；为空就什么都不做。
  - 发送 `bridge.send('addProject', { path })`。
  - 成功：清空输入框，按 README 显示"已添加「名字」"，列表滚到底。新项目由 Swift 推送的 `config` 带来，组件**不自己往列表里加**。
  - 被拒：按错误码显示 `.project-hint.error` 的文案。
  - 请求还没回来时，再按回车不重复发送。
- **移除**：行尾 `.project-remove`，用定稿里的 × 图标。
  - 第一次点：加 `.confirm`，文字换成"移除？"，开始 3 秒计时；3 秒内再点才发送 `removeProject`，过时恢复成 ×。
  - 同一时间只有一行在确认状态。
  - 点它不会选中这一行（`stopPropagation`）。
  - 成功或被拒按 README 显示。
  - 被移除的项目如果正选中着：现有逻辑在 `config` 里找不到选中的项目时会清空 `selectedProject`，确认它在推送 `config` 后照样生效。
- **拖入提示**：订阅 `store.projectDrop`。
  - `over` 为真时，卡片加 `.drop-target`，否则去掉。
  - 带 `result` 时，按 README "一次拖入多个文件夹"那一行显示：
    - `added` 有一个："已添加「名字」"；
    - 有多个："已添加 N 个项目"；
    - `error` 不为空：在 `.project-hint` 里显示对应的错误文案。
  - `projectDrop` 的 `result` 是一次性的：同样的结果连推两次，就显示两次。用推送时间或计数区分，写法自定，但要有测试。
- **列表为空**时的文案改成 README 里 M7 的新文案。
- 卸载时清理所有计时器和监听。

### 3. `bridge.js`

- 推送事件 `config`：校验它和 `getConfig` 回复里的 `config` 结构一致（复用现有的校验），通过后整体替换 `store.config`；不合格就整条丢弃并 `console.warn`，和其他事件一样。
- 推送事件 `projectDrop`：
  - `over` 必须是布尔值；
  - `result` 是 `null`，或者 `{added: [{id, name}], error}`，其中 `id` 符合 id 规则，`name` 是字符串，`error` 是字符串或 `null`；
  - 写入 `store.projectDrop`。
- `store.js` 的初始状态加 `projectDrop: { over: false, result: null }`。如果 `store.js` 的初始状态写在别处，就在那里加，并在交付记录里说明。

### 4. mock（`web/js/mock.js`）

- 动作表加 `['addProject', ['path']]`、`['removeProject', ['projectId']]`。
- mock 没有真实文件系统，用和 `mockup.js` 一样的规则模拟核对结果：
  - 不以 `~/` 或 `/Users/<名字>/` 开头 → `outside-home`；
  - 以 `.xxx` 扩展名结尾 → `not-directory`；
  - 含 `missing` → `not-found`；
  - 和已有项目同路径或同名 → `duplicate`。
- 成功时按 AGENTS.md 的规则生成 id 和默认值，回复新项目，并推送 `config`。
- `removeProject` 找不到 → `not-found`；成功推送 `config`。
- 再加一个调试用的方法 `mock.dropFolders(names)`：先推 `projectDrop {over: true}`，再按名字逐个添加（路径用 `~/Desktop/<名字>`），最后推 `{over: false, result}`。这样在浏览器里也能看到拖入的效果。如果 `bridge.js` 已经把 mock 挂到了 `window` 上，顺着现有的写法暴露它；没有的话就只在测试里用。

### 5. 测试

- `Tests/web/projects.test.mjs`：
  - 回车添加：发出的请求、成功后清空输入框并显示提示、四种错误码和其他错误的文案、组字时回车不发送、等回复期间不重复发送；
  - 移除：两次点击、3 秒过期、同时只有一行在确认、点击不选中行、成功和失败的提示；
  - `projectDrop`：`over` 对应 `.drop-target`；`result` 的一个、多个、有错误三种显示；同样结果连推两次显示两次；
  - 空列表的新文案；
  - 卸载后没有残留的计时器。
- `Tests/web/bridge.test.mjs`：`config`、`projectDrop` 两个事件合法和不合法的输入。
- `Tests/web/mock.test.mjs`：`addProject` 的几种结果、id 生成（包括纯中文名得到 `project`、重名加 `-2`）、`removeProject`、成功后推送了 `config`、`dropFolders`。
- `Tests/web/linkage.test.mjs` 现有的测试必须照样通过。如果只是因为 DOM 多了元素需要调整测试里找元素的写法，可以改，在交付记录里写明改了哪里。

## 允许修改的文件

- `web/widgets/projects.js`、`web/widgets/projects.css`、`web/styles/tokens.css`
- `web/js/bridge.js`、`web/js/mock.js`、`web/js/store.js`
- `Tests/web/projects.test.mjs`、`Tests/web/bridge.test.mjs`、`Tests/web/mock.test.mjs`、`Tests/web/linkage.test.mjs`（只在上面说的情况下改）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改 Swift（M7-01、M7-03）；不做拖入区域的上报（`setDropRegions`，M7-03）。
- 组件不往 `store.config` 里自己加减项目，一律等 `config` 推送。
- 不改其他组件的样式和 DOM。`todos` 的位置只通过 `--todos-top` 这个 token 变化。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `scripts/test-web.sh` 全部通过
- [ ] 下面这条命令没有输出：

  ```bash
  awk -v t=web/widgets/projects.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/projects.css
  ```
- [ ] `grep -nE -- '--(glow-drop|drop-fill|drop-dim-opacity|icon-lg|projects-height|todos-top):' web/styles/tokens.css`：6 行，数值和 `docs/design/tokens.css` 一样；`grep -c -- '--avatar-ring' web/styles/tokens.css` 输出 `0`
- [ ] `git diff --name-only main...task/M7-02` 只有上面"允许修改的文件"
- [ ] （Claude Code 复验）浏览器打开 `http://127.0.0.1:8765/`：
  - 项目卡片的样子和效果图（`/design/index.html`）一致；
  - 粘贴 `~/Desktop/test` 回车能添加；`/etc/hosts` 显示"只能添加个人文件夹（~）里的文件夹"；
  - × 点两次能移除；
  - 在控制台调用 `dropFolders` 能看到拖入提示和结果；
  - 控制台没有错误。

**用户手动验证**：本任务没有。应用里的效果，等 M7-03 合并后一起验证。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
