# M8-01: 去掉启动栏、压缩角色卡、加终端入口（网页）

- **状态**：todo
- **里程碑**：M8
- **依赖**：无。和 M8-02、M8-03 互不依赖；M8-04 依赖本任务（用到同步后的 `tokens.css` 和 `base.css` 的 `.key-hint`）
- **分支**：task/M8-01

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

桌面网页照 2026-10-23 的 M8 定稿改版：

- 应用启动栏去掉；
- 角色卡压成一条（高 112），播放语音时只沿圆形头像外圈亮光环（**顺带完成暂缓的 M4-11**）；
- 系统状态的电量低提示挪到标题行；
- 待办伸到底；
- 第一列系统状态下面多一条"终端"入口，点一下发 `openTerminal`。

做完后 `web/styles/tokens.css` 和 `docs/design/tokens.css` 完全一样。在应用里，点终端入口要等 M8-05 合并后才会打开面板（之前 Swift 回复 `unknown-action`，组件接住即可）。

## 背景与约束

- 先读：
  - `docs/design/README.md`：开头"M8 改版"一节、"组件的共同写法"、"store 里的键"；
  - AGENTS.md：组件清单、联动规则、Bridge 接口里标着 M8 的 `openTerminal` 和 `getConfig` 的 `terminal.hotkey`。
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

### 3. `bridge.js` 和 `mock.js`

- `bridge.js` 的 `normalizeConfig`：
  - 去掉 `apps[].iconUrl` 的处理；
  - 加上 `terminal: { hotkey: 字符串或 null }`：`config.terminal` 不是对象，或 `hotkey` 不是字符串时，都当作 `null`。
- `mock.js`：
  - 去掉 `launchApp` 和 mock 配置里的 `iconUrl`；
  - 加上 `openTerminal`（没有参数，`console.info` 一行后回复 `null`）；
  - mock 配置加上 `terminal: { hotkey: '⌥`' }`。
- 测试跟着改：
  - `Tests/web/linkage.test.mjs`：去掉启动栏和"相关应用高亮"，外观换背景只检查角色卡；
  - `Tests/web/appearance.test.mjs`：去掉 launcher 的部分；
  - `Tests/web/bridge.test.mjs`、`Tests/web/mock.test.mjs`、`Tests/web/stats.test.mjs`：按上面的改动更新；
  - 新建 `Tests/web/terminal.test.mjs`：覆盖入口的 DOM、快捷键文字的显示和隐藏、点击发送 `openTerminal`、发送失败不抛出、卸载后不再响应。

## 允许修改的文件

- `web/styles/tokens.css`、`web/styles/base.css`（修改）
- `web/widgets/character.js`、`web/widgets/character.css`、`web/widgets/stats.js`、`web/widgets/stats.css`、`web/widgets/todos.css`、`web/widgets/appearance.js`（修改）
- `web/widgets/terminal.js`、`web/widgets/terminal.css`（新建）
- `web/widgets/launcher.js`、`web/widgets/launcher.css`（删除）
- `web/js/main.js`、`web/js/media.js`、`web/js/bridge.js`、`web/js/mock.js`（修改）
- `Tests/web/linkage.test.mjs`、`Tests/web/appearance.test.mjs`、`Tests/web/bridge.test.mjs`、`Tests/web/mock.test.mjs`、`Tests/web/stats.test.mjs`（修改）
- `Tests/web/terminal.test.mjs`（新建）、`Tests/web/launcher.test.mjs`（删除）
- `Tests/web/character.test.mjs`（新建，可选，给光环的 DOM 写测试用）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改 Swift、`docs/`、`web/index.html`。
- 不做终端面板本身（M8-04、M8-05）。
- 不用 `filter: drop-shadow` 做语音光环。

## 验收标准

**可执行的检查**（实现者自测，审查者复验）：

- [ ] `scripts/test-web.sh` 全部通过
- [ ] `diff docs/design/tokens.css web/styles/tokens.css` 没有输出
- [ ] 下面这条命令没有输出（逐个检查 5 个组件的样式和定稿一致）：

  ```bash
  for n in character stats todos terminal appearance; do awk -v t=web/widgets/$n.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/$n.css; done
  ```
- [ ] `grep -rn "launcher\|launchApp\|iconUrl\|app-icons" web Tests/web` 没有输出
- [ ] `grep -c "key-hint" web/styles/base.css` 输出 `1`
- [ ] `git diff --name-only main...task/M8-01` 只有上面"允许修改的文件"
- [ ] （审查者复验）`node scripts/serve-web.mjs`，浏览器打开 `http://127.0.0.1:8765/`，对照 `http://127.0.0.1:8765/design/index.html`：
  - 第一列从上到下是日期、角色卡、系统状态、终端入口；
  - 量一下位置：角色卡在 300–412，系统状态在 428–596，终端入口在 612–660（相对安全区域顶部），没有启动栏；
  - 待办下边离安全区域底部 12；
  - 控制台 `window.shell.receive({event: 'systemStats', battery: {level: 15, charging: false, onBattery: true}, cpu: 10, memory: {usedBytes: 1, totalBytes: 2, percent: 50}})` 之后：标题行右边出现"电量低，已暂停视频和动画"，系统状态的高度不变；
  - 点头像，播放期间只有圆形头像外圈有冰蓝光环在呼吸；
  - 点终端入口，控制台出现 mock 的 `openTerminal` 日志；
  - 控制台没有错误。

**用户手动验证**：

- [ ] 用 `scripts/bundle.sh --open` 打包启动：桌面布局和上面一样，没有启动栏；点头像有光环；点终端入口什么都不发生（M8-05 之前属预期），其他组件照旧可用。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由审查者填写（Claude Code，或没参与实现的另一个 Codex 会话） ===== -->

## 审查记录

- **审查者**：
- **结论**：
- **意见**：
