# M5-01: 联动规则的整页回归测试

- **状态**：review
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
  - 从已同步远端的 `main`（`fbfc9d9`）创建 `task/M5-01`。新增 `Tests/web/linkage.test.mjs`，用 9 条测试覆盖联动表第 1–8 行（第 1 行分别覆盖 07:00 和 21:00）。
  - 十个真实组件按 `main.js` 的 `WIDGETS` 顺序挂在同一个假 `#desktop` 下，共用真实 `createStore(initialState)`、`createBridge` 和 `createMock`；所有挂载完成后才调用 `bridge.start()`。项目筛选、启动栏关联、待办回车新增、外观按钮和语音均由 DOM 事件触发，不通过直接写入共享状态代替组件联动。
  - 新增 `Tests/web/helpers/linkage-browser.mjs`：提供最小 DOM/事件冒泡、固定日期、手动推进的 timeout/interval/RAF、观察器和无 I/O 的 Audio。随机源固定；不引入 npm 包，也不修改既有测试。
  - 外观场景保留真实 mock 校验与回复，只延迟其 `uiState` 推送；验证请求与回复已结束、推送尚未送达时，共享状态、头像、两张背景和选择标记仍保持原值，再经 `target.shell.receive` 投递真实事件验证一起生效。
  - 每条测试预先注册清理钩子：逆序调用全部组件清理函数、退订事件观察、停止 mock、还原全局 Audio，并检查无残留定时器/帧/观察器/DOM 或 Audio 监听；清理后再推进一分钟，状态仍不变化。store/bridge 捕获的告警和异常也会使测试失败。
- **自测结果**（2026-10-19）：
  - 修改前基线：`scripts/test-web.sh` **PASS 412/412**，fail/skip/todo 均为 0。
  - 新增测试：`node --test Tests/web/linkage.test.mjs` **PASS 9/9**，输出覆盖“联动 1”到“联动 8”，fail/skip/todo 均为 0。
  - 全量回归：`scripts/test-web.sh` **PASS 421/421**，fail/skip/todo 均为 0。
  - 时区隔离复验：`TZ=UTC node --test Tests/web/linkage.test.mjs` **PASS 9/9**。
  - 变异验证：复制 `web/`、本次测试和 helper 到系统临时目录，逐项改动下表中的一处代码，运行 `node --test --test-reporter=tap Tests/web/linkage.test.mjs`。**12/12** 均退出 1，且失败的是预期联动断言而非语法/导入错误；每次恢复该文件后才继续下一项。最后恢复副本全部源文件，重新运行 **PASS 9/9**。原工作区产品文件全过程保持原样。

    | 临时破坏的位置 / 行为 | 被触发的失败测试 |
    |---|---|
    | `clock.js`：时段恒写 `day` | 联动 1 两条、联动 4 |
    | `todos.js`：`visibleTodos` 的项目筛选谓词恒为 `true` | 联动 2、联动 3 |
    | `launcher.js`：关联应用改为订阅 `ready` 而非 `selectedProject` | 联动 3 |
    | `greeting.js`：问候改为订阅 `ready` 而非 `now` | 联动 4 |
    | `stats.js`：低电量边界由 `< 20` 改为 `<= 20` | 联动 5 |
    | `bridge.js`：暂停只写 `paused`，遗漏 `audioSpectrum: null` | 联动 5、联动 6 |
    | `bridge.js`：删除暂停期间丢弃频谱的判断 | 联动 6 |
    | `voice.js`：增加“暂停时不播放语音”的错误限制 | 联动 6 |
    | `character.js`：头像/背景改为订阅 `ready` 而非 `ui` | 联动 7 |
    | `appearance.js`：保存前直接写 `store.ui` 乐观更新 | 联动 7 |
    | `voice.js`：关闭开关时遗漏停止正在播放的语音 | 联动 8 |
    | `voice.js`：播放入口遗漏 `voiceEnabled` 校验 | 联动 8 |

  - `git diff --check` **PASS**；与 `main` 比较，`web/`、`Sources/`、`AGENTS.md`、`CLAUDE.md` 均无差异。
  - 独立子代理交付前复核：未发现 Critical / Important / Minor 实质问题；独立实跑联动 **9/9**、全量网页 **421/421**、两文件语法检查和 diff 检查均 **PASS**。此自查不替代 Claude Code 的正式审查，审查记录保持空白。
  - 实现提交：`f617301`。提交后执行 `git diff --name-only main...task/M5-01`，结果仅为 `Tests/web/linkage.test.mjs`、`Tests/web/helpers/linkage-browser.mjs` 和本任务单，范围检查 **PASS**。
  - 本次未运行 Swift 构建/测试、未打包应用，也未操作真实提醒事项或运行时配置：本任务只增加 Node 测试，以上不属于任务验收要求。
- **疑问 / 偏离**：
  - 无新增产品问题，无 TODO 测试，无需求或文件范围扩展。变异验证在临时副本执行而非原地改动，避免其他协作者或正在运行的应用读到故意破坏的产品代码。
  - 推送尚待用户确认：尝试执行 `git push -u origin task/M5-01` 时，权限自动审核以“向尚未确认的远端发送仓库内容”为由拦截了含推送的命令，命令未执行。已请求用户明确允许向现有 `origin`（`https://github.com/arvinhanye/desktop-shell-mac-.git`）发送此任务分支；目前保留本地提交，不合并 `main`。
  - 假 DOM 检查组件状态与样式开关，不声称验证了实际 CSS 渲染；`main.js` 的 phase/paused 订阅按任务要求做源码检查。真实桌面逐条验证仍属 M5-02；Swift 音频捕获停止/恢复仍属 M5.5。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
