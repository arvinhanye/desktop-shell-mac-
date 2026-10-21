# M7-05: 添加项目时容忍全角的"～""／"

- **状态**：todo
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
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
