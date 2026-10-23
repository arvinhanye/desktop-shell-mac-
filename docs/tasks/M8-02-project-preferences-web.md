# M8-02: 项目管理模式与编辑面板

- **状态**：changes-requested
- **里程碑**：M8
- **依赖**：M8-01 本地实现与自查通过
- **分支**：task/M8-02（接续 M8-01，记录起点 SHA）
- **依据**：已确认方案第 3 节及 M8-00 计划；Codex 经用户同意编制。

## 目标与接口

项目卡“管理”模式显示编辑/上移/下移/原有移除，日常打开行为不变；新增同网页编辑面板。使用 M8-01 的三个接口及完整响应，不新增路径传输。表单失败保留草稿，排序由成功 config 推送确认。

- 新增 store `editingProjectId: string|null`、`layoutOpen: boolean`（为后续菜单预留）；编辑面板打开清除 appearanceOpen/layoutOpen。外观打开反向清除 editingProjectId。
- 新增 `web/widgets/project-editor.js` 默认导出现有 widget 接口；`projectNameLength(text)` 按 Intl.Segmenter 字素计数，`projectEditPatch(original,draft)` 仅返回有改动字段，保持提醒绑定时省略 reminderListOptionId。
- `projects.js` 新增 `moveProjectIds(projects,projectId,direction)`，direction 为 -1/+1，边界不发送；跨页面配置变化后用最新列表生成完整排列。排序失败保留原列表并刷新配置，刷新不重置未保存表单。
- 选择项为页面内按钮列表，列表显示来源与序号消歧；只读/占用选项禁用但仍显示当前状态；权限不足不妨碍改其他字段。
- 面板关闭先 blur 隐藏文本框；项目被删除时关闭并提示。每次 options 请求/保存设 generation，旧回复和卸载后回复无效。保存进行中禁用重复提交。
- mock 复现后端字段、验证和 config/todos 事件；使用内存列表模拟同名、只读、失联，不借浏览器读取真实目录或账户。

## 允许修改的文件

- `web/widgets/{projects,appearance,character}.js`、`web/widgets/projects.css`
- `web/widgets/project-editor.js`、`web/widgets/project-editor.css`（新建）
- `web/js/{main,store,bridge,mock}.js`、`web/styles/tokens.css`
- `docs/design/{design,tokens}.css`（仅本项规则，保留 M4-11 差异）
- `Tests/web/{projects,appearance,bridge,mock,store,linkage}.test.mjs`
- `Tests/web/project-editor.test.mjs`（新建）、`Tests/web/helpers/linkage-browser.mjs`（仅补所需 DOM 行为）
- 本任务单的状态及交付记录。

## 实施步骤与自动验收

- [x] RED：`project-editor.test.mjs` 的 name 长度断言：空白非法，100 字素有效、101 非法，家庭 emoji 算 1；`projectEditPatch` 未更改返回空对象，解除提醒返回 null，保持绑定不发送字段。
- [x] RED：projects 测试断言管理按钮不选中项目；上移只发一次最新完整 projectIds，首尾禁用；失败原序保留；项目打开/拖入/移除既有测试不退化。
- [x] RED：编辑器挂载测试断言草稿取消、保存失败保留、未知/恶意标题仅 textContent、迟到 options 回复无效、远端删除关闭、非文本按钮不调用 focusInput。
- [x] RED：mock/bridge/linkage 测试覆盖 M8-01 完整选项响应、null 清除、更新后 config 与 todos 同步、权限与只读错误；使用真实 store/widget 组合。
- [x] 运行 `node --test Tests/web/project-editor.test.mjs Tests/web/projects.test.mjs Tests/web/mock.test.mjs Tests/web/bridge.test.mjs`，记录预期 RED。
- [x] GREEN：实现面板、管理模式、mock 与样式 token；仅在用户打开面板时取选项，不轮询。
- [x] GREEN：`scripts/test-web.sh`、`scripts/test.sh`、`swift build`、`git diff --check`；检查源码没有路径/bundle ID 进入新增 DOM/请求。
- [x] 在本地浏览器 mock 中检查滚动、长名称、同名选项、错误和面板互斥；随后子代理只读自查并记录本地提交。

## 用户手动验证

- [ ] 签名应用内输入中文名称、⌘A/⌘C/⌘V 与 Esc 焦点交还正常。
- [ ] 改默认应用后项目打开目标正确，其他关联高亮仍在；改名与排序不改变磁盘目录。
- [ ] 选择不同提醒列表，新增提醒进入所选列表；解除后进入默认列表；只读/撤权/列表删除有反馈。
- [ ] 列表改名后 ID 绑定仍生效；重启和另一屏幕显示一致。

## 交付记录

- **改动摘要**：增加管理模式与独立编辑面板，支持名称、默认应用、列表保持/解绑/选择和上下移；失败草稿保留、面板互斥、关闭还焦点、远端删除提示与异步版本保护。mock 使用独立列表ID/token及外部变化控制。起点 `17e3f5f524e375dae832c4c81975746fe0407951`。
- **自测结果**：PASS：网页 492/492，Swift 275/275，swift build，git diff --check。浏览器 mock 实测中文改名、Safari 默认应用、同名本地列表选择保存并重开核实；小视口面板滚动与只读/占用禁用已检查。原临时截图已失效；当前截图 `build/m8-validation/m8-project-editor.jpg`。自查的退出管理后排序失败漏刷新、撤权后旧选项不失效以及 mock 列表删除后旧待办归属残留三项均先 RED 后修复；配置版本保护阻止旧刷新覆盖新推送。真实签名应用焦点、跨屏与提醒写入仍为 SKIP。
- **累计自查补修**：发现历史共享列表第一认领者仍可重选必定保存失败的选项。回到本任务允许的 `project-editor.js` 和对应测试范围修复；沿用接续分支末端，不改任务需求或原生拒绝契约。回归先观察 disabled=false 的 RED，修复后禁用该选项并标“共享占用”；“保持当前关联”仍可保存名称且不发送绑定字段。最终网页512/512 PASS，无数据迁移。正式审查须使用整批末端，原 task/M8-02 快照不含此补丁。
- **疑问 / 偏离**：沿用原有日常悬停移除入口；管理模式替换打开按钮为编辑/排序并显示移除。新增面板测试复用 linkage-browser；store字段和组件注册清单按新契约更新，保留原断言强度。M4-11 设计差异保持。

## 审查记录

- **审查者**：Claude Code（2026-10-23）
- **范围**：M8-01 + M8-02，加上 `task/M8-05` 上给 M8-02 的修复 `d570600`。在临时检出里基于 `4cb083a` cherry-pick `d570600`（无冲突），对照 `c18d068`（main）审查。
- **用户决定（2026-10-23）**：旧 M8 只保留项目编辑（M8-01、M8-02）；M8-03、M8-04、M8-05 作废，不合并。终端改造另编为 M9。
- **结论**：需修改（changes-requested）

### 已实际执行

- `scripts/test-web.sh`：493/493 通过
- `git diff --check c18d068 HEAD`：无输出
- `swift build`：成功（冷编译 236 秒）
- `scripts/test.sh`：275 个测试、29 个套件全部通过

### 需要实现者修改（在 `task/M8-02` 上接着提交。审查者已把 `d570600` 拣到这个分支上，就是 `9cdebd1`，不用再拣）

1. **提醒列表日志的规则回退了**（`TodoItems.swift`，属于 M8-01）。AGENTS.md"配置文件示例"要求：`remindersList` 找不到时记录日志，同名列表有多个时取第一个并记录日志。改动后的 `listToProject` / `boundListID` 把 `list-missing`、`list-ambiguous` 两条日志去掉了，只剩 `list-shared`。要补回来，并给 `remindersListId` 失联也记一条（只写项目 id，不写列表名）。
2. **进度提示显示成了错误色**（`project-editor.js` / `project-editor.css`）。"读取项目设置…""正在保存…"和错误共用 `.project-editor-message`，而它是 `--color-danger`。把进度提示和错误分开：进度用 `--color-text-muted`，只有错误用 `--color-danger`（比如错误时加 `.error` 类，和 `.project-hint.error` 一样）。CSS 规则由 Claude Code 写进 `docs/design/design.css`，见下面"审查者改动"；实现者照抄。
3. **去掉作废任务留下的 `layoutOpen`**。它是给已经作废的 M8-03、M8-04 预留的，现在没有人读。从 `store.js` 的初始状态、`projects.js`、`appearance.js`、`project-editor.js` 和对应测试里删掉。

### 审查者改动（Claude Code 负责 `docs/design/`）

- `docs/design/design.css`：项目编辑的规则原来直接接在 `visualizer.css` 一节后面，没有分节标题。结果用 README 里的核对命令提取 `visualizer.css` 时，会把项目编辑的规则一起带出来，和 `web/widgets/visualizer.css` 对不上。现在拆成 `web/widgets/project-editor.css` 一节，项目卡片新增的几条挪回 `projects.css` 一节，并加上第 2 条要的 `.project-editor-message.error`。
- `docs/design/tokens.css`：`--editor-width`、`--control-disabled-opacity` 原来是一个单独的 `:root`，放在时段主题后面。现在挪进主 `:root` 的对应分组，数值不变。`web/styles/tokens.css` 由实现者照着同步。

### 合并时由 Claude Code 处理

- AGENTS.md 补上项目编辑的规范（用户已同意先审合并，措辞合并前给用户看）：
  - 三个新动作 `getProjectEditOptions` / `updateProject` / `reorderProjects`；
  - 配置字段 `projectOrder`、`remindersListId`；
  - M7"改写 config.json"的规则改成"只合并改动的字段，保留结构体不认识的键"；
  - 编辑接口会把提醒事项列表的名字和来源发给网页（以前 `getConfig` 从不给网页列表名）。
- `M8-03`、`M8-04`、`M8-05` 三张任务单的状态改成"作废（2026-10-23 用户决定）"，`M8-00` 计划里加一行说明。

### 用户手动验证（实现者改完、复验通过后，由用户在签名的 `.app` 里做；审查者先备份 `config.json`）

- M8-02 任务单里的四条：
  - 中文名称、⌘A / ⌘C / ⌘V、Esc 交还焦点；
  - 改默认应用后打开的目标正确；
  - 选择 / 解除提醒列表后，新增的提醒进对的列表；
  - 列表改名后绑定仍有效，重启后保持。
- 其中"其他关联高亮仍在"一句是针对启动栏的，M9 去掉启动栏后不再适用，这次只看默认应用。

