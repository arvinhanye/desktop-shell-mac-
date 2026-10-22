# M8-02: 项目管理模式与编辑面板

- **状态**：review
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

- **审查者**：待正式独立审查。
- **结论**：待审查。
- **意见**：子代理结果仅作实现自查。
