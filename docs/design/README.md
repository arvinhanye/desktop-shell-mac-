# M3.5 设计定稿（2026-10-18）

用户在 Safari 里确认了效果图。M4 照这里实现，**Codex 不自行做视觉决定**；这里没有覆盖到的视觉问题，在交付记录里提问。

## 文件

| 文件 | 内容 | M4 怎么用 |
|---|---|---|
| `tokens.css` | 全部 token 数值：配色、字体、字号、间距、圆角、阴影、组件位置和尺寸、四个时段主题、有毛玻璃时的底色浓度 | 原样复制到 `web/styles/tokens.css` |
| `fonts.css` | 字体声明（字体文件在 `media/fonts/`，不进 git） | 原样复制到 `web/styles/fonts.css` |
| `design.css` | 组件样式，按目标文件分节（`base.css` 追加的部分、每个 `web/widgets/<名字>.css`） | 每节照抄到对应文件 |
| `index.html` | 效果图页面。`<main id="desktop">` 里每个 `<section class="widget" data-widget="…">` 就是一个组件，里面的结构就是组件要生成的 DOM（id 只是效果图用的，组件里可以不要） | 照着生成 DOM |
| `mockup.js` | 效果图的模拟数据和交互（选中项目、勾选、外观面板、律动条等），是交互的参考 | 只作参考，组件按任务单重写 |
| `mockup.css` | 效果图外壳：模拟的菜单栏、程序坞、访达图标、底部控制栏 | **不属于设计**，不要抄 |
| `parameters.md` | 从美化包皮肤配置整理的参数表，以及头像超分的做法 | 背景资料 |

查看：`node scripts/serve-web.mjs`，然后用 Safari 打开 `http://127.0.0.1:8765/design/index.html`（开发服务器不会把 `/design/` 自动指到 `index.html`）。底部控制栏可以切换时段和各种状态，"实际尺寸"按 1:1 显示，"播放语音"让头像一直保持播放中的光环。

## 截图

截图里有壁纸和头像，素材版权属于原作者，仓库是公开的，所以截图**不进 git**，存在 `assets/design-screenshots/`（3584 × 2240，2 倍）：夜晚、早晨、白天、傍晚、选中项目、电量低和暂停、提醒事项未授权、外观面板、隐藏图标看组件区。截图里的壁纸是 4K 视频第 3 秒的静帧。

**截图和定稿有一处出入**（2026-10-18 M4-04 审查时发现）：截图时 `mockup.css` 里有一条 `#desktop button { font: inherit; color: inherit }`，带 id 优先级，盖过了 `design.css` 里按钮自己的字号和颜色。所以截图里项目卡片的"访达 / Cursor"按钮、外观面板的"恢复默认"是 14 像素白字（定稿是 12 像素淡色），角色卡的"外观"按钮是 14 像素（定稿 12 像素），"完成"按钮的字是白色（定稿是深色 `--color-accent-contrast`）。用户确认**以 `design.css` 为准**，`mockup.css` 已改正，截图没有重拍；对照截图时这几个按钮的字以 `design.css` 为准。

## 定下来的几件事

- **布局**：组件放在左侧两列（每列 360，间隔 16，离安全区域左边 32），启动栏横跨两列在左下，律动条在底部中间偏右，右侧 240 留给两列访达图标。用户整理桌面，只留两列图标。
- **底板**：半透明夜靛打底，再叠一层玫瑰色；圆角 2，不加阴影。应用里底板下面垫原生毛玻璃（`NSVisualEffectView`，`.hudWindow`），网页底色降到 45%（`:root[data-glass="on"]`）。探针结论见 AGENTS.md"技术探针"。
- **字体**：日期数字 Gobold，月份、时间、竖排星期 Porter，问候语、标题、角色名用思源宋体，正文 Google Sans。
- **问候语**：`"<title>，<user.name>"`，名字用强调色。
- **角色卡**：头像组合图（签名 + 圆形头像，480 × 300 的 2 倍图）整张显示在卡片左上，下面是名字和签名（`config.character.motto`），右上角"外观"按钮打开外观面板。点头像播放语音，播放期间**只沿圆形头像外圈**有一圈冰蓝色的光环呼吸（2026-10-19 用户定稿：原来是整张组合图的 `drop-shadow`，会沿签名柔边和图里半透明的部分零散地亮）。光环是按钮里一个和圆形头像重合的 `span.avatar-ring`，位置和直径见 tokens 的 `--avatar-ring-*`，30 张头像的圆都在同一个位置。**实现（M4-11）暂缓**：应用里目前仍是 M4-07 的整张图 `drop-shadow` 发光，`web/widgets/character.css` 和这里的 `character.css` 一节、`web/styles/tokens.css` 和这里的 `tokens.css` 暂时不一致，属预期；做 M4-11 时一起同步。
- **项目、待办**：列表可以滚动，上下还有内容时边缘淡出，鼠标移上去出现细滚动条。今天完成的提醒排在最后，划掉显示，可以再点一下取消完成。
- **启动栏**：真实应用图标（Swift 导出），应用没装时显示名字的第一个字。
- **视频**：4K 原片，不缩小。
- **窗口层级**：组件窗口在系统桌面小组件之上（图标层 +3）。

## 定稿之外补充的状态和文案（2026-10-18，写 M4 任务单时定）

效果图没有画到、但组件必须处理的情况，统一按这里做，样式只用已有的类：

| 位置 | 情况 | 显示 |
|---|---|---|
| 外观 | `avatarId` 为 `null` 或找不到 | 用 `media.avatars` 的第一张（按 id 排序后是 `1`）；一张都没有就不显示头像图 |
| 外观 | `backgroundId` 为 `null` 或找不到 | 角色卡、启动栏不显示背景图（"恢复默认"就是这个效果） |
| 项目卡片 | 打开失败（`openProject` / `openProjectWith` 被拒） | 卡片标题右边的 `.card-meta` 显示"没能打开"，3 秒后清空 |
| 项目卡片 | `config.projects` 为空 | 列表里一行 `<p class="card-meta">`："还没有项目，在 config.json 的 projects 里添加"（M7 起改成"还没有项目，在上面粘贴文件夹路径，或把文件夹拖进来"） |
| 待办 | 还没收到第一次 `todos` 推送（`todosAccess` 为 `unknown`） | 输入框隐藏，列表空，不显示文字 |
| 待办 | `notDetermined` | 输入框隐藏；`li.todo-denied`：`<strong>正在等待提醒事项权限</strong>在弹出的对话框里点「允许」` |
| 待办 | `denied` / `restricted` / `writeOnly` | 输入框隐藏；`li.todo-denied`：`<strong>还不能读取提醒事项</strong>到「系统设置 → 隐私与安全性 → 提醒事项」里允许 DesktopShell`（效果图原文） |
| 待办 | 新增失败 / 勾选失败 / 文字超过 500 字 | `.todo-hint` 显示"没能添加，请再试一次" / "没能更新这条提醒，请再试一次" / "最多 500 个字"；输入框内容变化或下一次操作成功后清除，恢复原来的提示（如果有） |
| 系统状态 | 还没收到 `systemStats`，或某项数值缺失 | 数值显示"—"，进度条为空，折线不画 |
| 系统状态 | 电量 `level` 为 `null`（没有电池） | 电量数值"—"，小字为空，进度条为空 |
| 系统状态 | 电量的小字 | 用电池："% 用电池"；接电源并在充电："% 充电中"；接电源没在充电："% 电源"（效果图原文是"用电池""电源"） |
| 项目卡片（M7） | 添加成功（输入框回车或拖入） | 清空输入框；`#project-meta`（标题右边的 `.card-meta`）显示"已添加「名字」"，3 秒后清空；新项目排在列表最后，列表滚到底 |
| 项目卡片（M7） | 添加被拒 | `.project-hint.error` 显示：`not-found` →"找不到这个文件夹"；`not-directory` →"这不是文件夹"；`outside-home` →"只能添加个人文件夹（~）里的文件夹"；`duplicate` →"这个文件夹已经是项目了"；其他错误 →"没能添加，请再试一次"。输入框内容变化或下一次添加成功后清除 |
| 项目卡片（M7） | 一次拖入多个文件夹 | 逐个添加；成功的合并成一条"已添加 N 个项目"（只有一个时用"已添加「名字」"）；有失败的，`.project-hint.error` 显示第一个失败的原因 |
| 项目卡片（M7） | 移除 | 行尾 `.project-remove`（×）第一次点：加 `.confirm`、文字换成"移除？"，3 秒内再点才移除，否则恢复成 ×；同一时间只有一行在确认状态；点它不会选中这一行。移除成功：`#project-meta` 显示"已移除「名字」，文件夹没有动"，3 秒后清空；被拒：`#project-meta` 显示"没能移除"，3 秒后清空 |
| 项目卡片（M7） | 文件夹拖到卡片上方 | 卡片加 `.drop-target`，显示 `.project-drop`（"松开，添加为项目"）；离开或松开后去掉 |
| 外观面板 | 保存失败（`saveUiState` 被拒） | 面板右上角按钮左边加一个 `.card-meta`，显示"保存失败，请再试一次"，3 秒后清空。**没有错误时这个元素设成 `hidden`**：空着也会多占一个间距、打乱标题和按钮的基线对齐（M4-07 审查时发现）；显示错误的 3 秒里按钮下移约 6 像素，可以接受 |

## 组件的共同写法（M4）

M4-03 到 M4-08 的每个组件都照这里写，任务单里不再重复。

- **文件**：`web/widgets/<名字>.js` 默认导出 `{ name, css, mount(host, ctx) }`。`name` 和文件名相同；`css` 是 `'<名字>.css'`（没有样式就不写）；`mount` 返回清理函数。`host` 是 `mountWidgets` 建好的 `<section class="widget" data-widget="<名字>">`，`ctx` 是 `{ store, bridge, hitRegions }`。在 `web/js/main.js` 的 `WIDGETS` 里加上名字才会挂载。
- **DOM**：照 `index.html` 里对应的 `section` 生成，类名、层级、`role`、`aria-*`、`alt`、`draggable` 都一样；效果图里的 `id` 不用照抄。`section` 上的 `aria-label` / `aria-hidden` 设在 `host` 上。
- **样式**：`design.css` 里对应的那一节**原样**放进 `web/widgets/<名字>.css`，不加不减、不改数值，文件里也不加别的注释。核对命令（没有输出才算一致）：

  ```bash
  awk -v t=web/widgets/<名字>.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/<名字>.css
  ```

  定稿没有覆盖的视觉问题，先在交付记录里提问，不要自己补样式。
- **挂载**：`mount` 同步建好 DOM、订阅 store 就返回，不等图片加载之类的耗时操作（Swift 要等 `main.js` 跑完才推送首批事件，见 M3-05 审查记录）。
- **通信**：组件之间只通过 store。只写下表里归自己写的键；读别的键用 `store.subscribe(key, fn, { immediate: true })`。清理函数里退订、清掉定时器和事件监听。
- **用户数据**：项目名、提醒标题、名字、签名、应用名一律用 `textContent`；`innerHTML` 只用于写死的图标 SVG。动态样式用 `element.style.xxx` 或 `element.style.setProperty`，不写 `style="…"` 字符串（页面的 CSP 不允许内联样式属性）。
- **Bridge**：只传 id。`bridge.send` 失败会 reject，调用处要接住（`.catch` 或 `try`），不留下未处理的 Promise。bridge 已经记了日志，组件不再 `console.error`。
- **点击**：可点击的东西必须在 `.card` 里或带 `data-hit`，否则点击会穿透给访达；纯展示的组件（时钟、问候语、律动条）两样都不加。`hit-regions.js` 会自动发现变化，组件不用调用 `hitRegions`。
- **键盘**：文本输入框的焦点由 `web/js/keyboard-focus.js` 统一处理（获得焦点时发 `focusInput`，Esc 和失焦时发 `blurInput`），组件不调用 `focusInput` / `blurInput`，也不自己处理 Esc。应用里组件窗口只在输入框聚焦时才收得到按键，所以别的地方不要依赖键盘操作。
- **动画**：没东西要画时停下来（不只是暂停时），不留空转的 `requestAnimationFrame` 或定时器；同一帧要改的东西合并在一个 `requestAnimationFrame` 里。`base.css` 的 `:root[data-paused]` 已经会停住所有 CSS 动画。
- **测试**：格式化、筛选、取值这类逻辑写成导出的纯函数，放在 `Tests/web/<名字>.test.mjs` 里用 `node --test` 测；DOM 的样子在浏览器里看（`node scripts/serve-web.mjs`，打开 `http://127.0.0.1:8765/`，mock 数据和效果图一致）。

## store 里的键

| 键 | 谁写 | 谁读 | 说明 |
|---|---|---|---|
| `ready`、`config`、`media`、`ui`、`todos`、`todosAccess`、`safeArea`、`paused`、`systemStats`、`audioSpectrum` | `bridge.js`（`getConfig` 回复和 Swift 推送） | 各组件、`main.js` | 组件**不写**这些键。换外观靠 `saveUiState`，之后 Swift 推送 `uiState` 更新 `ui`；增删项目后 Swift 推送 `config` 更新 `config`（M7） |
| `projectDrop` | `bridge.js`（Swift 推送的 `projectDrop` 事件，M7） | 项目卡片 | `{ over: 布尔值, result: null 或 { added: [{id, name}], error: 错误码或 null } }`；`over` 为真时卡片显示拖入提示；`result` 只在一次拖放结束时带上，组件据此显示"已添加…"或错误提示 |
| `phase` | 时钟 | `main.js`（设 `<html data-phase>`） | `morning` / `day` / `evening` / `night` |
| `now` | 时钟 | 问候语、待办 | 当前这一分钟开始时的时间戳（毫秒），每分钟写一次；初始 `null`，读的一方遇到 `null` 按当前时间算 |
| `selectedProject` | 项目卡片 | 待办、启动栏 | 项目 id 或 `null` |
| `appearanceOpen` | 角色卡（打开）、外观面板（关闭） | 外观面板 | 布尔值 |
| `editingProjectId` | 项目卡片（管理模式里点"编辑"）、编辑项目面板（关闭） | 编辑项目面板 | 项目 id 或 `null`（M8）。打开时清掉 `appearanceOpen`，外观面板打开时也清掉它，两个面板互斥 |
| `voiceRequest` | 角色卡（点头像时加 1） | 语音 | 计数，只看变化 |
| `voicePlaying` | 语音 | 角色卡（头像发光） | 布尔值 |
