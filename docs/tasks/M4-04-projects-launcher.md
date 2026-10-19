# M4-04: 项目卡片和应用启动栏

- **状态**：todo
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

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
