# M8-05: 应用启动反馈与最终回归

- **状态**：todo
- **里程碑**：M8
- **依赖**：M8-04 本地实现与自查通过
- **分支**：task/M8-05（接续 M8-04，记录起点 SHA）
- **依据**：已确认方案第 5/6 节及 M8-00 计划；Codex 经用户同意编制。

## 目标与接口

不改变 launchApp 语义。按 appId 阻止在途重复请求，其他应用正常响应。成功不追加提示；失败只在名称行显示 3 秒，保留原图标、布局、高亮和背景联动。

- 新增纯函数 `launchFailure(error) -> {label,description}`：code/message 为 not-found 时 `未找到应用` / `未找到此应用，请检查安装或配置`；其余为 `启动失败` / `启动失败，请稍后重试`。
- 完整描述进入 title/可访问描述，原应用名保留在可访问名称；name 行 danger token 表示错误，不改高度。
- 3000ms 为本功能行为常量（非 CSS 动画时长）；逐应用请求/提示 token 加渲染 generation，防止旧请求、旧计时器与卸载后回复改变新界面。
- 清理事件监听与计时器。Bridge 仍是唯一日志入口，不新增 console.error。

## 允许修改的文件

- `web/widgets/launcher.js`、`web/widgets/launcher.css`
- `docs/design/design.css`（仅 launcher 反馈规则）
- `Tests/web/launcher.test.mjs`、`Tests/web/linkage.test.mjs`
- 本任务单的状态与交付记录；M8-00 的进度及最终验证记录。

## 实施步骤与自动验收

- [ ] RED：纯函数断言 not-found 精确文案、未知错误归通用失败；不使用 iconUrl 为 null 判断未安装。
- [ ] RED：延迟 Promise 测试断言同一应用连点仅一次、不同应用可同时启动；失败 label 改变但可访问名称包含原 app.name。
- [ ] RED：假时钟断言 2999ms 仍提示、3000ms 恢复；第二次失败后第一计时器不清新提示；配置更换和 cleanup 后旧回复/计时器无效。
- [ ] 根据已批准需求更新原“失败无提示”的有效断言为有反馈断言，保留日志不重复、Promise 被接住、点击不冒泡等回归；记录测试预期变更依据。
- [ ] 运行 `node --test Tests/web/launcher.test.mjs Tests/web/linkage.test.mjs` 并记录 RED；随后最小实现并跑 GREEN。
- [ ] 子代理只读自查本项和最终累计差异；修复本次引入问题，不顺带重构。
- [ ] 完整运行 `scripts/test.sh`、`scripts/test-web.sh`、`swift build`、`git diff --check`，分别记录真实计数/警告及环境限制。
- [ ] `scripts/bundle.sh --debug` 后执行 `codesign --verify --strict build/DesktopShell.app`，记录构建包路径；不把打包成功当成真实桌面验收。
- [ ] 本地提交并整理 M8-00 交付汇总：基线/末端 SHA、允许范围、自动结果、尚待人工项、接续分支和正式审查入口。不合并、不推送。

## 用户手动验证

- [ ] 实际启动成功与配置中失效应用分别检查；失败可见、3 秒恢复、原背景和高亮保留。
- [ ] 新构建应用的项目管理、菜单布局、点击穿透、焦点、多屏、重启清单按 M8-02/03/04 汇总执行。

## 交付记录

- **改动摘要**：尚未实施。
- **自测结果**：尚未执行。
- **疑问 / 偏离**：无。

## 审查记录

- **审查者**：待正式独立审查。
- **结论**：待审查。
- **意见**：子代理结果仅作实现自查。
