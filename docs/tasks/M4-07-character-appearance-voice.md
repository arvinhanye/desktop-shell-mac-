# M4-07: 角色卡、外观面板和点击语音

- **状态**：review
- **里程碑**：M4
- **依赖**：M4-06（必须已合并到 `main`；用到 M4-04 的 `web/js/media.js`）
- **分支**：task/M4-07

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

第一列的角色卡显示头像组合图、名字和签名；点头像随机播放一句语音，播放期间头像发冰蓝色的光。点角色卡右上角的"外观"，在同一个网页里弹出外观面板，可以换头像和"启动栏和卡片的背景"，选了立即生效并保存，重启后保持。菜单栏关掉"点击语音"后，点头像不再出声。

## 背景与约束

- 先读 `docs/design/README.md` 的"组件的共同写法""store 里的键"和"定稿之外补充的状态和文案"（头像、背景的默认值，保存失败的提示）。照着做的部分：`index.html` 里 `character`、`appearance` 两节；`design.css` 里 `character.css`、`appearance.css` 两节；`mockup.js` 的 `renderAppearance`、头像点击和外观面板的开关。
- AGENTS.md：组件清单第 7 条和"两项功能"（点击语音、背景图库）；Bridge 的 `saveUiState` 和推送事件 `uiState`；联动规则表最后两行；"省电要求"最后一句（点击语音暂停时照样可以播放）。
- M2-03 的要求：`voice.js` 每次播放用一个**局部**的 `Audio` 对象。
- 三个组件之间只通过 store：角色卡写 `appearanceOpen = true` 和 `voiceRequest`，外观面板写 `appearanceOpen = false`，语音写 `voicePlaying`。`store.ui` 只由 bridge 写（`saveUiState` 之后 Swift 推送 `uiState`；mock 也会推送）。
- 自测可以在应用里换外观（会写 `ui.json`），结束前恢复成原来的选择。

### 1. 角色卡（`web/widgets/character.js`、`character.css`）

- DOM 照 `index.html`：`.card.character-card` > `.card-art` + `button.avatar-button`（`aria-label`"播放一句语音"）> `img`（`alt=""`、`draggable="false"`）+ `button.appearance-button`（SVG 图标 + "外观"）+ `.character-info` > `.character-name` + `.character-motto`。
- 头像：`img.src = avatarUrl(store.media, store.ui)`（`web/js/media.js`）；为 `null` 时隐藏 `img`。
- 名字是 `config.character.name`，签名是 `config.character.motto`（`null` 时为空）。
- 背景图：`.card-art` 和启动栏一样，用 `backgroundUrl(store.media, store.ui)`，`null` 时为 `none`。
- 点头像：`voicePlaying` 为真时忽略；否则 `store.set({ voiceRequest: store.get('voiceRequest') + 1 })`。要不要真的播放由语音组件判断。
- `.avatar-button` 的 `playing` class 跟着 `voicePlaying` 走。
- 点"外观"：`store.set({ appearanceOpen: true })`。
- 订阅 `config`、`media`、`ui`、`voicePlaying`。

### 2. 外观面板（`web/widgets/appearance.js`、`appearance.css`）

- DOM 照 `index.html`：`.appearance-overlay`（`data-hit`）> `.appearance-panel`（`role="dialog"`、`aria-label="外观"`、`data-glass`）> `.appearance-head`（`h2`"外观" + `.appearance-actions`）+ `.appearance-scroll`（`h3`"头像"、`.thumb-grid.avatars`、`h3`"启动栏和卡片的背景"、`.thumb-grid.backgrounds`，两个网格都是 `role="radiogroup"`）。
- `.appearance-actions` 里依次是：一个空的 `span.card-meta`（报错用）、"恢复默认"（`ghost-button`）、"完成"（`primary-button`）。
- 遮罩的 `hidden` 跟着 `appearanceOpen` 走：打开时遮罩盖住整个安全区域并接住所有点击（`data-hit`），面板有毛玻璃（`data-glass`）；关上时两样都不在了（`hidden` 的元素不会被 `hit-regions.js` 收集）。
- 缩略图：`media` 变化时重建（`ui` 变化时不重建，只更新选中状态）。每个是 `button.thumb`（背景图的再加 `.background-thumb`）、`role="radio"`、`data-id`，里面 `img`（`alt=""`、`draggable="false"`、`loading="lazy"`）。面板关着时 `display: none`，懒加载的图不会加载，`mount` 也不用等它们。
- 选中状态：头像网格里 `aria-checked="true"` 的是实际显示的那张（`ui.avatarId` 为 `null` 或找不到时是第一张）；背景网格里是 `ui.backgroundId` 那张（`null` 时一张都不选）。
- 点缩略图：发 `saveUiState { avatarId }` 或 `saveUiState { backgroundId }`；点的就是当前选中的那张时不发。**不先改界面**，等 Swift 推送 `uiState`（本机写一个小文件，几毫秒）。
- "恢复默认"：发 `saveUiState { avatarId: null, backgroundId: null }`。
- 保存失败：`.card-meta` 显示"保存失败，请再试一次"，3 秒后清空。
- 关闭：点"完成"，或者点遮罩上面板以外的地方（`event.target` 是遮罩本身）→ `store.set({ appearanceOpen: false })`。**不做 Esc 关闭**：应用里组件窗口只在输入框聚焦时才收得到按键。

### 3. 点击语音（`web/widgets/voice.js`，没有界面、没有样式）

- 作为组件挂载（这样和其他组件一样出错互不影响），`mount` 里把 `host.hidden = true`，不往里面放东西。
- 把播放逻辑写成可测试的 `createVoicePlayer({ store, createAudio, random })`（`createAudio` 默认是 `url => new Audio(url)`），`mount` 里用它。
- `voiceRequest` 变化时（不用 `immediate`）：`ui.voiceEnabled` 为假、`voicePlaying` 为真、或者 `media.voices` 为空 → 什么都不做。否则：
  - 随机选一条（`pickVoice(voices, lastId, random)`：多于一条时不和上一条重复）。
  - `const audio = createAudio(url)`（每次播放一个新对象，只放在这次播放的闭包里），`store.set({ voicePlaying: true })`，调用 `audio.play()`。
  - `ended`、`error` 事件，或者 `play()` 返回的 Promise 被拒绝 → 结束：移除监听，`voicePlaying` 设回 `false`。结束只处理一次。
- 播放中 `ui.voiceEnabled` 变成假（菜单栏关了"点击语音"）→ `audio.pause()` 并结束。
- `paused` 不影响语音：暂停时照样能播放。（暂停时头像的发光动画会被 `base.css` 停住，属于正常。）
- 清理函数：正在播放就停下并结束，退订。
- 不碰系统音频捕获（那是 M5.5 的事）。

### 4. 接入

- `main.js` 的 `WIDGETS` 加上 `'character'`、`'appearance'`、`'voice'`。

### 5. 测试

- `Tests/web/voice.test.mjs`（用假的 store、假的 `Audio`、固定的 `random`）：正常播放一次并在 `ended` 后复位；播放中再请求被忽略；`error` 和 `play()` 被拒绝都能复位、之后还能再播；`voiceEnabled` 为假时不播；播放中关掉 `voiceEnabled` 会停下并复位；`paused` 为真时照样播；`voices` 为空不播；清理时停下；`pickVoice` 不连续重复（只有一条时除外）。
- `Tests/web/appearance.test.mjs`：把"哪张是选中的"写成纯函数测（`ui.avatarId` 为 `null`、找不到、正常；`backgroundId` 为 `null`、正常）；"点了这张要不要发请求、发什么"（点当前选中的不发；头像、背景、恢复默认三种请求的参数）。

## 允许修改的文件

- `web/widgets/character.js`、`character.css`、`appearance.js`、`appearance.css`、`voice.js`（新建）
- `web/js/main.js`（只改 `WIDGETS`）
- `Tests/web/voice.test.mjs`、`Tests/web/appearance.test.mjs`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 组件不直接写 `store.ui`；`saveUiState` 只传 id 或 `null`，不传路径。
- 不在模块里保存一个全局的 `Audio` 对象；不预加载全部语音。
- 不用 `innerHTML` 插入名字、签名；不拼接素材路径（地址只用 `media` 里给的 `url`）。
- 组件 CSS 和 `design.css` 对应的一节不一致。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `scripts/test-web.sh` 全部通过，包含上面列出的新测试
- [ ] 下面两条命令都没有输出：

  ```bash
  awk -v t=web/widgets/character.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/character.css
  awk -v t=web/widgets/appearance.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/appearance.css
  ```

- [ ] `git diff --name-only main...task/M4-07` 只包含"允许修改的文件"
- [ ] （Claude Code 复验）浏览器打开 `http://127.0.0.1:8765/`（mock 数据）：控制台没有错误；角色卡和效果图一致；点头像能听到语音、头像发光，放完光停；点"外观"→ 面板和 `assets/design-screenshots/08-外观面板.jpg` 一致；点一张头像、一张背景 → 角色卡和启动栏立即换；"恢复默认"→ 第一张头像、没有背景图；点"完成"或面板外面 → 关闭

**用户手动验证**（`scripts/bundle.sh --open`；先按 M4-01 在 `config.json` 里加好 `character.motto`）：

- [ ] 角色卡显示头像组合图、"爱弥斯"和签名，和 `01-夜晚.jpg` 一致
- [ ] 点头像 → 播放一句语音，头像发冰蓝色的光；播放中再点 → 不会叠着放第二句；放完再点 → 换一句
- [ ] 菜单栏关掉"点击语音"→ 点头像没有声音；播放中关掉 → 声音立刻停
- [ ] 菜单栏"暂停动画"后点头像 → 照样有声音
- [ ] 点"外观"→ 面板弹出，桌面其他地方变暗；这时点面板外面不会点到访达图标，面板关闭；关闭后点击又能穿透给访达
- [ ] 换一张头像和一张背景 → 角色卡、启动栏立即变；退出再打开 DesktopShell → 选择还在
- [ ] 点组件和面板的过程中，前台应用一直不变

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：从最新 `main`（`58b7e03`）建立 `task/M4-07`，只涉及允许的 9 个文件。新增角色卡、外观面板、无界面的语音组件；`main.js` 仅增加三个 WIDGETS。角色卡通过共享媒体 helper 取 URL，名字和签名用纯文本；外观仅发送 id/null，等待 bridge 的 `uiState` 推送再更新选择，`ui` 更新保留缩略图节点；语音每次使用局部 Audio，处理播放结束、错误、Promise 拒绝、关闭开关和销毁，暂停动画不影响播放。
- **TDD 记录**：网页基线 345/345 PASS。语音占位实现的 RED 为 14 FAIL / 1 PASS，实现后 15/15 PASS；外观与角色卡占位实现及未注册组件的 RED 为 19 FAIL / 7 PASS，实现后 26/26 PASS。新增合计 41 项测试，覆盖选择回退、请求参数、无乐观更新、背景联动、DOM/监听/计时器清理、重复请求及迟到播放回调。
- **最终自动检查**：`scripts/test-web.sh` 386/386 PASS（0 FAIL / 0 SKIP）；`scripts/test.sh` 167/167 PASS（19 suites）；`swift build` PASS。两条任务单 CSS 比对命令均无输出；`git diff --check` 无输出。允许范围检查为 9/9 文件，规范、设计文件和本任务需求/验收/正式审查部分保持原样。
- **浏览器自测**：在 `http://127.0.0.1:8765/` 使用 mock 数据，切换头像 1→2 后角色卡同步变化；背景 folder-01→folder-02 后角色卡和启动栏同时变化；恢复默认后头像为第一张、两处背景均为 none；完成与遮罩空白点击均关闭面板；打开/关闭及选择过程中控制台 error/warn 均为空。点头像观察到 `playing` class，之后复位。自测后恢复 mock 原选择（头像 1、背景 folder-01），未在原生应用中更改用户外观。浏览器截图为 1280×720 局部视口，用于交互/布局证据，不等同于真实桌面全屏目测或声音听感验收。
- **原生打包**：`scripts/bundle.sh --open` PASS，以现有 `DesktopShell Self-Signed` 证书生成 release 包 `/Users/arvinhan/Desktop/desktop-shell/build/DesktopShell.app` 并重启，严格签名检查通过。打包的 6 个本次网页源码/样式文件与工作区逐一相同；进程已运行，启动日志仍为 `widget=icon+3 video=icon-1`。
- **独立自查**：Codex 子代理只读覆盖 9/9 文件，Critical / Important / Minor 均为 0；独立复跑新增测试 41/41 PASS、两份 CSS 比对及 diff 检查通过，并额外检查同步重入请求和播放前清理。此自查不替代 Claude Code 正式复验，下面审查区留空。
- **证据位置**：本机 `/tmp/desktopshell-m4-07-check/` 包含 baseline、两轮 RED、GREEN、最终 web/native/build/bundle/startup 日志及 `appearance-browser.jpg`。素材、截图、运行时数据均不进入提交。
- **待人工验收**：按上面的用户清单确认真实语音听感、播放中重复点击与菜单栏关闭、暂停动画后播放、外观面板打开/关闭时 Finder 点击穿透、切换并重启保持选择，以及全程前台应用不变；完成后恢复原外观选择。状态交付为 `review`，留待 Claude 正式复验与用户桌面验收。
- **疑问 / 偏离**：无范围扩展或新增设计决定；按钮字号与颜色按 `design.css`，不用旧截图的覆盖样式。原生毛玻璃区域接入仍属 M4-09，本任务只保留定稿的 `data-glass` 标记。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
