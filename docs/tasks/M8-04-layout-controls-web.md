# M8-04: 两种布局、组件显隐与应用栏收缩

- **状态**：todo
- **里程碑**：M8
- **依赖**：M8-03 本地实现与自查通过
- **分支**：task/M8-04（接续 M8-03，记录起点 SHA）
- **依据**：已确认方案第 4 节及 M8-00 计划；Codex 经用户同意编制。

## 目标与接口

- 新增 `web/widgets/layout.js`、`layout.css`，默认导出 widget 接口。面板有标准/工作优先两项、八个显隐复选项、恢复布局默认、完成。保存串行、失败留旧值与提示，只使用 M8-03 局部补丁；恢复只发标准及完整全部 true。
- 新增 `web/js/layout.js` 导出 `installLayout({store,doc,win,scheduleRegions}) -> cleanup`；应用宿主 hidden、位置 token、项目隐藏清空 selectedProject、隐藏前 blur，以及页面可见恢复时调度三类区域。保留时间服务与其他订阅，不卸载时钟。
- 所有面板互斥；角色卡隐藏时原生菜单仍可打开布局面板。关闭隐藏输入前先交还焦点。
- standard 为原有列；work-first 仅交换两列内容。launcher 使用独立安全区左侧锚点，不随 column-1 交换。律动位置、组件内部视觉、右侧图标留白保持。
- launcher 宽度采用内容宽度，max-width 为原双列宽与实际组件可用区的小值，保留原高度和 padding。应用 tile 不收缩，横向滚动，名称单行省略；零应用隐藏底板。恢复应用时尊重 widgetVisibility.launcher。
- 预设使用 `data-layout` 时仍显式 schedule hit/drop/glass；不得指望原观察器监听该属性。统一出口由 main 持有三种 reporter，并在 mount 后安装布局监听。
- visualizer 的暂停条件扩为 paused、document.hidden 或显隐关闭；停绘制及过期计时，恢复时只用未过期的最新状态/后续频谱。组件隐藏不触发全局 paused 或改音频捕获策略。

## 允许修改的文件

- `web/js/{main,store,layout-state,hit-regions,drop-regions,glass-regions}.js`、`web/js/layout.js`（新建）
- `web/widgets/{launcher,visualizer,appearance,character,project-editor}.js`、`web/widgets/launcher.css`
- `web/widgets/layout.js`、`web/widgets/layout.css`（新建）
- `web/styles/{base,tokens}.css`、`docs/design/{design,tokens}.css`（只同步本项布局规则，保留 M4-11 差异）
- `Tests/web/{launcher,visualizer,hit-regions,drop-regions,glass-regions,appearance,project-editor,linkage}.test.mjs`
- `Tests/web/layout.test.mjs`（新建）、`Tests/web/helpers/linkage-browser.mjs`
- 本任务单的状态及交付记录。

## 实施步骤与自动验收

- [ ] RED：layout.test 断言两预设显隐互不覆盖，恢复保留 avatar/background/voice，保存失败不写 store.ui，串行保存不覆盖其他组件。
- [ ] RED：真实组件联动断言 clock 隐藏后 now/phase 继续更新、项目隐藏清空选择、文本框先 blur、全部隐藏后 openLayout 仍使面板可见。
- [ ] RED：区域测试断言交换/隐藏后 hit、drop、glass 清除旧矩形且按帧去重；页面可见恢复补报；隐藏项目不接收拖放。
- [ ] RED：visualizer 测试断言 paused/页面隐藏/组件隐藏无绘制、无空转，恢复不渲染过期频谱，原音频策略未改变。
- [ ] RED：launcher 测试覆盖 0/1/2/多应用 DOM、无应用底板消失、显隐优先；浏览器验收实际宽度、图标尺寸及横向滚动，不用 CSS 字符串匹配冒充几何验证。
- [ ] 运行 `node --test Tests/web/layout.test.mjs Tests/web/visualizer.test.mjs Tests/web/launcher.test.mjs`，记录预期 RED。
- [ ] GREEN：实现布局服务/面板、有限 CSS token、应用栏收缩与生命周期处理，禁止新轮询。
- [ ] GREEN：`scripts/test-web.sh`、`scripts/test.sh`、`swift build`、`git diff --check`；浏览器检查目标尺寸及较小安全区，子代理只读自查、本地提交。

## 用户手动验证

- [ ] 两图标底板明显收缩；多图标横向可达，长名不撑开；工作优先布局中 launcher 仍在左下。
- [ ] 切换预设及隐藏卡片后原位置可点击 Finder，没有残余毛玻璃；桌面图标区域仍可使用。
- [ ] 隐藏项目输入时键盘交还；全部隐藏后菜单仍可恢复；隐藏时钟不冻结时段与待办日期。
- [ ] 原生毛玻璃、拖入、多屏一致、重启恢复分别检查，记录真实运行包路径。

## 交付记录

- **改动摘要**：尚未实施。
- **自测结果**：尚未执行。
- **疑问 / 偏离**：无。

## 审查记录

- **审查者**：待正式独立审查。
- **结论**：待审查。
- **意见**：子代理结果仅作实现自查。
