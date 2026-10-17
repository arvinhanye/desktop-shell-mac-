# M2-02: 路径、配置读写、shell:// 路径安全（纯逻辑 + 单元测试）

- **状态**：review
- **里程碑**：M2
- **依赖**：无（可以和 M2-01 任意顺序，但 Codex 一次只做一个）
- **分支**：task/M2-02

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

先把 M2-03 要用到的三块逻辑写好，并用单元测试锁住行为：应用目录在哪里、`config.json` 怎么读写、`shell://` 请求怎么安全地映射到本地文件。本任务**不接入界面**，运行应用看不到任何变化。

## 背景与约束

- 先读 `AGENTS.md` 的"Bridge 接口"（安全要求）、"配置文件示例"、"运行时素材目录"、"开发环境"（单元测试部分）。
- 所有逻辑写成可以注入参数的纯函数或结构体，测试里用临时目录，**测试不能读写用户真实的 `~/Library/Application Support/DesktopShell`**。

### 1. `AppPaths.swift`

```swift
struct AppPaths: Equatable {
    let supportDir: URL   // ~/Library/Application Support/DesktopShell
    let mediaDir: URL     // supportDir/media
    let webDir: URL       // 网页文件目录

    static func resolve(environment: [String: String],
                        bundleResourceURL: URL?,
                        currentDirectory: URL,
                        home: URL,
                        fileExists: (URL) -> Bool) -> AppPaths
}
```

规则：

- `supportDir`：环境变量 `DESKTOPSHELL_SUPPORT_DIR` 有值就用它，否则是 `home/Library/Application Support/DesktopShell`。
- `mediaDir`：`supportDir/media`。
- `webDir` 按顺序取第一个可用的：环境变量 `DESKTOPSHELL_WEB_DIR` → `bundleResourceURL/web`（存在时；M2.5 打包后走这条）→ `currentDirectory/web`（开发时在仓库根目录运行走这条）。
- 再提供一个 `static var current: AppPaths`，用真实的 `ProcessInfo`、`Bundle.main`、`FileManager` 调用 `resolve`。

### 2. `Config.swift`（数据模型）和 `ConfigStore.swift`（读写）

- 数据模型和 `AGENTS.md`"配置文件示例"一一对应，全部 `Codable`：`AppConfig { background, character, greetings, projects, apps }`。`Project` 增加可选字段 `apps: [String]?`（联动规则里"项目相关的应用"）；`tags`、`apps` 都是可选。
- `AppConfig.example`：内容与 `AGENTS.md` 的示例一致，只把项目路径改成 `~/Desktop/desktop-shell`，并给这个项目加上 `"apps": ["cursor"]`。
- `ConfigStore`：

  ```swift
  struct ConfigStore {
      let supportDir: URL
      func load() throws -> AppConfig
  }
  ```

  - `config.json` 不存在：先创建 `supportDir`（含中间目录），再把 `AppConfig.example` 写成格式化的 JSON（`prettyPrinted` + `sortedKeys` + `withoutEscapingSlashes`，中文不能被转义成 `\uXXXX`），然后返回它。
  - 存在但解析失败：**抛出错误，不能覆盖用户的文件**。调用方（M2-03）会记录日志并在内存里使用 `example`。
  - 解析成功后做校验：`projects` 和 `apps` 里 `id` 不符合 `^[A-Za-z0-9_-]+$` 的条目丢弃，并用 `NSLog` 记录；`greetings` 按 `from` 升序排序，`from` 不在 0–23 范围的丢弃。
- 把 id 校验写成一个独立的函数 `isValidID(_:) -> Bool`，后续 bridge 也要用它。

### 3. `SchemeResolver.swift`（`shell://` 的安全核心）

URL 约定（同一个源，避免 ES module 跨域问题）：

| URL | 映射到 |
|---|---|
| `shell://app/` | `webDir/index.html` |
| `shell://app/<path>` | `webDir/<path>` |
| `shell://app/media/<path>` | `mediaDir/<path>` |

```swift
struct SchemeResolver {
    let webRoot: URL
    let mediaRoot: URL
    /// path 是 URL.path（已经解码过百分号编码）。不允许访问时返回 nil。
    func fileURL(forPath path: String) -> URL?
    static func mimeType(forPathExtension ext: String) -> String
    static func parseRange(_ header: String?, fileSize: Int) -> RangeResult
}
enum RangeResult: Equatable { case full, partial(ClosedRange<Int>), unsatisfiable }
```

`fileURL(forPath:)` 必须**同时**满足以下条件才返回 URL，否则返回 nil：

1. `path` 以 `/` 开头，不包含 `\0`。
2. 去掉开头的 `/`（或 `/media/`）后按 `/` 切分，任何一段都不能是空串、`.`、`..`，也不能以 `.` 开头（不提供隐藏文件）。
3. 把候选路径和根目录都做 `resolvingSymlinksInPath()` + `standardizedFileURL`，候选路径必须以"根目录路径 + `/`"开头。这样能挡住符号链接逃逸，也能挡住 `/x/web` 与 `/x/web2` 这种前缀误判。注意 `/tmp` 本身是指向 `/private/tmp` 的符号链接，两边都解析后再比较。
4. 目标存在，并且是普通文件（不是目录）。

`mimeType`：`html`→`text/html`，`js`/`mjs`→`text/javascript`（ES module 必须是 JS 类型），`css`→`text/css`，`json`→`application/json`，`png`→`image/png`，`jpg`/`jpeg`→`image/jpeg`，`svg`→`image/svg+xml`，`webp`→`image/webp`，`mp3`→`audio/mpeg`，`mp4`→`video/mp4`，`woff2`→`font/woff2`，`woff`→`font/woff`，`ttf`→`font/ttf`，`otf`→`font/otf`，`txt`→`text/plain`，其他一律 `application/octet-stream`。扩展名不区分大小写。

`parseRange`（`<audio>` 播放 mp3 时 WebKit 会发 Range 请求，M2-03 要用）：

- `nil` 或空串 → `.full`
- `bytes=a-b` → `.partial(a...min(b, size-1))`；`bytes=a-` → `.partial(a...size-1)`；`bytes=-n` → 最后 n 个字节
- `a >= size`、`a > b`、格式不对 → `.unsatisfiable`
- 多段（含逗号）→ `.full`（不支持多段，直接返回整个文件）
- `fileSize == 0` 时任何 Range 都是 `.unsatisfiable`

### 4. 测试（swift-testing，用 `scripts/test.sh` 运行）

每个测试自己建临时目录（`FileManager.default.temporaryDirectory` 下的 UUID 子目录），结束后删除。至少覆盖：

- **AppPathsTests**：三种 `webDir` 来源的优先级；`DESKTOPSHELL_SUPPORT_DIR` 覆盖；`mediaDir` 总是 `supportDir/media`。
- **ConfigStoreTests**：文件不存在时生成文件并返回 example，且生成的 JSON 里能直接看到中文"爱弥斯"；已有合法文件时原样读取；损坏的 JSON 会抛错，**并且文件内容保持不变**；非法 id（如 `"../x"`、`"a b"`、`""`）被丢弃；`greetings` 乱序时排好序，`from: 24` 被丢弃。
- **SchemeResolverTests**：
  - `/`→`index.html`；`/js/a.js`、`/media/voice/1.mp3` 正常映射
  - 拒绝：`/../secret`、`/media/../config.json`、`/a/./b`、`/a//b`、`/.hidden`、`/media/.DS_Store`、含 `\0`、不以 `/` 开头、目录、不存在的文件
  - 前缀误判：根目录是 `.../web`，同级还有 `.../web2/x.html`，`fileURL` 不能返回它
  - 符号链接逃逸：在 `webRoot` 里建一个指向根目录外文件的符号链接，访问它返回 nil；指向根目录内文件的符号链接可以访问
  - `mimeType`：表里每一项，加上大写扩展名和未知扩展名
  - `parseRange`：上面列出的每种情况

## 允许修改的文件

- `Sources/DesktopShell/AppPaths.swift`（新建）
- `Sources/DesktopShell/Config.swift`（新建）
- `Sources/DesktopShell/ConfigStore.swift`（新建）
- `Sources/DesktopShell/SchemeResolver.swift`（新建）
- `Tests/DesktopShellTests/AppPathsTests.swift`（新建）
- `Tests/DesktopShellTests/ConfigStoreTests.swift`（新建）
- `Tests/DesktopShellTests/SchemeResolverTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不修改 `AppDelegate`、`ScreenManager`、`DesktopWindow`，不接入界面（M2-03 再接）。
- 测试不碰真实的用户目录。
- 不引入第三方依赖。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh` 退出码 0，原有 9 个安全区域测试和本任务新增的测试全部通过；交付记录里列出新增测试的数量
- [ ] 把 `SchemeResolver` 第 3 条（前缀和符号链接检查）临时注释掉，`scripts/test.sh` 必须失败（验证测试真的能抓住漏洞）；验证后恢复，不要提交注释掉的版本
- [ ] `git diff --name-only main...task/M2-02` 只包含"允许修改的文件"
- [ ] 运行测试前后，`ls ~/Library/Application\ Support/DesktopShell 2>&1` 的结果不变（测试没有碰真实目录）

**用户手动验证**：本任务没有界面变化，无需手动验证。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
  - 新增可注入的 `AppPaths.resolve` 和运行时 `current`，按约定选择支持目录、素材目录及网页目录。
  - 新增 Codable 配置模型、完整示例、独立的 ASCII id 校验，以及首次创建、已有配置读取和内存过滤排序逻辑；读取或解析失败直接抛错，保留已有文件。
  - 新增 `SchemeResolver`：检查路径段、解析根目录与候选文件的符号链接、校验带分隔符的根目录边界及普通文件属性；实现完整 MIME 表和单段 Range 解析。
  - 仅改动允许的 7 个 Swift 文件和本任务单的状态、交付记录；没有界面接入或依赖变更。
- **自测结果**（2026-10-17）：
  - 测试先行：未实现接口时编译失败；临时空实现可编译但产生 95 条断言问题，原有 9 个安全区域测试仍通过；完成实现后全套通过。
  - 新增 **25 个测试**：AppPaths 7 个、ConfigStore 8 个、SchemeResolver 10 个；加上原有 9 个，`scripts/test.sh` 最终退出码 0，**34/34 通过**。参数化测试另覆盖损坏配置、15 种 id、14 种非法路径、21 项 MIME、37 项 Range 输入。
  - 变异验证：临时移除根目录边界 `guard` 后，`scripts/test.sh` 因 **2 个测试中的 5 条断言失败**而非零退出，实际捕获 `web2` 前缀误判及 web/media 的文件、目录符号链接逃逸。随后逐字节恢复源码，重新运行全套测试，34/34 通过；提交版本保留完整检查。
  - 恢复后 `swift build` 退出码 0；构建日志经 `grep -iE 'warning|error'` 检查，无匹配输出。
  - 所有文件系统测试均使用临时目录下的独立 UUID 子目录并清理，测试后没有 `DesktopShellTests-*` 残留。真实支持目录仅作测试前后只读 `ls` 对照，两次均只列出 `media`，输出和退出码一致；未运行应用或在真实目录生成配置。
  - `git diff --check` 通过；变更范围为上述 8 个允许文件，任务需求及审查记录保持原样。独立只读代码检查未发现需要修复的 P0/P1/P2 问题；正式审查仍待 Claude Code 完成。
  - 构建、测试、变异及支持目录对照日志位于 `/tmp/ds-m2-02-validation/`。本任务没有界面变化，无需用户手动验证。
- **疑问 / 偏离**：无。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
