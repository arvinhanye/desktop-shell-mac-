# M2-02: 路径、配置读写、shell:// 路径安全（纯逻辑 + 单元测试）

- **状态**：todo
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
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
