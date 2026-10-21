# M7-05: 添加项目时容忍全角的"～""／"

- **状态**：review
- **里程碑**：M7
- **依赖**：无（M7-01 到 M7-03 已合并）。和 M7-04 改的文件不重叠，先后都行
- **分支**：task/M7-05

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

用中文输入法在项目输入框里打路径时，容易打出全角的"～"和"／"。现在这样的路径一律提示"找不到这个文件夹"，容易让人以为文件夹真的不存在。改成：照原样找不到时，把全角符号换成半角再试一次。

## 背景与约束

- **用户发现**（2026-10-21，M7-03 验收）：
  - 中文输入法下打 `/etc` 和 `~/Desktop/…`，打出来的是 `／etc` 和 `～/Desktop/…`，结果显示"找不到这个文件夹"；
  - 切到英文输入法后才正常。
- **Claude Code 用 M7-01 的代码核对过**：
  - `／etc` → `notFound`，`～/Desktop/CS61A-master` → `notFound`；
  - 半角的 `/etc` → `outsideHome`，`~/Desktop/CS61A-master` → 成功。
- 全角斜杠"／"在 macOS 里是合法的文件名字符（虽然很少见），所以**不能一上来就替换**。要先照原样核对，只有原样得到 `notFound` 时才用换过的路径再试一次。
- 用户 2026-10-21 同意做这个修复。

### 1. Swift（`Sources/DesktopShell/ProjectEditing.swift`）

- 新增纯函数 `static func normalizeFullWidth(_ input: String) -> String`：
  - 开头的"～"（U+FF5E）换成"~"；
  - 所有的"／"（U+FF0F）换成"/"；
  - 其余字符不动。
- `resolve` 的流程：
  1. 照原样按现在的规则核对。
  2. 结果是 `notFound`，并且 `normalizeFullWidth(input) != input` 时，用换过的路径再核对一次，返回第二次的结果（成功或其他错误）。
  3. 其他情况返回第一次的结果。
- 存进 `config.json` 的 `path` 仍然是 `storedPath` 算出来的真实路径。

### 2. mock（`web/js/mock.js`）

- `addProject` 的模拟核对按同样的规则：原样不符合"以 `~/` 或 `/Users/<名字>/` 开头"时，先换成半角再判断，这样浏览器里的表现和应用一致。

### 3. 测试

- `Tests/DesktopShellTests/ProjectEditingTests.swift`（修改），用现有的假文件系统：
  - `normalizeFullWidth`：
    - `～/Desktop/a` → `~/Desktop/a`；
    - `／etc` → `/etc`；
    - `～／Desktop／a` → `~/Desktop/a`；
    - 中间的"～"不换（例如 `~/a～b` 原样）；
    - 没有全角符号的输入原样返回。
  - `resolve`：
    - `～/Desktop/a`（a 存在）→ 成功；
    - `／etc`（`/etc` 存在）→ `outsideHome`；
    - 文件夹名本身含"／"、照原样存在时 → 照原样成功，不做替换；
    - 换过以后仍不存在 → `notFound`。
- `Tests/web/mock.test.mjs`（修改）：`～/Desktop/test` 能添加成功，`／etc` 得到 `outside-home`。

## 允许修改的文件

- `Sources/DesktopShell/ProjectEditing.swift`
- `Tests/DesktopShellTests/ProjectEditingTests.swift`
- `web/js/mock.js`
- `Tests/web/mock.test.mjs`
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改其他校验规则（存在 → 是文件夹 → 在 home 里 → 不重复）和错误码。
- 不改网页组件和文案。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build` 无错误、无警告
- [ ] `scripts/test.sh`、`scripts/test-web.sh` 全部通过
- [ ] `scripts/bundle.sh` 成功
- [ ] `git diff --name-only main...task/M7-05` 只有上面"允许修改的文件"

**用户手动验证**（用主仓库的 `build/DesktopShell.app`）：

- [ ] 开着中文输入法，在项目输入框里打 `／etc` 回车 → "只能添加个人文件夹（~）里的文件夹"
- [ ] 开着中文输入法打 `～/Desktop/<一个还没加的文件夹>` 回车 → 加成项目；`config.json` 里的 `path` 是半角的 `~/Desktop/…`
- [ ] 之后在列表里把它移除（或者保留，由用户决定）

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
  - 从最新 `main` / `origin/main`（`b73e8bf`）建立 `task/M7-05`，仅修改本任务允许的 5 个文件。
  - 新增纯函数 `normalizeFullWidth`：仅替换开头 U+FF5E 和全部 U+FF0F，其余字符保持不变。
  - 原有路径核对移入 `resolveOriginal`，校验内容和顺序保持原样；`resolve` 只在首次为 `notFound` 且转换后确有变化时重试一次，直接返回第二次结果。已有全角文件名优先；持久化仍来自真实解析路径。
  - mock 仅在原路径前缀不符合现有规则时转换，再沿用现有错误检查和项目推送流程；未改组件或文案。
- **自测结果**：
  - RED：先添加行为测试，Swift 捕获 9 个预期问题（全角成功路径返回 `notFound`，错误未转换为 `outsideHome` / `notDirectory` / `duplicate`）；mock 74 项中 6 项因缺少转换失败。Swift 首次测试编译遇到新增类型别名访问级别错误，修正测试声明后才取得上述行为 RED，未将编译错误视为修复证据。
  - GREEN：`scripts/test.sh` 263/263 PASS（28 suites）；`scripts/test-web.sh` 482/482 PASS，0 FAIL / 0 SKIP。
  - 新增覆盖：纯函数字符规则、全角路径解析、重试后的各错误、原样存在的全角文件名、非 `notFound` 不重试、未变化路径不重复检查、NUL 和符号链接边界；临时目录集成测试确认写入 `config.json` 的路径为 `~/Desktop/a`，再以半角添加得到重复错误。未触碰用户真实项目配置。
  - `swift build` PASS，无编译错误或警告；`scripts/bundle.sh` release PASS，plist、固定证书签名与 designated requirement 检查通过。产物：`/Users/arvinhan/Desktop/desktop-shell/build/DesktopShell.app`。
  - `git diff --check`、5 文件范围检查及任务需求部分逐字一致检查 PASS。
  - 子代理只读自查未发现需修正问题，并复验 mock 74/74 PASS；仅算交付前自查，不是正式审查。
  - 日志：`/private/tmp/m7-05-red-swift.log`、`/private/tmp/m7-05-red-web.log`、`/private/tmp/m7-05-green-swift.log`、`/private/tmp/m7-05-green-web.log`、`/private/tmp/m7-05-build.log`、`/private/tmp/m7-05-bundle.log`。
  - 桌面手动验收尚未执行：请退出旧应用并打开上述主仓库应用；输入 `／etc`，确认提示“只能添加个人文件夹（~）里的文件夹”；输入 `～/Desktop/<尚未添加的真实文件夹>`，确认添加成功且配置路径为半角 `~/Desktop/…`；之后按用户意愿移除或保留项目。本次未启动应用或更改登录项。
- **疑问 / 偏离**：
  - 无需求或文件范围偏离。状态为 `review`，只交付任务分支，不合并或推送 `main`；正式审查需由未参与本次实现的其他会话完成。
  - 提交并推送任务分支的命令被权限审核拦截，理由为尚缺此次远端源代码推送的明确授权；该命令未执行，代码和交付记录目前是本地未提交修改。待用户明确同意提交并推送 `origin/task/M7-05` 后继续；不影响上述已完成的本地验证。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：Codex（2026-10-21，独立审查会话）：代码审阅、自动复验及用户桌面验收通过，未发现需退回的缺陷。
- **意见**：
  - 审查对象是 `task/M7-05` 上的 5 个未提交修改文件；分支 HEAD 和本地 `main` 均为 `b73e8bf`，因此 `git diff main...task/M7-05` 当前为空，不将空差异当作交付验证。已检查 `git diff HEAD` 的实际修改，范围符合任务要求，需求部分保持不变。
  - 5/5 文件已审阅，跳过 0，覆盖率 100%。核对了仅 `notFound` 且转换有变化时重试、原样存在的全角文件名优先、原校验顺序与错误码、真实路径持久化，以及 Bridge、AppState、输入框和拖入调用链；mock 符合本任务规定的前缀模拟规则。未修改业务代码或测试。
  - 用 `git archive HEAD` 加工作区补丁建立独立临时检出 `/private/tmp/m7-05-review.q6R40y`，5 个文件逐一 `cmp` 与原工作区一致。该目录执行 `swift build` PASS（无编译警告）、`scripts/test.sh` 263/263 PASS（28 suites）、`scripts/test-web.sh` 482/482 PASS（0 FAIL / 0 SKIP）、`scripts/bundle.sh` release PASS（固定证书签名及校验通过），四项退出码均为 0；`git diff --check` PASS。
  - 首次沙盒构建因禁止写入 `~/.cache/clang/ModuleCache` 失败；经权限审批后在同一临时检出重新完成以上四项，未调整源码或降低检查。复验日志在该目录的 `review-build-verified.log`、`review-swift-verified.log`、`review-web-verified.log`、`review-bundle-verified.log`。
  - 用户回复桌面验收“通过”。额外只读核对确认真实配置中 `ui` 项目的路径为 `~/Desktop/UI练习`，对应文件夹存在，应用日志也有该路径的成功添加记录。但当前主仓库应用进程启动于新包生成之前，近期应用日志未见 `outside-home`，尚不足以确认本次全角输入修复已在新进程验收；已请用户退出旧应用并重开主仓库 `build/DesktopShell.app` 后确认两项全角输入。临时审查包未启动，登录项未操作，真实配置未由审查者改写。
  - 补充验收：用户随后明确确认“已重启且两项全角输入均通过”。只读检查确认主仓库应用为新进程 PID 20921，启动晚于新包生成；该进程成功添加 `desktop-shell`，日志及真实配置均为 `~/Desktop/desktop-shell`，对应目录存在。全角输入及界面错误提示以用户实测为据；近期持久化日志未包含 `outside-home`，未将该日志项记作已观察到。审查者未操作真实项目配置。
  - 合并前检查：获取远端后 `main`、`origin/main` 与任务分支基线均为 `b73e8bf`；4 个代码/测试文件与自动复验快照逐一一致。按项目流程保存任务提交，再进行非快进合并及复验。
