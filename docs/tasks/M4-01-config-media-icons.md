# M4-01: 配置新字段、语音列表、应用图标和素材升级

- **状态**：todo
- **里程碑**：M4
- **依赖**：M3 完成；M3.5 设计定稿已合并到 `main`
- **分支**：task/M4-01

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

`getConfig` 带上 M3.5 定稿要用的新数据：问候语的称呼 `user.name`、角色卡的签名 `character.motto`、启动栏的应用图标地址 `apps[].iconUrl`、点击语音用的语音列表 `media.voices`。应用启动时 Swift 把应用图标导出到 `media/app-icons/`。`prepare-media.sh` 改成 4K 视频、2 倍头像、新尺寸的心形装饰条，并复制字体。做完之后，后面组件任务要用的数据和素材都齐了；桌面上暂时看不出变化（组件从 M4-03 开始做），除了视频变清楚。

## 背景与约束

- 先读 `AGENTS.md`：Bridge 表里的 `getConfig`；"配置文件示例"和它下面关于 `user.name`、`character.motto` 的说明；"运行时素材目录"表里 `video/`、`avatars/`、`ornaments/`、`fonts/`、`app-icons/` 几行；技术选型表的"背景"一行。
- `docs/design/fonts.css` 列出要用的 5 个字体文件；`docs/design/tokens.css` 的 `--viz-ornament-width` 是心形的显示宽度 640（素材做 2 倍）。
- **上一次的尝试**：Codex 之前在本地做过一版（commit `eb5334e`，没有合并），Claude Code 已把那个分支改名为 `attempt/M4-01-codex1` 保留。这次从最新的 `main` 新建 `task/M4-01` 重做。可以参考旧代码，但以本任务单为准；旧版里本任务单没有要求的东西（`.prepare-media-recipe` 标记文件、`Tests/media/` 目录、`docs/handoff/`）不要带过来。
- 自测不碰用户的真实数据：不改 `~/Library/Application Support/DesktopShell/` 里的 `config.json`、`ui.json`；素材脚本用临时的 `MEDIA_DIR` 验证，正式目录由用户自己跑。

### 1. 配置（`Config.swift`）

- `AppConfig` 加可选的 `user: User?`（`struct User: Codable, Equatable { var name: String? }`）；`Character` 加可选的 `motto: String?`。
- 旧配置文件（没有这两个字段）照常读取，不写回、不补字段。
- `AppConfig.example` 按 AGENTS.md 的配置示例加上 `user.name = "Arvin"` 和 `character.motto = "愿星光一直落在你走的路上"`。

### 2. 语音列表（`MediaLibrary.swift`）

- `scan` 增加一个参数指定接受哪些扩展名，默认值仍是现在的图片扩展名；其他规则不变（跳过隐藏文件、符号链接、非法 id，重复 id 只留第一个，按 id 自然排序）。
- 语音：扫描 `voice/`，只接受 `mp3`，`url` 为 `/media/voice/<文件名>`。

### 3. 应用图标（新建 `AppIcons.swift`）

- **什么时候导出**：应用启动时，在 `AppDelegate` 里**创建窗口之前**开始；菜单栏"重新加载"重新读取配置之后再导出一次。导出在后台线程进行，不阻塞主线程。
- **怎么导出**：对 `config.apps` 的每个应用，用 `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` 找到应用，`NSWorkspace.shared.icon(forFile:)` 取图标，画成 128 × 128 像素的 PNG，写到 `media/app-icons/<appId>.png`。
- **写文件**：先写到同一目录下的临时文件，再改名替换，失败不留下半个文件。只覆盖本次导出的同名文件，不删除目录里的其他文件。`app-icons/` 不存在就新建；它是符号链接或者被普通文件占着时整次不导出，记录一行日志。
- **结果**：每次导出得到一张"导出成功的应用 id"表，`getConfig` 用它决定 `iconUrl`。应用找不到或导出失败 → 不在表里，记录一行日志（只写 app id 和原因，例如 `DesktopShell icons: app=figma not-installed`）。全部做完记录一行 `DesktopShell icons: exported=<成功数>/<总数>`。
- 把"按 bundle id 找应用并取图标"做成可以替换的函数（例如初始化参数），方便测试时不依赖本机装了什么。

### 4. `getConfig` 的回复（`BridgeProtocol.swift` 的 `ConfigReply`、`Bridge.swift`、`AppState.swift`）

```json
{
  "config": {
    "user": { "name": "Arvin" },
    "character": { "name": "爱弥斯", "motto": "愿星光一直落在你走的路上" },
    "greetings": ["……不变……"],
    "projects": ["……不变……"],
    "apps": [
      { "id": "cursor", "name": "Cursor", "iconUrl": "/media/app-icons/cursor.png" },
      { "id": "figma", "name": "Figma", "iconUrl": null }
    ]
  },
  "media": {
    "avatars": ["……不变……"],
    "backgrounds": ["……不变……"],
    "voices": [{ "id": "1", "url": "/media/voice/1.mp3" }]
  },
  "uiState": { "……": "不变" }
}
```

- `user` 对象总是有；`user.name`、`character.motto` 在配置里没有、或者去掉首尾空白后为空时是 `null`（键保留，值写 `NSNull()`）；有值时输出去掉首尾空白后的字符串。
- `iconUrl`：这个应用在**最近一次**导出里成功 → `/media/app-icons/<appId>.png`；否则 `null`。
- 收到 `getConfig` 时导出还没做完：等它做完再回复。等待是异步的（回复处理器先存起来，导出完成后在主线程回复），不能阻塞主线程。正常情况下页面加载比导出慢，用不着等。
- 回复里仍然**没有**项目路径、bundle id、提醒事项列表名、背景视频。
- 日志行改为 `DesktopShell bridge: getConfig avatars=<数量> backgrounds=<数量> voices=<数量> icons=<有 iconUrl 的数量>`。

### 5. 网页这边跟上（`web/js/bridge.js`、`web/js/mock.js`、`web/js/store.js`）

- `bridge.js` 的 `normalizeReply`：
  - `media.voices` 和头像、背景一样过滤成 `{id, url}`；回复里没有或不是数组 → `[]`（不要因此丢掉头像和背景）。
  - `config.user` 规范成 `{ name: 字符串或 null }`，缺失也给出这个形状。
  - `config.character.motto` 规范成字符串或 `null`。
  - 每个应用的 `iconUrl` 规范成字符串或 `null`。
- `store.js`：`initialState.media` 加 `voices: []`。
- `mock.js` 的 `getConfig` 回复和 Swift 同一个形状：`user.name`、`character.motto` 用 AGENTS.md 示例里的值；现有 3 个应用加上 `iconUrl: '/media/app-icons/<id>.png'`，再加一个没装的应用 `{ id: 'figma', name: 'Figma', iconUrl: null }`；`media.voices` 是 `/media/voice/1.mp3` 到 `54.mp3`（id `'1'` 到 `'54'`）。其余 mock 数据在 M4-02 换成效果图的数据，这里不动。

### 6. 素材脚本（`scripts/prepare-media.sh`）

- **视频**：去掉缩放，保持原片的 3840 × 2160；`-preset` 从 `slow` 改成 `medium`（M3.5 探针就是这样转的，4K 用 `slow` 太慢），其余参数不变。汇总里照常打印视频信息。在交付记录里写下实际转码用了多久。
- **头像**：改从 `assets/avatars-2x/<n>.png`（480 × 300）原样复制，不再用 `assets/avatars/`。开头的素材目录检查相应改成检查 `avatars-2x`。
- **心形装饰条**：裁切不变，缩放目标从 2400 改成 1280，结果是 1280 × 213。
- **字体**：新增输出目录 `fonts/`，从 `assets/fonts/` 原样复制 `docs/design/fonts.css` 用到的 5 个文件：`SourceHanSerifSC-SemiBold.otf`、`Gobold-Bold.otf`、`Porter.otf`、`GoogleSans-Regular.ttf`、`GoogleSans-Bold.ttf`。`Emilea.otf` 没用到，不复制。开头的素材目录检查加上 `assets/fonts`；结尾的汇总加一行 `fonts`。
- `app-icons/` 不归脚本管：脚本不创建、不删除、不检查它。
- 增量规则不变（输出比源文件新就跳过）。所以已有的旧产物（2560 × 1440 的视频、2400 × 400 的心形）不会自动重做，用户升级时跑一次 `--force`。在交付记录里写明这一点，不要另加"配方标记"之类的机制。

### 7. 测试

- `ConfigStoreTests.swift`：没有 `user`、`motto` 的旧配置能读；带这两个字段的能读；`example` 编码再解码不变。
- `MediaLibraryTests.swift`：`voice/` 只收 `mp3`（`.txt`、`.wav`、隐藏文件、符号链接、非法 id 都跳过）；自然排序（`2.mp3` 在 `10.mp3` 前面）；图片扫描的行为不变。
- `AppIconsTests.swift`（新建，替换掉"找应用 + 取图标"的函数）：成功时写出 128 × 128 的 PNG；找不到的应用不在成功表里；`app-icons` 是符号链接时什么都不写、成功表为空；目录里原有的其他文件保留；同名旧文件被覆盖。
- `BridgeTests.swift`（`ConfigReply.make`）：新字段的形状；`user.name`、`motto` 缺失或只有空白时是 `NSNull`；`iconUrl` 按成功表给出地址或 `NSNull`；仍然没有 `path`、`bundleId`、`remindersList`、`background`。
- `Tests/web/bridge.test.mjs`：`normalizeReply` 对新字段的规范化（缺失、类型不对、`voices` 不是数组时头像和背景还在）。`Tests/web/mock.test.mjs`：mock 的回复带新字段。

## 允许修改的文件

- `Sources/DesktopShell/Config.swift`、`MediaLibrary.swift`、`BridgeProtocol.swift`、`Bridge.swift`、`AppState.swift`、`AppDelegate.swift`（修改）
- `Sources/DesktopShell/AppIcons.swift`（新建）
- `scripts/prepare-media.sh`（修改）
- `web/js/bridge.js`、`web/js/mock.js`、`web/js/store.js`（修改）
- `Tests/DesktopShellTests/ConfigStoreTests.swift`、`MediaLibraryTests.swift`、`BridgeTests.swift`（修改），`AppIconsTests.swift`（新建）
- `Tests/web/bridge.test.mjs`、`Tests/web/mock.test.mjs`（修改）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改用户的 `config.json`、`ui.json`，不把新字段写回配置文件。
- 不改 `web/widgets/`、`web/styles/`、`web/index.html`（M4-02 起才动）。
- 不改 `AGENTS.md`、`docs/design/`、本任务单的需求部分；不新建任务单以外的文档（例如 `docs/handoff/`）。
- 素材脚本不引入 ffmpeg、ffprobe、sips 以外的工具。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `swift build 2>&1 | grep -iE "warning|error"` 没有输出
- [ ] `scripts/test.sh`、`scripts/test-web.sh` 全部通过，包含上面列出的新测试
- [ ] `git diff --name-only main...task/M4-01` 只包含"允许修改的文件"
- [ ] `bash -n scripts/prepare-media.sh` 通过
- [ ] `MEDIA_DIR=<临时目录> scripts/prepare-media.sh` 退出码 0，然后：
  - `ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,codec_tag_string,width,height,r_frame_rate -of default=nw=1 <临时目录>/video/aemeath.mp4` → `hevc`、`hvc1`、`3840`、`2160`、`30/1`
  - `ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 <临时目录>/video/aemeath.mp4` 没有输出（没有音轨）
  - `sips -g pixelWidth -g pixelHeight <临时目录>/ornaments/heart.png` → 1280 × 213
  - `for n in {1..30}; do cmp assets/avatars-2x/$n.png <临时目录>/avatars/$n.png; done` 没有输出
  - `ls <临时目录>/fonts` 正好是上面列的 5 个文件，每个都和 `assets/fonts/` 里的同名文件 `cmp` 一致
  - 语音 54 个、背景图 63 张加 `CREDITS.txt`，和以前一样
- [ ] 同一个临时目录再跑一次：每一类都是"生成 0"
- [ ] （Claude Code 复验）`scripts/bundle.sh --open` 启动后，日志里依次有 `DesktopShell icons: exported=<n>/<总数>` 和 `DesktopShell bridge: getConfig avatars=30 backgrounds=63 voices=54 icons=<n>`，`n` 等于 `config.apps` 里本机装了的应用数；从启动到出现 `icons: exported` 不超过 3 秒；`media/app-icons/` 里这些应用的 PNG 都是 128 × 128

**用户手动验证**：

- [ ] 在 `config.json` 里加上 `"user": { "name": "Arvin" }`，并给 `character` 加上 `"motto"`，点菜单栏"重新加载" → 没有报错（Claude Code 查日志里没有 `configuration reload failed`）。名字和签名的显示要等 M4-03、M4-07。
- [ ] 运行 `scripts/prepare-media.sh --force`（4K 转码要等一阵），然后退出、重新打开 DesktopShell → 桌面视频明显比以前清晰，循环处不卡顿，颜色和以前一致。
- [ ] 在 `config.json` 的 `apps` 里临时加一个没装的应用（例如 `{ "id": "figma", "name": "Figma", "bundleId": "com.figma.Desktop" }`），点"重新加载" → Claude Code 查日志：`icons:` 记录了 `figma` 找不到，成功数没有算它。验证完删掉这一项。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
