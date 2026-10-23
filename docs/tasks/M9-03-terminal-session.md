# M9-03: 终端会话：PTY 跑登录 shell（Swift）

- **状态**：review
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

- **改动摘要**：从 `main`（`d15e0a1`）独立创建 `task/M9-03`，不包含 M9-01 的网页修改。新增 `TerminalLaunch`、`@MainActor TerminalSession`、`TerminalSize.validated(cols: Double, rows: Double)`、`terminalEnvironment` 和 `TerminalOutputBuffer`。公开会话接口保持任务约定；`lastSize` 是有 `cols` / `rows` 的 `TerminalSize`，初始 80×24。默认登录 shell、环境、工作目录按规范；start 幂等，resize 无效尺寸不污染状态，退出保留输出，重开清空输出。
  - 后台串行队列负责 PTY 读写；EINTR 重试，EAGAIN 通过可写事件继续发送，保留短写偏移，不忙等或阻塞主线程。输出以 16 ms 批次交给主线程，确认上一批已交付后才安排下一批，退出先排空尾部再回调状态。read/write source 全部完成取消后才 close，避免 fd 复用竞态；释放会话同样发送 SIGHUP 并保留退出监听直至 waitpid 回收。
  - 最近输出上限 256 KiB，截断时避开 UTF-8 后续字节。自查发现待交付输出可能在主线程忙碌时堆积，已补读端背压：积压达到 256 KiB 时暂停 read source，主线程接收后恢复，不丢字；退出时正确恢复并取消 suspended source。
- **自测结果**：
  - 基线 `scripts/test.sh` **276/276 PASS**；最终 **299/299 PASS（30 suites）**。新增 `TerminalSessionTests` **23/23 PASS**，覆盖环境、尺寸边界/非整数/非有限、UTF-8 分块与容量、真实 sh 退出码、cat 写入、stty 改尺寸、默认状态/幂等/重开、工作目录/环境、SIGHUP、exec/chdir 失败 127、主线程回调节流、释放后进程回收、512 KiB 写入背压、主线程阻塞后 1 MiB 输出仍完整。
  - 先写测试验证类型缺失 RED；实现后通过。自查修复的主线程背压另有真实 RED→GREEN：旧实现会在主线程阻塞时提前写完 marker，新实现让子进程受 PTY 背压，恢复后输出和 marker 完整。
  - 最终 `swift build` 成功、无编译错误/警告；`git diff --check` 通过。日志检查仅开始 pid、退出 status 与 errno，不含终端输入/输出或长度。子代理只读自查和 debug 目标文件反汇编核对 forkpty 子路径仅 chdir/execve/_exit，无 Swift runtime 调用（自查不是正式审查）。
  - 证据位于 `build/m9-validation/`：`M9-03-full-tests.log`、`M9-03-build-final.log`、`M9-03-targeted-final.log`、`M9-03-backpressure-red.log`。最初沙盒运行被 Swift 模块缓存写权限阻止，以上结果均来自正常本机权限下的项目脚本；未修改签名、系统权限或运行配置。
- **疑问 / 偏离**：无范围偏离，仅新增两份允许文件并更新本任务状态/交付记录。没有接入窗口或 bridge，不构建终端面板；交互验收按任务单留到 M9-05。M9-01 与本任务分别在独立分支交付；未合并 `main`。任务分支推送被自动审批拦截；虽然已通过 GitHub 连接器核实远端归属和推送权限，审批仍要求用户在对话中明确授权向 `https://github.com/arvinhanye/desktop-shell-mac-` 推送，故暂作本地交付。
- **审查修改（2026-10-23，对应 `main` 的审查记录 `e8ecd0e`）**：
  - 修复 P2：退出事件先进入排空阶段，停止写入并取消读取源（已暂停时先恢复再取消）；只有读到 EOF / EIO / EAGAIN 后才调用 `waitpid`。达到 256 KiB 积压上限时继续保留 PTY 和子进程，待主线程交付上一批输出、返回 ACK 后续读，不把一次读取预算耗尽当成排空完成。退出状态仍在最后一批 `onOutput` 完成后交付，保持原有节流、内存上限和 fd 取消顺序。
  - 新增两项真实 PTY 检查：一项让首个输出回调暂不返回，积压 256 KiB 和中文尾串，核对恢复后的完整输出、最近 256 KiB 及退出顺序；另一项复用生产 shell 启动函数，待独立 marker 确认真实子进程已写完尾部后，人工调度后台 worker 的退出入口，强制退出处理早于首次读取。这项窄回归不声称覆盖内核退出事件的投递；通知路径由现有端到端测试与延迟监听探针覆盖。为此仅将启动函数、worker 和其串行化退出入口改为模块内可见，未改动公开会话接口、未添加运行时测试分支。高水位测试本身不保证事件顺序，也能在原版通过；原有读写背压和释放回收测试保留。
  - 最终 `scripts/test.sh --jobs 4` **301/301 PASS（30 suites，终端组 25 项）**；`swift build --jobs 4` 成功且无编译错误/警告；`git diff --check` 通过。日志仍仅 pid、status、errno。独立子代理自查未发现新增生命周期或回调顺序问题，仅算实现自查，不代替正式复审。
  - 同一退出入口回归对旧版逻辑 **RED**（等待 `onExit` 5 秒超时），对修复版 **GREEN**（17 字节尾部、退出码 3、退出前交付完整输出和回收均通过）。隔离旧版仅同步模块可见性及队列转发，保留先 waitpid 后读的原逻辑。最终源码另经审查者延迟监听探针 **30/30 PASS**；fd 数 **4→4**，提前释放后无残留子进程。验证产物保存在 `build/m9-validation/M9-03-revision/`：`full-tests-final.log`、`build-final.log`、`regression-scheduled-exit-original-red.log`、`regression-scheduled-exit-green.log`、`exit-tail-fixed.log`。`regression-notes.md` 区分最终证据和没有区分能力的中间测试构造，后者不算修复证明。
  - 超时证据边界：本次原版延迟探针也会卡住，父进程采样显示终端队列已进入退出处理并阻塞在 `__wait4`（725/725 个样本）；对照副本先读后等即通过。独立 C 探针同时确认先读后回收有 4 字节、先回收后读为 0。详见 `quick-exit-diagnosis.md`、`diagnostic-parent.sample.txt`、`pty-tail-before.log`。这证明本次可复现超时受读/回收顺序影响；审查最初那次全量测试超时没有当时调用栈，**仍不能断言同因，也不以本次通过抹去**。原审查记录保留在 `main`，本次未修改审查者内容。

<!-- ===== 以下由审查者填写（Claude Code，或没参与实现的另一个 Codex 会话） ===== -->

## 审查记录

- **审查者**：
- **结论**：
- **意见**：
