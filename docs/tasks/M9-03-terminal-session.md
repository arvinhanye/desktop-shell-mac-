# M9-03: 终端会话：PTY 跑登录 shell（Swift）

- **状态**：todo
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

- **审查者**：
- **结论**：
- **意见**：
