# M8-01: 项目编辑、显示排序与提醒列表绑定接口

- **状态**：done
- **里程碑**：M8
- **依赖**：已确认方案与 M8-00 计划
- **分支**：task/M8-01（核实最新 main 后创建）
- **依据**：`docs/design/2026-10-22-usability-design.md` 第 3 节；全局流程见 `M8-00-usability-plan.md`。
- **编制**：Codex，本次用户明确同意代为编制。

## 目标与约束

新增三个受限接口，不返回路径或 bundle ID。名称为去首尾空白后的 1–100 个 Character；应用移首保留其他关联；项目排序不动原数组；ID 绑定优先且失联不按名称回退。旧名称绑定与原有共享归属兼容。未知 JSON 扩展键、不可见项目及非目标字段保留。

## 接口

- `AppConfig.projectOrder: [String]?`、`Project.remindersListId: String?` 均为可选，旧 JSON 缺字段可读，纯加载不写盘。
- 新建 `ProjectPreferences.swift`：`orderedProjects(_ config: AppConfig) -> [AppConfig.Project]`；`updating(_ project: AppConfig.Project, name: String?, appId: String?, reminderList: UiPatch, apps: [AppConfig.App]) -> Result<AppConfig.Project, BridgeError>`。此处 reminderList 的 `.set` 已由调用方核实为原生列表 ID，`.clear` 同时清除新旧绑定。
- `ReminderListSnapshot` 包含 `id/title/sourceTitle: String`、`canWrite: Bool`。`RemindersBackend.lists()` 返回该快照；原有映射纯函数可继续接收 `(id,title)` 投影。
- `getProjectEditOptions {projectId}` 回复：`{project:{id,name,appId}, access, binding:{status,optionId}, lists:[{id,title,source,canWrite,assignedProjectId}]}`。可空的 appId、optionId、assignedProjectId 明确为 null；access 沿用提醒权限枚举，服务未就绪用 unknown。binding.status 为 none/linked/missing/read-only/unavailable/shared。
- 原生 option ID 与 EventKit ID 映射由 RemindersStore 进程内持有；刷新保留仍有效列表的 option ID、撤销已消失项，写入再核实权限和存在性。仅编辑回复公开列表名称和来源显示标签。
- `updateProject {projectId,name?,appId?,reminderListOptionId?}` 回复公开项目对象并推送 config；缺省不动、选项 null 为解除；空补丁 invalid。无项目/应用/选项 not-found；撤权、只读或被另一项目占用 failed。
- `reorderProjects {projectIds}` 回复 null 并推送 config；形状/重复/非法 ID 为 invalid，最新可见集合不匹配为 not-found。仅变更 projectOrder，保留不可见项的原始配置。
- AppState 提供 `projectEditOptions(projectId:)`、`updateProject(projectId:name:appId:reminderListOption:)`、`reorderProjects(projectIds:)`，返回 `Result`，桥只分发和回复。保存基于最新磁盘配置；成功后更新内存、淘汰旧提醒查询再推送。

## 允许修改的文件

- `Sources/DesktopShell/{Config,ConfigStore,ProjectEditing,AppState,BridgeProtocol,Bridge,RemindersStore,TodoItems}.swift`
- `Sources/DesktopShell/ProjectPreferences.swift`（新建）
- `Tests/DesktopShellTests/{ConfigStoreTests,ProjectEditingTests,BridgeTests,PageEventTests,TodoItemsTests}.swift`
- `Tests/DesktopShellTests/ProjectPreferencesTests.swift`（新建）；现有文件私有提醒 fixture 在原文件更新，不另造通用框架。
- 本任务单的状态及交付记录。

## 实施步骤与自动验收

- [x] RED：新增 `ProjectPreferencesTests`，断言 `orderedProjects` 去重/补尾且 `config.projects.map(\.id)` 原样；应用选择后 apps 为 `[chosen, ...originalExceptChosen]`；name 改动保留 id/path/tags。`scripts/test.sh --filter ProjectPreferencesTests` 应因缺实现失败。
- [x] RED：扩充 BridgeTests，三个动作的未知键、空补丁、错误类型、null 语义和未信任来源拒绝；公开配置绝不出现 path/bundleId/remindersList/remindersListId。
- [x] RED：在 TodoItemsTests/RemindersStoreTests 增加 ID 改名仍匹配、同名不同 ID、ID 失联不回退、只读/撤权/选择后删除失败、旧共享列表排序前后归属相同、旧异步查询被淘汰的断言。
- [x] RED：ConfigStoreTests/ProjectEditingTests 在临时目录断言未知顶层/项目扩展键、无效 ID 项目、未改字段保留；保存失败不修改磁盘/内存、不发 config；更新先读取最新磁盘。
- [x] GREEN：实现模型、纯函数和受限写入；针对项目配置做 JSON 合并保存，只覆盖明确变更字段，避免 Codable 重编码丢掉扩展键。
- [x] GREEN：接入提醒选项、二次校验与 ID 写入路由；更新 hasReminders 与公共投影排序；新增项目补尾、移除清理 order。
- [x] GREEN：`scripts/test.sh`、`scripts/test-web.sh`、`swift build`、`git diff --check` 全部通过；前端尚未接入，不冒称 GUI 已完成。
- [x] 子代理只读自查本任务实际 diff，修复本次问题，记录起点/终点与本地提交。

## 用户手动验证

- [ ] 待 M8-02 接入界面后联合验证；本项不自动写入真实提醒列表。

## 交付记录

- **改动摘要**：三个原生接口、独立显示排序、按 ID 的提醒绑定及临时列表选项已实现；项目 JSON 合并保留未知字段，保存失败不改变内存或广播。起点 `c18d06805047b98d9c8ccc087f1061b1ae8b9509`，本地提交见 M8-00 汇总。
- **自测结果**：PASS：Swift 275/275（29 suites），网页 482/482，swift build，git diff --check。RED 已观察：初始排序/绑定/白名单缺口、新增项目补尾、失效应用关联三组。提醒查询淘汰、共享占用、撤权/只读/失联、未知 JSON 字段、写入回滚均有回归覆盖。只读子代理发现默认应用投影未跳过失效关联，修复后复核闭合。真实 GUI/提醒写入 SKIP，待 M8-02 联合验收。
- **疑问 / 偏离**：计划与接续分支已获确认；测试集中在 ProjectPreferencesTests 及复用既有测试，覆盖目标不变。Swift 首次沙盒缓存权限失败已用同一脚本经批准访问缓存复验，无 SDK 或校验变更。

### 审查返修（2026-10-23，与 M8-02 一起交付）

- 按正式审查第 1 条，在 `task/M8-02` 的 `54e0a80` 上恢复 `list-missing` / `list-ambiguous`，ID 绑定失联也记录 `list-missing`；日志只含项目 id。仅列表归属映射启用诊断，编辑选项探测保持静默；ID 优先、不按名称回退、同名列表按 id 取首个的行为保持。
- 新增真实 stderr 回归，覆盖缺失、歧义、ID 失联、ID 优先、空绑定及日志隐私。先观察三条诊断缺失的 RED，再通过定向 19/19（2 suites）和完整 Swift 276/276（29 suites）；`swift build`、固定证书 debug 打包通过。首次沙盒缓存失败后通过获批执行复验，未修改 SDK、证书或信任设置。
- 证据在 `build/m8-02-review-fix/`；状态恢复 `review`，留待原审查者正式复验，真实提醒事项读写仍待人工验收。

## 审查记录

- **审查者**：Claude Code（2026-10-23）
- **结论**：需修改（changes-requested），和 M8-02 一起审。完整记录见 `M8-02-project-preferences-web.md` 的审查记录；属于本任务的是第 1 条（`TodoItems.swift` 少了提醒列表找不到 / 有歧义时的日志）。

### 复验（Claude Code，2026-10-23）

- **结论**：通过，和 M8-02 一起合并到 `main`。完整记录见 `M8-02-project-preferences-web.md` 的复验部分。
