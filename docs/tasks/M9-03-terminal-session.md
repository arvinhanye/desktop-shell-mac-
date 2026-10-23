# M9-03: 终端会话：PTY 跑登录 shell（Swift）

- **状态**：changes-requested
- **里程碑**：M9
- **依赖**：无。和 M9-01、M9-02、M9-04 互不依赖；M9-05 依赖本任务
- **分支**：task/M9-03

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

新建 `TerminalSession`：用 `forkpty` 跑用户的登录 shell，提供写入、改行列数、结束；把输出合并后交给调用方；保留最近 256 KB 的输出用于重推；能知道 shell 什么时候退出、退出状态是多少。

本任务只做会话本身和测试，不接面板、不接 bridge（M9-05 做）。

## 背景与约束

- 先读 AGENTS.md：
  - "技术探针"的终端面板探针：PTY 和环境变量两段；
  - Bridge 接口下面的"终端会话"一节；
  - "安全要求"里终端的日志规则。
- 探针里验证过的做法：
  - `fork` 之前用 `strdup` 准备好 argv、envp、工作目录，子进程里只调用 `chdir` + `execve`，失败就 `_exit(127)`；
  - 主端设成非阻塞，用 `DispatchSourceRead` 读；
  - 用 `DispatchSourceProcess`（`.exit`）知道退出，然后 `waitpid`；
  - 改行列数用 `ioctl(fd, 0x80087467 /* TIOCSWINSZ */, &winsize)`。

### 接口（名字可以调整，交付记录里写清楚）

- **初始化**：`TerminalSession(launch: TerminalLaunch)`。`TerminalLaunch` 里有：
  - `executable`：默认取环境变量 `SHELL`，没有就用 `/bin/zsh`；
  - `arguments`：默认 `["-l"]`；
  - `directory`：默认 `~`；
  - `environment`：默认取本进程的环境变量。
  - 测试里可以换成别的程序。
- **`start(cols:rows:) -> Bool`**：已经在运行时直接返回 `true`；`forkpty` 失败时记日志，返回 `false`。
- **`write(_ data: Data)`**：写满为止，遇到 `EAGAIN` / `EINTR` 就重试，其他错误记日志后放弃这一次。没有在运行时什么都不做。
- **`resize(cols:rows:)`**：记住尺寸，在运行时调用 `ioctl`。
- **`terminate()`**：给 shell 发 `SIGHUP`。退出应用时调用。
- **状态**：`isRunning`、`lastSize`（最后一次 `start` 或 `resize` 的尺寸）、`recentOutput`（最近的输出，最多 256 KB）。
- **回调**：都在主线程调用。
  - `onOutput(Data)`：读到的数据合并后交出，最多每 16 ms 一次；
  - `onExit(Int32)`：退出状态，正常退出时是 `WEXITSTATUS`，被信号结束时是 128 + 信号编号。

### 纯函数（单独测试）

- **环境变量**：在给定的环境上补 `TERM=xterm-256color`、`COLORTERM=truecolor`，没有 `LANG` 时补 `LANG=en_US.UTF-8`。已有的 `LANG` 不动，`TERM` 和 `COLORTERM` 总是覆盖。
- **行列数校验**：`cols`、`rows` 都要是 1–1000 的整数。M9-05 的 bridge 会用到。
- **重推缓冲区**：追加数据，超过 256 KB 就丢掉最旧的部分。丢掉以后，开头如果是 UTF-8 的后续字节（`0x80`–`0xBF`），继续丢到下一个字符的开头，避免重推时第一个字乱码。

### 其他要求

- shell 退出后，`isRunning` 变成 `false`，`recentOutput` 保留。再次 `start` 时清空缓冲区、开新的 shell，`lastSize` 照旧可用。
- **日志**：只写 `terminal session started pid=…`、`terminal session exited status=…` 和错误（`errno`）。**绝不写输入、输出的内容和长度。**
- 读取放在后台队列，回调切回主线程；多次输出在 16 ms 内合并成一次。

## 允许修改的文件

- `Sources/DesktopShell/TerminalSession.swift`（新建）
- `Tests/DesktopShellTests/TerminalSessionTests.swift`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改别的 Swift 文件，不接 bridge 和窗口。
- 不用 `Process` / `posix_spawn` 替代 `forkpty`（拿不到控制终端，探针用的就是 `forkpty`）。
- 不在子进程里调用 Swift 运行时的函数（分配内存、打日志等）。

## 验收标准

**可执行的检查**（实现者自测，审查者复验）：

- [ ] `swift build` 无错误、无警告
- [ ] `scripts/test.sh` 全部通过，`TerminalSessionTests` 至少覆盖下面几项：
  - [ ] 环境变量函数：三种情况（没有 `LANG`、已有 `LANG`、已有 `TERM`）；
  - [ ] 行列数校验：边界 0、1、1000、1001，以及非整数；
  - [ ] 重推缓冲区：不超过 256 KB；截断后不以 UTF-8 后续字节开头；
  - [ ] 真实 PTY：跑 `/bin/sh -c 'printf hi; exit 3'`，`onOutput` 收到的内容含 `hi`，`onExit` 收到 `3`，之后 `isRunning` 为 `false`；
  - [ ] 真实 PTY 改尺寸：`start(cols: 80, rows: 24)` 跑 `/bin/sh`，`resize(cols: 120, rows: 30)` 后写入 `stty size\n`，输出里有 `30 120`；
  - [ ] 写入：跑 `/bin/cat`，写入 `abc\n`，输出里有 `abc`；
  - [ ] 退出后能重新 `start`。
- [ ] `grep -n "Log\." Sources/DesktopShell/TerminalSession.swift`：日志只有开始、退出和错误这几类，不含任何输入输出变量
- [ ] `git diff --name-only main...task/M9-03` 只有上面"允许修改的文件"

**用户手动验证**：本任务没有，并到 M9-05。

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由审查者填写（Claude Code，或没参与实现的另一个 Codex 会话） ===== -->

## 审查记录

- **审查者**：Codex（独立会话，2026-10-23；未参与实现）。
- **结论**：不通过，`changes-requested`。发现 1 个已确定的 P2：回收子进程早于 PTY 尾部读取，导致退出时丢失输出。实现分支 `task/M9-03`（`887344a`）不合并；本记录单独写入 `main`，不改变实现者工作区或任务分支。
- **意见**：
  - **[P2] 在回收子进程前可靠排空 PTY 尾部**。`Sources/DesktopShell/TerminalSession.swift:371` 先 `waitpid`，第 380 行才 `readAvailable()`。退出事件先于读事件得到处理时，本机 macOS 会在回收后使尚未读取的 PTY 输出不可恢复，`onOutput` 与 `recentOutput` 都缺失末尾字节。独立 C 探针让子进程写 `tail` 并退出，父进程延迟 100ms：先读后回收得到 4 字节，先回收后读得到 0 字节。
  - 原始 TerminalSession 源码不变，仅在独立探针的 started 日志桩中延迟 100ms，连续 30 次均收到退出码 3 但输出为空；重复执行相同结果。仅在 `/tmp` 对照副本把读取放到 `waitpid` 前，同条件 30/30 输出完整，fd 计数保持 4，无残留子进程。此副本只用于定位，未应用到业务代码。
  - 修复时需在回收前确保尾部已排空，并处理 `pendingOutput` 达到背压上限、reader 已暂停的情况，不能简单依赖普通读取路径的 256KiB 上限。新增能确定触发退出先于读取的回归测试，核对最终输出和退出回调顺序；同时保留既有背压与资源回收覆盖。
  - 全部 3 个变更文件（398 行实现、426 行测试、任务单）已审，覆盖率 100%，无跳过；改动范围、日志隐私、fork 子路径、source 取消/关 fd 顺序符合要求。常规额外探针：onExit 内立即重开 200 次、启动后立即释放 200 次均通过，不抵消上述确定缺陷。
  - 独立 worktree 执行 `swift build` 成功，无编译警告/错误。首次全量测试为 298/299（30 suites），`TerminalSessionTests.swift:128` 等待快速退出 shell 的 onExit 超时；随后单例 1/1、终端组 23/23、低负载全量 299/299 均通过。**首次超时根因尚未确定**，不能将其直接归因为上述尾部丢失，也不能以复跑通过抹去。人工延后监听注册仍收到退出回调，未证明存在漏退出通知竞态。
  - 完整命令与日志保存在本审查 worktree 的 `build/m9-review/M9-03/`；确定性探针源码与结果保存在其 `probes/`。初始沙盒阻止 Swift 缓存/manifest sandbox，正常权限重试完成；未修改系统权限或签名信任。审查未修改实现逻辑。
