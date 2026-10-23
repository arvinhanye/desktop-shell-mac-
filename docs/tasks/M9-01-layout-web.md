# M9-01: 去掉启动栏、压缩角色卡、加终端入口（网页）

- **状态**：done
- **里程碑**：M9
- **依赖**：无（基于已合并 M8 项目编辑的 main）。和 M9-03 互不依赖；M9-02 依赖本任务（网页先不再需要 `apps`，Swift 才能停发），M9-04 依赖本任务（用到同步后的 `tokens.css` 和 `base.css` 的 `.key-hint`）
- **分支**：task/M9-01

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

桌面网页照 2026-10-23 的 M9 定稿改版：

- 应用启动栏去掉；
- 角色卡压成一条（高 112），播放语音时只沿圆形头像外圈亮光环（**顺带完成暂缓的 M4-11**）；
- 系统状态的电量低提示挪到标题行；
- 待办伸到底；
- 第一列系统状态下面多一条"终端"入口，点一下发 `openTerminal`；
- 项目行只剩"访达"按钮，去掉"用 <应用> 打开"；编辑项目面板去掉"默认打开应用"（2026-10-23 用户定）。

做完后 `web/styles/tokens.css` 和 `docs/design/tokens.css` 完全一样。在应用里，点终端入口要等 M9-05 合并后才会打开面板（之前 Swift 回复 `unknown-action`，组件接住即可）。

## 背景与约束

- 先读：
  - `docs/design/README.md`：开头"M9 改版"一节、"组件的共同写法"、"store 里的键"；
  - AGENTS.md：组件清单、联动规则、Bridge 接口里标着 M9 的 `openTerminal` 和 `getConfig` 的 `terminal.hotkey`。
- 定稿：
  - `docs/design/index.html`：`character`、`stats`、`terminal` 三节的 DOM；
  - `docs/design/design.css`：base.css、character、stats、todos、terminal 各节。`mockup.js` 只作交互参考。
- **Codex 不自行做视觉决定**：样式、文案都照定稿。

### 1. 样式和 token

- `web/styles/tokens.css` 整个换成 `docs/design/tokens.css`（M4-11 一并完成后两边不再有差别）。
- `web/styles/base.css`：
  - 把 `design.css` 的 base.css 一节里新增的 `.key-hint` 加进去；
  - `.card-art` 的注释照定稿改成"角色卡"。
- 下面几个组件的 `.css` 换成 `design.css` 对应一节的最新内容：`character.css`、`stats.css`、`todos.css`；新建的 `terminal.css` 也一样。
- 删除 `web/widgets/launcher.css`。

### 2. 组件

- **删除启动栏**：
  - 删掉 `web/widgets/launcher.js` 和 `Tests/web/launcher.test.mjs`；
  - `web/js/main.js` 的 `WIDGETS` 去掉 `launcher`，在 `stats` 后面加 `terminal`；
  - `media.js` 里提到启动栏的注释一并改掉。
- **角色卡**（`character.js`）：
  - 头像按钮里在 `img` 后面加 `<span class="avatar-ring" aria-hidden="true">`（照 `index.html`）；
  - 播放中的 `.playing` 类照旧由 `voicePlaying` 控制。光环的位置、尺寸、动画全在 CSS 和 tokens 里，JS 不算。
  - M4-11 任务单（`docs/tasks/M4-11-avatar-voice-ring.md`）的目标并入本任务，它的状态由 Claude Code 在审查时改。
- **系统状态**（`stats.js`）：
  - 电量低提示从卡片底部的 `p.power-hint` 改成标题行里的 `span.card-meta.power-hint`，放在 `.card-title` 后面；
  - 文字改成"电量低，已暂停视频和动画"；
  - 显示条件不变（卡片上的 `.low-battery`）。
- **外观面板**（`appearance.js`）：小标题"启动栏和卡片的背景"改成"角色卡的背景"。
- **终端入口**（新建 `web/widgets/terminal.js`，`name` 为 `terminal`，`css` 为 `terminal.css`）：
  - DOM 照 `index.html` 的 `terminal` 一节：一个 `button.card.terminal-entry`，里面是图标 SVG、`.terminal-entry-label`"终端"、`kbd.key-hint`；
  - `host` 的 `aria-label` 为"终端"；
  - `kbd` 的文字取 `store.config.terminal.hotkey`。它是字符串时显示；为 `null` 或没有时，`kbd` 设成 `hidden`；
  - 点按钮发送 `bridge.send('openTerminal')`，失败接住，不显示任何提示（Swift 已记日志）。

### 3. 项目卡片和编辑面板（去掉"用应用打开"）

- `projects.js`：
  - `projectActions` 只返回"访达"（`openProject`），不再读 `project.apps` 和 `config.apps`；
  - 管理模式不受影响。
- `project-editor.js`：
  - 去掉"默认打开应用"小标题和那组按钮；
  - `projectEditPatch` 不再比较、也不再发送 `appId`；
  - `getProjectEditOptions` 回复里没有 `project.appId` 也照常工作。
- 对应的测试一起改，并加一条：项目行里没有第二个打开按钮，编辑面板里没有"默认打开应用"。

### 4. `bridge.js` 和 `mock.js`

- `bridge.js` 的 `normalizeConfig`：
  - `config.apps` 不再是必需的：只要求 `greetings`、`projects` 是数组，`apps` 和项目的 `apps` 都不再读取、不再放进 store（M9-02 起 Swift 不发了）；
  - 去掉 `apps[].iconUrl` 的处理；
  - 加上 `terminal: { hotkey: 字符串或 null }`：`config.terminal` 不是对象，或 `hotkey` 不是字符串时，都当作 `null`。
- `mock.js`：
  - 去掉 `launchApp`、`openProjectWith`，mock 配置里去掉 `apps` 和项目的 `apps`；`updateProject` 不再接受 `appId`（带上就回复 `invalid`），`getProjectEditOptions` 的回复不带 `appId`；
  - 加上 `openTerminal`（没有参数，`console.info` 一行后回复 `null`）；
  - mock 配置加上 `terminal: { hotkey: '⌥`' }`。
- 测试跟着改：
  - `Tests/web/linkage.test.mjs`：去掉启动栏和"相关应用高亮"，外观换背景只检查角色卡；
  - `Tests/web/appearance.test.mjs`：去掉 launcher 的部分；
  - `Tests/web/bridge.test.mjs`、`Tests/web/mock.test.mjs`、`Tests/web/stats.test.mjs`、`Tests/web/projects.test.mjs`、`Tests/web/project-editor.test.mjs`：按上面的改动更新；
  - 新建 `Tests/web/terminal.test.mjs`：覆盖入口的 DOM、快捷键文字的显示和隐藏、点击发送 `openTerminal`、发送失败不抛出、卸载后不再响应。

## 允许修改的文件

- `web/styles/tokens.css`、`web/styles/base.css`（修改）
- `web/widgets/character.js`、`web/widgets/character.css`、`web/widgets/stats.js`、`web/widgets/stats.css`、`web/widgets/todos.css`、`web/widgets/appearance.js`（修改）
- `web/widgets/terminal.js`、`web/widgets/terminal.css`（新建）
- `web/widgets/launcher.js`、`web/widgets/launcher.css`（删除）
- `web/widgets/projects.js`、`web/widgets/project-editor.js`（修改）
- `web/js/main.js`、`web/js/media.js`、`web/js/bridge.js`、`web/js/mock.js`（修改）
- `Tests/web/linkage.test.mjs`、`Tests/web/appearance.test.mjs`、`Tests/web/bridge.test.mjs`、`Tests/web/mock.test.mjs`、`Tests/web/stats.test.mjs`、`Tests/web/projects.test.mjs`、`Tests/web/project-editor.test.mjs`（修改）
- `Tests/web/helpers/linkage-browser.mjs`（修改，仅限去掉启动栏、应用相关的部分）
- `Tests/web/terminal.test.mjs`（新建）、`Tests/web/launcher.test.mjs`（删除）
- `Tests/web/character.test.mjs`（新建，可选，给光环的 DOM 写测试用）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改 Swift、`docs/`、`web/index.html`。
- 不做终端面板本身（M9-04、M9-05）。
- 不用 `filter: drop-shadow` 做语音光环。

## 验收标准

**可执行的检查**（实现者自测，审查者复验）：

- [ ] `scripts/test-web.sh` 全部通过
- [ ] `diff docs/design/tokens.css web/styles/tokens.css` 没有输出
- [ ] 下面这条命令没有输出（逐个检查 5 个组件的样式和定稿一致）：

  ```bash
  for n in character stats todos terminal appearance projects project-editor; do awk -v t=web/widgets/$n.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/$n.css; done
  ```
- [ ] `grep -rn "launcher\|launchApp\|iconUrl\|app-icons\|openProjectWith\|appId" web Tests/web` 没有输出
- [ ] `grep -c "key-hint" web/styles/base.css` 输出 `1`
- [ ] `git diff --name-only main...task/M9-01` 只有上面"允许修改的文件"
- [ ] （审查者复验）`node scripts/serve-web.mjs`，浏览器打开 `http://127.0.0.1:8765/`，对照 `http://127.0.0.1:8765/design/index.html`：
  - 第一列从上到下是日期、角色卡、系统状态、终端入口；
  - 量一下位置：角色卡在 300–412，系统状态在 428–596，终端入口在 612–660（相对安全区域顶部），没有启动栏；
  - 待办下边离安全区域底部 12；
  - 控制台 `window.shell.receive({event: 'systemStats', battery: {level: 15, charging: false, onBattery: true}, cpu: 10, memory: {usedBytes: 1, totalBytes: 2, percent: 50}})` 之后：标题行右边出现"电量低，已暂停视频和动画"，系统状态的高度不变；
  - 点头像，播放期间只有圆形头像外圈有冰蓝光环在呼吸；
  - 点终端入口，控制台出现 mock 的 `openTerminal` 日志；
  - 项目行只有"访达"一个打开按钮；管理 → 编辑，面板里只有显示名和提醒事项列表；
  - 控制台没有错误。

**用户手动验证**：

- [ ] 用 `scripts/bundle.sh --open` 打包启动：桌面布局和上面一样，没有启动栏；点头像有光环；点终端入口什么都不发生（M9-05 之前属预期）；项目行只有"访达"，编辑面板改名、关联提醒列表照旧能保存（Swift 还没改时会照旧收到 `apps`，网页忽略即可）；其他组件照旧可用。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：从最新 `main`（`d15e0a1`，2026-10-23 fetch 确认）创建 `task/M9-01`。移除启动栏和项目的应用打开/默认应用选项；同步全部 token 与角色卡、系统状态、待办样式；头像改为独立圆环。新增终端入口（快捷键随配置更新，无配置隐藏，点击发送 `openTerminal`，失败静默接住，卸载清理）。bridge 忽略旧应用配置，mock 接入 M9 白名单，联动测试同步。仅修改本任务允许文件；M4-11 状态留给正式审查者。
- **自测结果**：
  - 基线网页测试 495/495；更新后 `scripts/test-web.sh` **491/491 PASS**（0 fail / skip）。新增或更新测试先见预期失败，再验证通过；移除了退役功能的测试。
  - `diff docs/design/tokens.css web/styles/tokens.css`、任务指定 7 份组件 CSS 对照、禁用符号 grep 均无输出；`.key-hint` 计数为 1；`git diff --check` 通过。独立子代理只读自查未发现已确认缺陷，仅算交付前自查，不代替正式审查。
  - IAB 加载本机 mock 页面，实测相对安全区域：角色卡 300–412、系统状态 428–596、终端入口 612–660，待办底部留白 12。项目只见“访达”打开按钮，编辑面板只有名称与提醒列表；终端按钮产生 `mock: openTerminal`，快捷键显示 ⌥`，控制台无 error / warn。
  - 日志与截图：`build/m9-validation/M9-01-web.log`、`M9-01-browser.png`（未入库）。浏览器透明背景不含原生视频/毛玻璃，窗口视口较小，不作为真实桌面观感验收。
- **疑问 / 偏离**：无范围偏离。真实 `.app` 中的光环播放观感、低电量标题布局、Finder 穿透与项目编辑保存仍待用户/正式审查者按上方步骤验收；本轮没有启动或替换运行中的应用。终端面板尚待 M9-05，当前原生点击入口返回 `unknown-action` 属任务预期。任务分支推送被自动审批拦截（远端归属及代码外发授权未确认），暂作本地交付。

<!-- ===== 以下由审查者填写（Claude Code，或没参与实现的另一个 Codex 会话） ===== -->

## 审查记录

- **审查者**：Codex（独立会话，2026-10-23；未参与实现）。
- **结论**：通过。用户已确认真实桌面的新布局、圆形语音光环、终端入口及其他组件正常；项目编辑保存的磁盘核对尚未完成，用户明确同意该项记为“待确认”后先合并。以 `git merge --no-ff` 合并至 `main`，状态改为 `done`。
- **意见**：
  - 审查对象 `cde6621`，基线 `d15e0a1`。全部 28 个变更文件已审（含 24 个代码/测试文件、3 个删除文件及任务单），覆盖率 100%，无跳过，无已确认 P1/P2 缺陷，无超出允许范围的修改。
  - 在独立审查 worktree 复验：`scripts/test-web.sh` 491/491 通过；token 完全一致；7 份组件 CSS 与定稿一致；禁用符号扫描无输出；`.key-hint` 定义 1 处；`git diff --check` 通过。附加 `scripts/test.sh --jobs 4` 276/276（29 suites）通过。
  - 浏览器实测相对安全区域：角色卡 300–412、系统状态 428–596、终端入口 612–660；待办底边留白 12。通过独立测试按钮注入低电量事件后提示位于标题行，状态卡仍为 168px；语音期间光环为 93px 圆形并使用 `voice-pulse`。项目只有“访达”打开按钮，编辑面板只有名称与提醒列表；终端点击记录 `mock: openTerminal`，浏览器无 error/warn。浏览器检查不替代真实桌面观感。
  - `scripts/bundle.sh --debug` 及最终固定证书签名/验签通过。受限环境首次看不到签名身份，正常权限复验成功，未更改证书信任或系统权限。随后用 `scripts/bundle.sh --debug --open` 启动正确测试包；只读核实进程来自审查目录，启动日志为 `widget=icon+3 video=icon-1`，点击终端的原生日志为预期 `unknown-action`。
  - **待确认（用户同意不阻塞合并）**：项目改名、提醒列表关联后的真实保存。审查期间配置内容和修改时间未变，不能将用户的总体观感反馈记作已验证持久化；后续需要实际保存并核对磁盘。M4-11 任务单状态依任务要求仍由 Claude Code 维护，本次未改。
  - 证据保存在本审查 worktree 的 `build/m9-review/`，未入库。审查未修改业务逻辑。
