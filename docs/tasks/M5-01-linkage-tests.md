# M5-01: 联动规则的整页回归测试

- **状态**：todo
- **里程碑**：M5
- **依赖**：M4 完成（已合并到 `main`）
- **分支**：task/M5-01

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

一份测试把所有组件挂在**同一个** store 上，经过真实的 `bridge.js` + mock，逐行验证 AGENTS.md "联动规则"表。以后 M5.5、M6 改动时，联动坏了能马上发现。本任务**只写测试，不改产品代码**。

## 背景与约束

- 先读 AGENTS.md "联动规则"表（8 行）和 `docs/design/README.md` 的"store 里的键"。
- 联动在 M4 各组件里已经实现，每个组件对 store 的反应也各自测过（`Tests/web/<组件>.test.mjs`）。缺的是"一个组件写、另一个组件读"这条链在一起跑的测试。`appearance.test.mjs` 里已经有一条三个组件一起挂的集成测试，可以参考它的假 DOM。
- **只写测试**。如果某条测试发现了真的联动问题：不要改产品代码，把那条测试标成 `test(..., { todo: '原因' }, ...)`（node:test 会显示为 todo、不算失败），在交付记录里写清楚现象和复现步骤，Claude Code 另开修复任务。
- 不需要打包应用，不碰真实的提醒事项和配置。

### 1. 测试环境

- 新建 `Tests/web/linkage.test.mjs`。可以新建 `Tests/web/helpers/` 下的共享假 DOM（把现有测试里的假 DOM 提出来复用也行，但不改现有测试文件的行为）。
- 用真实的 `createStore(initialState)`、`createBridge(store, { target, mock })` 和 `createMock({ timers, now, random })`（假定时器、固定时间、固定随机数），按 `main.js` 的 `WIDGETS` 顺序把全部组件挂在同一个假 `#desktop` 下，再 `await bridge.start()`。
- Swift 推送用 `target.shell.receive(event)`（和应用里一样走 `applyEvent`）。
- `main.js` 本身有顶层 `await` 和真实 `document`，不在 node 里导入；它对 `phase` / `paused` 的处理（设 `<html data-phase>`、`data-paused`）用读源码的方式确认订阅存在即可（`appearance.test.mjs` 已经这样检查过 `WIDGETS`）。

### 2. 每行一条（测试名用"联动 N：…"开头，N 是表里的行号）

1. **时段**：时钟挂载后写入的 `phase` 符合当前小时（用固定时间，例如 07:00 → `morning`、21:00 → `night`）；`main.js` 订阅了 `phase` 并设 `dataset.phase`。
2. **选中项目 → 待办**：点项目卡片的一行 → 待办只剩这个项目的提醒，范围文字是"只看「…」"；再点一次 → 回到全部、"全部列表"。选中有列表的项目时在输入框回车新增 → 发出的 `addTodo` 带 `projectId`，mock 推送后新提醒出现在筛选后的列表里。选中没有列表的项目（mock 里的"旅行照片整理"）→ 出现"这个项目没有对应的提醒事项列表……"提示；新增照样带 `projectId`（交给 Swift 放进默认列表），新提醒的 `projectId` 为 `null`，所以不出现在筛选后的列表里、取消选中后能看到。
3. **选中项目 → 启动栏**：同一次点击后，启动栏里项目 `apps` 列出的应用有 `.related`，其他没有；选中没有 `apps` 的项目 → 都没有；取消选中 → 都没有。
4. **每分钟 → 问候语**：从 20:59 推进到 21:00（假定时器 + 假时间），问候语的祝福语从 20 点那条换成 21 点那条，`phase` 从 `evening` 变成 `night`。
5. **低电量**：推送 `systemStats`（用电池 15%）→ 系统状态卡出现省电提示；页面**不**自己写 `paused`；再推送 `paused: true`（Swift 会这样做）→ 见第 6 条。电量 20% 时没有提示。
6. **暂停**：推送 `paused: true` → `audioSpectrum` 变成 `null`、律动条全部回到静止、之后再来的频谱被丢弃、不排新的帧；点头像照样播放语音（点击语音不受暂停影响）；推送 `paused: false` → 新频谱进来后律动条恢复。"Swift 停止系统音频捕获"属于 M5.5，这条测试里写明暂不覆盖。
7. **外观**：打开外观面板，点一张头像、一张背景 → 发出的 `saveUiState` 只带 id → mock 推送 `uiState` 后角色卡头像、角色卡和启动栏的背景图一起变；组件没有在推送之前先改界面。
8. **语音开关**：推送 `uiState` 把 `voiceEnabled` 设成 `false` → 点头像不创建 `Audio`；播放中推送关闭 → 当前播放停止、`voicePlaying` 回到 `false`；再打开 → 点头像又能播放。

### 3. 共同要求

- 每条测试结束都调用全部组件的清理函数并停掉 mock，测试之间互不影响。
- 不依赖真实时间、真实定时器和网络。

## 允许修改的文件

- `Tests/web/linkage.test.mjs`（新建）
- `Tests/web/helpers/**`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改 `web/`、`Sources/` 和现有的测试文件；不加 npm 包。
- 发现产品问题时不自己修，按上面说的标 `todo` 并报告。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `scripts/test-web.sh` 全部通过（标成 `todo` 的不算失败，但要在交付记录里逐条说明）
- [ ] `node --test Tests/web/linkage.test.mjs` 的输出里，"联动 1" 到 "联动 8" 每条都至少有一个测试
- [ ] `git diff --name-only main...task/M5-01` 只有 `Tests/web/linkage.test.mjs`、`Tests/web/helpers/` 下的文件和本任务单
- [ ] 故意破坏一处联动再跑，测试要能发现：例如临时把 `web/widgets/todos.js` 里按 `selectedProject` 筛选的那一行改掉，`linkage.test.mjs` 应当失败；试完恢复（在交付记录里写明试了哪几处、各自哪条测试失败）

**用户手动验证**：无（桌面上的逐条验证见 M5-02）。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
