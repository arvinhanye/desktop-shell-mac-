# M4-04: 项目卡片和应用启动栏

- **状态**：done
- **里程碑**：M4
- **依赖**：M4-03（必须已合并到 `main`）
- **分支**：task/M4-04

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

第二列的"项目"卡片列出 `config.projects`：点一下选中、再点取消，每个项目有"访达"和"用 <应用> 打开"按钮。左下角横跨两列的启动栏列出 `config.apps`，显示真实的应用图标，点一下启动。选中项目时，启动栏里和它相关的应用高亮。启动栏的背景图跟随外观设置。

## 背景与约束

- 先读 `docs/design/README.md` 的"组件的共同写法""store 里的键"和"定稿之外补充的状态和文案"。照着做的部分：`index.html` 里 `projects`、`launcher` 两节；`design.css` 里 `projects.css`、`launcher.css` 两节；`mockup.js` 的 `renderProjects`、`selectProject`、`renderLauncher`。
- AGENTS.md：组件清单第 2、3 条；Bridge 的 `openProject`、`openProjectWith`、`launchApp`；联动规则表"选中某个项目卡片 → 启动栏高亮"一行。
- **联动的分工**：定稿画出了选中和高亮的样子，所以"选中项目 → 启动栏高亮"在本任务里一起做；"选中项目 → 待办筛选"在 M4-05 做。M5 再到桌面上把联动规则逐条验证一遍。

### 1. 外观取值（新建 `web/js/media.js`）

角色卡、启动栏、外观面板都要用，放在一个公用模块里：

```js
export function avatarUrl(media, ui)       // ui.avatarId 对应的 url；null 或找不到 → media.avatars 第一张的 url；一张都没有 → null
export function backgroundUrl(media, ui)   // ui.backgroundId 对应的 url；null 或找不到 → null
```

### 2. 项目卡片（`web/widgets/projects.js`、`projects.css`）

- DOM：`.card.projects-card` > `.card-head`（`h2.card-title`"项目"，后面加一个空的 `span.card-meta` 用来报错）+ `.project-list.scroll-list`。
- 每个项目一行，结构照 `mockup.js`：`div.project`（`role="button"`、`tabindex="0"`）> `div`（`.project-name`、`.project-tags` > 每个标签一个 `span.tag`）+ `.project-actions`。
- 按钮（`button.ghost-button`）：
  - 第一个是"访达"，`title`"在访达中打开"，点了发 `openProject { projectId }`。
  - 项目 `apps` 里第一个能在 `config.apps` 找到的应用，再加一个按钮：文字是应用名，`title`"用 <应用名> 打开"，点了发 `openProjectWith { projectId, appId }`。找不到就只有"访达"。
  - 按钮的点击不触发选中（`stopPropagation`）。同一个按钮的请求还没回来时，再点忽略。
  - 请求失败：`.card-meta` 显示"没能打开"，3 秒后清空（一次性定时器，再次失败重新计时）。成功什么都不显示。
- 选中：点项目行（或者它有焦点时按回车、空格）→ `selectedProject` 在这个项目的 id 和 `null` 之间切换。`.selected` 跟着 `store.selectedProject` 走。
- `config` 更新后，选中的项目已经不在了 → 把 `selectedProject` 设回 `null`。
- `config.projects` 为空：列表里放一行 `<p class="card-meta">还没有项目，在 config.json 的 projects 里添加</p>`。
- 列表用 `installScrollHints`（M4-02），清理时一起清掉。

### 3. 启动栏（`web/widgets/launcher.js`、`launcher.css`）

- DOM：`.card.launcher-card` > `.card-art` + `.app-row` > 每个应用一个 `button.app`（`title`"启动 <应用名>"）> 图标 + `span.app-name`。
- 图标：`iconUrl` 不为 `null` → `img.app-icon`（`alt=""`、`draggable="false"`）；为 `null`，或者图片加载失败（`error` 事件）→ 换成 `span.app-icon.app-icon-fallback`，内容是应用名的第一个字（按字素切，用 `Intl.Segmenter`）。
- 点击发 `launchApp { appId }`。失败只留 bridge 的日志，界面上不提示（启动栏没有放提示的位置）。
- 高亮：选中项目的 `apps` 里列出的应用加 `.related`；没有选中，或项目没有 `apps` → 都不加。
- 背景图：`.card-art` 的 `backgroundImage` 设成 `backgroundUrl(store.media, store.ui)`（`url("…")`）；为 `null` 时设成 `none`。订阅 `ui` 和 `media`，变了立即更新。
- 应用多到一行放不下时，超出的部分被卡片裁掉（定稿按一行设计），先不处理，在交付记录里写明实际能放几个。

### 4. 接入

- `main.js` 的 `WIDGETS` 加上 `'projects'`、`'launcher'`。

### 5. 测试

- `Tests/web/media.test.mjs`：`avatarUrl`、`backgroundUrl` 在 id 存在、为 `null`、找不到、列表为空时的结果。
- `Tests/web/projects.test.mjs`：把"这个项目有哪些按钮"和"点一下之后选中谁"写成纯函数（例如 `projectActions(project, apps)`、`toggleSelection(current, id)`）测：没有 `apps`、`apps` 第一个不在 `config.apps` 里、正常两个按钮；选中、取消、换选。
- `Tests/web/launcher.test.mjs`：`firstGrapheme`（中文、英文、emoji）；`relatedAppIds(config, selectedProject)`（没选中、项目没有 `apps`、正常）。

## 允许修改的文件

- `web/widgets/projects.js`、`projects.css`、`launcher.js`、`launcher.css`（新建）
- `web/js/media.js`（新建）
- `web/js/main.js`（只改 `WIDGETS`）
- `Tests/web/media.test.mjs`、`projects.test.mjs`、`launcher.test.mjs`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不新增 Bridge 动作；请求里只传 id，不传路径、应用名或 bundle id。
- 不用 `innerHTML` 插入项目名、标签、应用名。
- 组件 CSS 和 `design.css` 对应的一节不一致。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `scripts/test-web.sh` 全部通过，包含上面列出的新测试
- [ ] 下面两条命令都没有输出：

  ```bash
  awk -v t=web/widgets/projects.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/projects.css
  awk -v t=web/widgets/launcher.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/launcher.css
  ```

- [ ] `git diff --name-only main...task/M4-04` 只包含"允许修改的文件"
- [ ] （Claude Code 复验）浏览器打开 `http://127.0.0.1:8765/`（mock 数据）：控制台没有错误；两张卡片和效果图一致；点"DesktopShell"那一行 → 选中样式出现、启动栏的 Cursor 高亮（和 `assets/design-screenshots/05-选中项目.jpg` 一致），再点取消；点"访达""Cursor""启动 Safari"，控制台出现对应的 `mock: openProject desktop-shell` 等日志且项目没有被选中；Figma 显示首字"F"；项目列表滚动时上下边缘的淡出跟着变

**用户手动验证**（`scripts/bundle.sh --open`）：

- [ ] 项目卡片列出 `config.json` 里的项目；点"访达"→ 访达打开项目文件夹；点"Cursor"→ 用 Cursor 打开项目
- [ ] 把某个项目的 `path` 临时改成不存在的路径并"重新加载"，点"访达"→ 卡片标题右边出现"没能打开"，3 秒后消失；验证完改回来
- [ ] 点项目行 → 选中样式出现，启动栏里它的应用高亮；再点 → 取消
- [ ] 启动栏显示真实的应用图标，点一下启动对应应用；本机没装的应用显示名字的第一个字
- [ ] 点击启动栏、项目卡片时，前台应用不变（别的应用的键盘输入不受影响）
- [ ] （项目多于 4 个时）别的应用在前台时，鼠标移到项目列表上用触控板滚动 → 列表能滚，上下边缘淡出

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：基于已完成 M4-03 的 `main`（`3e5d4a1`）建立 `task/M4-04`。新增共享素材取值模块、项目卡片和应用启动栏，并在 `WIDGETS` 注册。项目支持选中/取消、键盘操作、访达/首个有效应用按钮、请求防重、失败提示及滚动淡出；启动栏支持真实图标/字素回退、项目关联高亮和背景图同步。组件销毁及配置重建均清理监听；旧请求回复不污染新配置。两个组件 CSS 均直接使用定稿对应分节。
- **自测结果**：
  - 基线 `scripts/test-web.sh`：**PASS 212/212**。新增 42 项测试先对占位实现运行：**RED 42/42**（均为断言失败，无导入或语法错误）；实现后全量 **PASS 254/254，FAIL 0，SKIP 0**。用户确认设计取值后，交付前再次全量运行，结果仍为 **PASS 254/254，FAIL 0，SKIP 0**。
  - 两条任务指定 `awk ... | diff -B` 命令：**PASS**，均无输出；`git diff --check`：**PASS**。当前变更限于允许列表的 10 个文件。
  - 浏览器 mock 验证（本次独立服务 `127.0.0.1:18767`）：控制台错误/警告 0，图片加载失败 0；选中 DesktopShell 后 Cursor 高亮，再点取消；访达、Cursor、Safari 按钮产生对应 mock 日志且不触发行选中；Figma 显示 `F`；项目列表顶部/中间/底部分别显示下缘/双缘/上缘淡出。
  - 启动栏容量：736px 卡片内，默认 7 个应用全部显示；临时浏览器夹具复用原组件与样式，使用相同短应用名和图标时，12 个经过 Flex 收缩后仍完整显示，第 13 个部分被裁切。较长名称可能降低容量，按任务要求保留裁切行为。
  - 独立只读复核：覆盖本次 10 个文件，复跑 254/254 通过，未发现 P1/P2 问题。此复核不代替 Claude 的正式审查。
  - 本地证据位于 `/tmp/desktopshell-m4-04-check/`：`baseline-web.log`、`red-web.log`、`green-web.log`、`final-web.log`、`selected.png`、`reference.png`、`browser-styles.json`、`capacity.json`、`capacity-13.png`。临时证据不进 git；本次验收服务和临时浏览器页已关闭。
  - **待验证**：真实桌面上的访达/指定应用打开、无效路径提示、前台键盘保持、触控板滚动及用户目测。本任务未改 Swift；未运行 Swift 测试或打包启动。
- **疑问 / 偏离**：
  - **设计冲突已由用户确认**：`design.css:29` 和现有 `web/styles/base.css:43` 都把 `.ghost-button` 定义为 `--text-sm`（12px）和淡色；效果图专用 `docs/design/mockup.css:38` 的 `#desktop button` 却以更高优先级覆盖成继承字号（14px）和白色。浏览器实测因此按钮高度为 24px/27px，且行内按钮区和标题区宽度不同。用户明确选择“保留 12px 淡色，按 design.css 交付”。实现保留定稿 CSS，未修改共享基础样式或 `docs/design/`；效果图覆盖规则交由 Claude 修正。
  - 浏览器与效果图舞台尺寸不同造成的 projects 反向 `bottom`、launcher 反向 `top` 计算值差异，不是锚点或尺寸变更；两组件定稿 CSS 对比完全通过。上述按钮差异是用户已确认的验收例外，不宣称当前效果图与实现逐像素一致。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**通过**，已合并到 `main`。代码审查和自动验收见下；手动验证 2026-10-18 完成（见最后）。
- **复验结果**（Claude Code，2026-10-18，在 `d79198d` 的独立检出上执行；打包在主目录的同一提交上执行）：
  - [x] `projects.css`、`launcher.css` 和 `design.css` 对应的一节逐行一致（两条 `awk | diff -B` 都没有输出）
  - [x] 只改了允许的 10 个文件；`git diff --check` 通过；没有 `innerHTML`、`setInterval`、`requestAnimationFrame`
  - [x] `scripts/test-web.sh` 254 项全部通过（没有 Swift 改动）
  - [x] 内置浏览器量效果图（"实际尺寸"）和正式页面：项目卡片、标题、项目行、启动栏、图标、应用名、首字图标的位置和尺寸一致（启动栏按到 `#desktop` 底边的距离比）；**唯一的差异**是项目行里按钮的字号（见下"定稿冲突"），连带项目名一栏宽 10 像素
  - [x] 交互（mock）：点"DesktopShell"→ 选中、启动栏 Cursor 高亮，再点取消；"访达""Cursor"按钮发出 `openProject desktop-shell`、`openProjectWith desktop-shell`，项目没有被选中；"课程论文"高亮 Safari 和备忘录，按钮是"访达 / Safari"；"旅行照片整理"只有"访达"、不高亮；点 Cursor 发 `launchApp cursor`；Figma 显示"F"；没有加载失败的图片；控制台没有错误
  - [x] 滚动淡出：初始状态正确（`more-below`，和 `scrollHintState` 一致）。这次内置浏览器面板处于隐藏状态，页面不渲染帧（`requestAnimationFrame` 不跑），滚动事件发不出来，所以滚动后的切换没法在这里验——M4-02 审查时已在同一个引擎里验过 `installScrollHints` 跟随滚动，组件只是调用它；桌面上的滚动留给用户验证
  - [x] `scripts/bundle.sh --open` 后日志正常
- **意见**：
  - 项目卡片：按钮 `stopPropagation`、每个按钮单独防重复；失败提示 3 秒，用代号挡住旧配置的迟到回复；配置里选中的项目没了会清掉选中；回车、空格只在行本身有焦点时生效。启动栏：图标加载失败换首字，`Intl.Segmenter` 取首字；高亮和背景图各自订阅，不重建按钮。`media.js` 和任务单一致。
  - **定稿冲突（Codex 发现，用户已定）**：`docs/design/mockup.css` 的 `#desktop button { font: inherit; color: inherit }` 带了 id 优先级，在效果图里盖过了 `design.css` 的 `.ghost-button`（12 像素、淡色），所以效果图和截图里项目按钮是 14 像素白字；正式页面的 `base.css` 用的是不带 id 的 `button`，会被按钮自己的 class 覆盖。用户选择**按 `design.css` 交付（12 像素淡色）**，实现正确。这是效果图外壳的错误，由 Claude Code 在合并后修正 `mockup.css`（同一条规则也让效果图里的"外观"按钮和"完成"按钮的字号、颜色与 `design.css` 不同，M4-07 会用到），截图里这几个按钮的字会比实际略大、略白。
- **手动验证**（2026-10-18，在 Claude Code 打包启动的 `d79198d` 上；按用户要求，`config.json` 的路径由 Claude Code 临时修改并改回，点击由用户完成，Claude Code 对照日志）：
  - [x] 点"访达""Cursor"：日志 `21:29:30 openProject desktop-shell ok`（两次）、`21:29:35 openProjectWith desktop-shell cursor ok`（两次）
  - [x] 项目路径临时改成不存在的 `~/Desktop/desktop-shell-missing-m4-04`，用户点"重新加载"（`21:29:59 reloaded config and pages`）后点"访达""Cursor"：日志 `openProject rejected: not-found`、`openProjectWith rejected: not-found`，卡片显示"没能打开"。之后改回 `~/Desktop/desktop-shell`，重启应用，`getConfig` 正常
  - [x] 点项目行出现选中样式、Cursor 高亮，再点取消（用户目测）
  - [x] 启动栏显示 Cursor、Safari 的真实图标，点击启动（日志 `launchApp cursor ok`、`launchApp safari ok`）
  - [x] 点启动栏和项目卡片时前台应用不变（用户目测）
  - 备注：第一次回复"五项都通过"时，日志里只有 `launchApp`，没有项目卡片的打开记录，所以先没合并，补做了前两项。`mockup.css` 的按钮规则已在 `main` 上修正（`7cfcc6d`）。
