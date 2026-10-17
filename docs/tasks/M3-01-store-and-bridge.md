# M3-01: 共享状态 store.js 与通信层 bridge.js（含 mock）

- **状态**：todo
- **里程碑**：M3
- **依赖**：无
- **分支**：task/M3-01

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

网页有了**唯一的共享状态**（`store.js`）和**唯一的 Swift 通信入口**（`bridge.js`）。在普通浏览器里（没有 `window.webkit.messageHandlers`）自动切换到 mock：能拿到模拟配置，定时收到模拟的 `systemStats` 和 `audioSpectrum`。这些逻辑全部用 Node 自带的测试运行器做单元测试。

本任务只写纯逻辑模块，页面（`index.html`、CSS、组件注册）在 M3-02 做。

## 背景与约束

- 先读 `AGENTS.md`：核心架构、"Bridge 接口（白名单）"（含"通信方式"）、联动规则、开发方式。
- **模块导入时不能访问 DOM**：三个模块里不出现 `document`、`localStorage`；`window` 只能通过参数注入（`target`），这样才能在 Node 里测试。
- 无构建步骤，不引入任何 npm 包，不建 `package.json`。测试只用 Node 自带的 `node:test`、`node:assert`（本机 Node v26）。
- 网页 → Swift 的协议（M3-03 起 Swift 端实现，mock 必须照同样的规则回复）：
  - `window.webkit.messageHandlers.shell.postMessage({action, ...参数})` 返回 Promise。成功时 resolve 为回复值（大多数动作是 `null`），失败时 reject，错误对象的 `message` 是下面的错误码之一：

    | 错误码 | 含义 |
    |---|---|
    | `untrusted` | 消息来源不是 `shell://app` 主框架 |
    | `invalid` | 消息格式不对（缺参数、类型错、多了不认识的参数） |
    | `unknown-action` | 不在白名单里，或者 Swift 还没实现 |
    | `not-found` | id 在配置或素材里查不到 |
    | `failed` | 系统调用失败（例如打开应用失败、写文件失败） |

  - **注意**：M3-03 合并之前，Swift 端还是不带回复的旧处理器，`postMessage` 会直接返回 `undefined`。bridge 必须能正常处理这种情况（见下文 `start()`）。
- Swift → 网页的事件（M3-05、M3-06、M3-07 实现）：Swift 调用 `window.shell.receive(event)`，`event` 是普通对象，`event.event` 是事件名，其余字段平铺。格式见下文 `applyEvent` 的表格。

### 1. `web/js/store.js`

```js
export function createStore(initialState)   // 返回一个 store
// store.get(key)                            → 当前值
// store.getState()                          → 整个状态的浅拷贝（给调试面板用）
// store.set(patch)                          → 浅合并顶层键
// store.subscribe(key, listener, { immediate = false } = {})  → 返回取消订阅函数
//    listener(value, previous)
export const initialState
export const store = createStore(initialState)   // 全页面唯一的实例
```

规则：

- 只接受 `initialState` 里有的键。`set` 里出现未知键：这个键忽略，`console.warn`，其他键照常生效；`patch` 不是普通对象：整条忽略并 `console.warn`。`subscribe` 未知键：`console.warn`，返回一个什么都不做的取消函数。
- 用 `Object.is` 比较新旧值，没变的键不通知。
- 先把 `patch` 里所有键写进状态，再按 `patch` 的键顺序逐个通知；同一个键的监听器按订阅顺序调用。监听器被调用时，`store.get` 已经能读到这次 `set` 的全部新值。
- 监听器抛错：`console.error`，不影响其他监听器，`set` 本身不抛错。
- 监听器里可以再调用 `set`：嵌套的 `set` 立即生效并同步通知。
- 通知过程中有人取消订阅或新增订阅：本轮通知用开始通知时的监听器快照。
- 写入的对象和数组做**浅冻结**（`Object.freeze`）。约定：更新时总是给新对象或新数组，不改旧值。
- `immediate: true`：订阅时立刻用 `(当前值, undefined)` 调用一次。

`initialState`（M4 之前不增减键；需要新键时在交付记录里提出）：

| 键 | 初始值 | 写入方 | 说明 |
|---|---|---|---|
| `ready` | `false` | bridge | `getConfig` 结束（成功或失败）后为 `true` |
| `config` | `null` | bridge | `{character, greetings, projects, apps}`，格式见 M3-03 |
| `media` | `{avatars: [], backgrounds: []}` | bridge | 每项 `{id, url}` |
| `ui` | `{avatarId: null, backgroundId: null, voiceEnabled: true}` | bridge、外观面板（M4） | |
| `todos` | `[]` | bridge | 系统提醒事项（M3-07 起由 Swift 推送）。每项 `{id, text, done, projectId, due}`，格式见 `applyEvent` 的 `todos` 事件 |
| `todosAccess` | `'unknown'` | bridge | 提醒事项权限：`'unknown'`（还没收到）或 `todos` 事件里的 `access` |
| `safeArea` | `{top: 0, right: 0, bottom: 0, left: 0}` | bridge | CSS 像素 |
| `paused` | `false` | bridge | |
| `systemStats` | `null` | bridge | 格式见 `applyEvent` |
| `audioSpectrum` | `null` | bridge | `{bands, at}`：`bands` 是 12 个 0–1 的数，`at` 是收到时的 `now()` |
| `phase` | `'day'` | 时钟（M4） | `'morning'` / `'day'` / `'evening'` / `'night'` |
| `selectedProject` | `null` | 项目卡片（M4） | 项目 id |

### 2. `web/js/bridge.js`

```js
export function createBridge(store, { target = globalThis, native, mock, now = () => Date.now() } = {})
// native 默认取 target.webkit?.messageHandlers?.shell
// 返回 { mode, send(action, params), start(), mock }
export function applyEvent(store, event, now)   // Swift 事件 → store，纯函数，供测试
```

- **模式**：`native` 存在且有 `postMessage` 函数时 `mode = 'native'`，否则 `mode = 'mock'`（`mock` 参数不传时用 `createMock()` 新建一个）。`bridge.mock` 在 mock 模式下是那个 mock 对象，native 模式下是 `null`。
- **接收**：`createBridge` 同步地设置 `target.shell = { receive(event) }`（已有就覆盖）。两种模式都走这一个入口：mock 推送事件也调用它。`receive` 内部调用 `applyEvent(store, event, now)`，**任何输入都不能让 `receive` 抛错**。
- **`send(action, params = {})`**：消息为 `{...params, action}`（`action` 放最后，参数不能覆盖它），返回 Promise。
  - native：`new Promise(resolve => resolve(native.postMessage(message)))`，这样 `postMessage` 同步抛错也会变成 rejection。
  - mock：`mock.handle(message)`。
  - 失败时统一 reject 一个 `Error`，带 `code` 属性：取原错误的 `message`（是字符串时），否则 `String(原错误)`。同时 `console.warn(\`bridge: ${action} 失败：${code}\`)`。
- **`start()`**：只能真正执行一次，重复调用返回同一个 Promise。
  1. mock 模式下先调用 `mock.start(receive)`，开始推送模拟事件。
  2. `send('getConfig')`。回复合法时一次性 `store.set({config, media, ui, ready: true})`；回复不合法、`undefined`（M3-03 之前的 Swift）或者 reject：`console.error` 一条说明，然后 `store.set({ready: true})`，`config` 保持 `null`。
  3. Promise 在 `ready` 写入之后 resolve，**永远不 reject**。
- **`getConfig` 回复的校验和规整**（完整格式见 M3-03）：
  - 回复必须是对象，`config` 必须是对象，`config.character.name` 是字符串，`config.greetings`、`config.projects`、`config.apps` 是数组，否则整体按失败处理。
  - `media` 缺失或格式不对时用 `{avatars: [], backgrounds: []}`；列表里 `id`、`url` 不是字符串的项丢掉。
  - `uiState` → `ui`：`avatarId`、`backgroundId` 缺失或不是字符串时为 `null`；`voiceEnabled` 不是布尔值时为 `true`。
  - 项目的 `tags`、`apps` 缺失时规整为 `[]`；`hasReminders` 不是布尔值时为 `false`。
  - 待办不在 `getConfig` 里，由 `todos` 事件推送。

**`applyEvent` 处理的事件**（格式不对就整条忽略并 `console.warn`，不改 store；未知事件同样处理）：

| `event.event` | 字段 | 写入 |
|---|---|---|
| `safeArea` | `top`、`right`、`bottom`、`left`：有限、非负的数 | `safeArea` |
| `paused` | `paused`：布尔值 | `paused`；为 `true` 时同时把 `audioSpectrum` 设为 `null` |
| `systemStats` | `battery`：`{level, charging, onBattery}`，`level` 是 0–100 的整数或 `null`（缺失按 `null`），另外两个是布尔值；`cpu`：0–100 的有限数；`memory`：`{usedBytes, totalBytes, percent}`，前两个是非负有限数，`percent` 是 0–100 的有限数 | `systemStats = {battery, cpu, memory}` |
| `uiState` | `avatarId`、`backgroundId`：字符串或 `null`（缺失按 `null`）；`voiceEnabled`：布尔值（缺失按 `true`） | `ui` |
| `audioSpectrum` | `bands`：长度正好 12 的有限数数组 | `audioSpectrum = {bands: 夹到 0–1 之后的新数组, at: now()}`；`store.paused` 为 `true` 时忽略这条 |
| `todos` | `access`：`'granted'` / `'denied'` / `'notDetermined'` / `'restricted'` / `'writeOnly'` 之一；`items`：最多 500 项的数组，每项 `id`（非空字符串）、`text`（字符串，可以为空）、`done`（布尔值）、`projectId`（字符串或 `null`，缺失按 `null`）、`due`（`null`、缺失按 `null`，或 `{date, time}`：`date` 形如 `2026-10-18`，`time` 形如 `09:00` 或为 `null`） | 一次性写入 `todos = items`（规整后的新数组）和 `todosAccess = access` |

### 3. `web/js/mock.js`

```js
export function createMock({ timers = globalThis, now = () => Date.now(), random = Math.random } = {})
// timers 提供 setInterval / clearInterval（测试时传假的）
// 返回 { handle(message), start(receive), stop(), setSound(on), setPaused(paused), setTodosAccess(access), state }
```

- **`handle(message)`** 返回 Promise，校验规则和错误码与 Swift 一致（M3-03、M3-04 的表格）。参数里多出不认识的键算 `invalid`。所有 id 参数先检查：必须是非空字符串，只含字母、数字、`_`、`-`（与 Swift 的 `isValidID` 相同），否则 `invalid`；格式合法但查不到才是 `not-found`。
  - `getConfig` → 回复 mock 配置，格式与 M3-03 的 `getConfig` 回复完全一致：
    - `config`：角色名"爱弥斯"；`greetings` 用 `AGENTS.md` 配置示例里的 7 条；`projects` 3 个（`desktop-shell`，`apps: ['cursor']`，`hasReminders: true`；另外两个随意，其中一个没有 `apps`、`hasReminders: false`）；`apps` 3 个（`cursor`、`safari`，再加一个）。
    - `media`：头像 `1`–`30`，`url` 为 `/media/avatars/<id>.png`；背景 `folder-01`–`folder-06`、`settings-01`（`.png`）和 `start-01`–`start-56`（`.jpg`），`url` 为 `/media/backgrounds/<文件名>`。（和真实的运行时素材一致，开发服务器能直接显示。）
    - `uiState` 取 mock 当前的内存状态。
  - `setHitRegions`：`regions` 是数组时 resolve `null`，否则 `invalid`。
  - `openProject` / `openProjectWith` / `launchApp`：id 不在 mock 配置里 → `not-found`；否则 `console.info('mock: …')` 后 resolve `null`。
  - `addTodo`：规则同 M3-07（`text` 去掉首尾空白后不为空、不超过 500 字，否则 `invalid`；`projectId` 可以缺失或为 `null`，是字符串时项目必须存在，否则 `not-found`；项目 `hasReminders` 为 `false` 时放进"默认列表"，新提醒的 `projectId` 为 `null`）。成功后加进内存、resolve 新的一项，并推送 `todos` 事件。
  - `setTodoDone`：`todoId` 必须是内存里有的提醒（否则 `not-found`），`done` 必须是布尔值（否则 `invalid`）。成功后 resolve `null` 并推送 `todos` 事件。
  - `todosAccess` 不是 `'granted'` 时，`addTodo`、`setTodoDone` 一律回复 `failed`。
  - **不实现删除**（和 Swift 一样，没有删除提醒的动作）。
  - `saveUiState`：规则同 M3-04（两个键至少有一个；`null` 表示恢复默认；字符串必须是 mock 素材里存在的 id，否则 `not-found`）。成功后更新内存状态，resolve 新的 `{avatarId, backgroundId, voiceEnabled}`，并通过 `receive` 推送一条 `uiState` 事件（模拟 M3-05 的广播）。
  - 其他任何 action → `unknown-action`；`message` 不是对象、`action` 不是字符串 → `invalid`。
- **初始待办**（mock 内存里）5 条：关联 `desktop-shell` 且到期时间为明天 09:00；关联另一个 `hasReminders: true` 的项目、没有到期时间；不关联项目、到期日为今天但没有具体时间；不关联项目、昨天 18:00 到期（已过期）；不关联项目、今天已完成。id 用 `mock-1` 这类字符串，日期按 `now()` 计算。
- **`start(receive)`**：立刻推送 `safeArea`（`top: 25, right: 0, bottom: 80, left: 0`，模拟菜单栏和程序坞）、`paused: false`、`uiState`、`todos`（`access: 'granted'`）、一条 `systemStats`；之后每 5 秒推送一次 `systemStats`（CPU 在 3–60 之间随机游走，内存 55–75% 左右，电量缓慢下降，`onBattery: false`）；"有声音"且没有暂停时每 33 毫秒推送一次 `audioSpectrum`（合成数据即可，值在 0–1）。重复调用 `start` 不会开第二套定时器。
- `setSound(on)`：开关模拟声音（关掉时停止推送 `audioSpectrum`，模拟静音），默认开。
- `setPaused(paused)`：推送一条 `paused` 事件（模拟 Swift 暂停），暂停期间不推送 `audioSpectrum`。
- `setTodosAccess(access)`：模拟权限状态（例如 `'denied'`），推送一条 `todos` 事件；不是 `'granted'` 时 `items` 为空数组，改回 `'granted'` 时恢复内存里的待办。
- `stop()`：清掉所有定时器。
- `state`：只读地暴露 `sound`、`paused`、`todosAccess`，给调试面板显示。

### 4. 测试与脚本

- `scripts/test-web.sh`：`set -euo pipefail`，切到仓库根目录；找不到 `node` 时打印"需要 Node.js（brew install node）"并以非零退出；然后 `exec node --test "Tests/web/**/*.test.mjs"`。
- 测试文件放在 `Tests/web/`（**不要**放进 `web/`，`web/` 会被打包进 `.app`）。测试至少覆盖：
  - store：未知键被忽略且有警告；值没变不通知；多键按顺序通知且通知时能读到全部新值；监听器抛错不影响其他监听器；嵌套 `set`；通知中取消订阅；`immediate`；写入的值被冻结。
  - bridge：模式判断；native 模式的消息格式（参数不能覆盖 `action`）、resolve 回复值、`postMessage` 同步抛错变成 rejection、rejection 带 `code`；`start()` 在 mock 模式下填好 store；`postMessage` 返回 `undefined` 时 `ready` 为 `true`、`config` 为 `null`；`start()` 重复调用只请求一次；`applyEvent` 每种事件的合法和非法输入各至少一例（`todos` 至少覆盖：未知的 `access`、`items` 不是数组、某项 `done` 不是布尔值、`due.date` 格式错、缺失的 `projectId` 和 `due` 规整为 `null`）；`paused: true` 清空 `audioSpectrum`；暂停时忽略 `audioSpectrum`；`receive(null)`、`receive('x')`、`receive({})` 都不抛错。
  - mock：未知 action → `unknown-action`；不存在的 `projectId`、`appId`、头像 id → `not-found`；`projectId: '../etc'` 这类格式非法的 id → `invalid`；多出参数 → `invalid`；`saveUiState` 会推送 `uiState`；`addTodo` 的空白文本 → `invalid`、不存在的项目 → `not-found`、`hasReminders: false` 的项目放进默认列表；`setTodoDone` 不存在的 id → `not-found`、`done` 非布尔值 → `invalid`；`addTodo`、`setTodoDone` 成功后推送 `todos`；`setTodosAccess('denied')` 之后两者都回复 `failed`；用假定时器验证关掉声音、暂停时不推送 `audioSpectrum`，`stop()` 后什么都不推送。

## 允许修改的文件

- `web/js/store.js`（新建）
- `web/js/bridge.js`（新建）
- `web/js/mock.js`（新建）
- `Tests/web/store.test.mjs`、`Tests/web/bridge.test.mjs`、`Tests/web/mock.test.mjs`（新建）
- `scripts/test-web.sh`（新建，可执行）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不引入 npm 包，不建 `package.json`、`node_modules`，不加任何构建步骤。
- 不修改 `web/index.html`、`web/m2-check.js` 和任何 Swift 文件（页面在 M3-02 替换）。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `scripts/test-web.sh` 全部通过，输出里能看到上面列出的各项测试
- [ ] `grep -nE "document\.|localStorage" web/js/store.js web/js/bridge.js web/js/mock.js` 没有输出
- [ ] `git diff --name-only main...task/M3-01` 只包含"允许修改的文件"
- [ ] `ls package.json node_modules 2>&1` 显示都不存在
- [ ] `scripts/test.sh` 仍然全部通过（Swift 部分没有被影响）

**用户手动验证**：

- 无（页面在 M3-02 才有，到时一起在浏览器里看）。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
