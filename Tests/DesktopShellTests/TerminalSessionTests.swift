import Darwin
import Foundation
import Testing
@testable import DesktopShell

@Suite(.serialized)
@MainActor
struct TerminalSessionTests {
    private let capacity = 256 * 1024

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while !condition() {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
            do { try await Task.sleep(for: .milliseconds(5)) }
            catch { return false }
        }
        return true
    }

    private func shell(_ command: String) -> TerminalSession {
        TerminalSession(launch: TerminalLaunch(
            executable: "/bin/sh", arguments: ["-c", command], directory: "/tmp"
        ))
    }

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    @Test("环境缺少 LANG 时补 UTF-8，保留无关变量")
    func defaultEnvironment() {
        let result = terminalEnvironment(["PATH": "/bin", "CUSTOM": "retained"])
        #expect(result["LANG"] == "en_US.UTF-8")
        #expect(result["TERM"] == "xterm-256color")
        #expect(result["COLORTERM"] == "truecolor")
        #expect(result["PATH"] == "/bin")
        #expect(result["CUSTOM"] == "retained")
    }

    @Test("环境已有 LANG 时原样保留，包括空值")
    func preservedLanguage() {
        #expect(terminalEnvironment(["LANG": "zh_CN.UTF-8"])["LANG"] == "zh_CN.UTF-8")
        #expect(terminalEnvironment(["LANG": ""])["LANG"] == "")
    }

    @Test("覆盖已有 TERM 和 COLORTERM，保留用户的 LANG")
    func overriddenTerminalEnvironment() {
        let result = terminalEnvironment([
            "TERM": "dumb", "COLORTERM": "old", "LANG": "ja_JP.UTF-8"
        ])
        #expect(result["TERM"] == "xterm-256color")
        #expect(result["COLORTERM"] == "truecolor")
        #expect(result["LANG"] == "ja_JP.UTF-8")
    }

    @Test("行列数接受 1 和 1000，拒绝越界、非整数及非有限值")
    func sizeValidation() throws {
        for (cols, rows) in [(1.0, 1.0), (80.0, 24.0), (1000.0, 1000.0)] {
            let size = try #require(TerminalSize.validated(cols: cols, rows: rows))
            #expect(size.cols == Int(cols))
            #expect(size.rows == Int(rows))
        }
        for value in [-1.0, 0, 1001, 1.5, Double.nan, .infinity, -.infinity] {
            #expect(TerminalSize.validated(cols: value, rows: 24) == nil)
            #expect(TerminalSize.validated(cols: 80, rows: value) == nil)
        }
    }

    @Test("输出未到容量时逐字节保留，空追加不改变内容")
    func outputBufferPreservesBytes() {
        var buffer = TerminalOutputBuffer()
        buffer.append(Data([0x1B, 0x5B, 0x33, 0x31, 0x6D]))
        buffer.append(Data("中文".utf8))
        buffer.append(Data())
        #expect(buffer.data == Data([0x1B, 0x5B, 0x33, 0x31, 0x6D, 0xE4, 0xB8, 0xAD, 0xE6, 0x96, 0x87]))
    }

    @Test("输出超过 256 KB 时只保留最新内容")
    func outputBufferKeepsTail() {
        var buffer = TerminalOutputBuffer()
        buffer.append(Data(repeating: 0x61, count: capacity))
        #expect(buffer.data.count == capacity)
        buffer.append(Data("tail".utf8))
        #expect(buffer.data.count == capacity)
        #expect(buffer.data.prefix(4) == Data("aaaa".utf8))
        #expect(buffer.data.suffix(4) == Data("tail".utf8))
        buffer.append(Data(repeating: 0x7A, count: capacity + 100))
        #expect(buffer.data == Data(repeating: 0x7A, count: capacity))
    }

    @Test("截断落在中文字符中间时移除开头的 UTF-8 后续字节")
    func outputBufferTrimsPartialUTF8Prefix() {
        var buffer = TerminalOutputBuffer()
        buffer.append(Data("中".utf8))
        buffer.append(Data(repeating: 0x78, count: capacity - 1))
        #expect(buffer.data.count == capacity - 1)
        #expect(buffer.data.first == 0x78)
        #expect(String(data: buffer.data, encoding: .utf8) != nil)
    }

    @Test("跨两次读取的 UTF-8 字符在未截断时不被丢弃")
    func outputBufferPreservesSplitUTF8() {
        var buffer = TerminalOutputBuffer()
        buffer.append(Data([0xE4]))
        buffer.append(Data([0xB8, 0xAD]))
        #expect(String(data: buffer.data, encoding: .utf8) == "中")
    }

    @Test("真实 PTY 交付退出前的输出和状态，回调都在主线程")
    func outputAndExitOnMainThread() async throws {
        let session = shell("printf hi; exit 3")
        defer { session.terminate() }
        var received = Data()
        var exits: [Int32] = []
        var callbacksOnMainThread: [Bool] = []
        var outputAtExit = Data()
        session.onOutput = {
            callbacksOnMainThread.append(Thread.isMainThread)
            received.append($0)
        }
        session.onExit = {
            callbacksOnMainThread.append(Thread.isMainThread)
            outputAtExit = received
            exits.append($0)
        }
        try #require(session.start(cols: 80, rows: 24))
        try #require(await waitUntil { !exits.isEmpty })
        #expect(text(received).contains("hi"))
        #expect(text(outputAtExit).contains("hi"))
        #expect(exits == [3])
        #expect(!session.isRunning)
        #expect(session.recentOutput == received)
        #expect(callbacksOnMainThread.count >= 2)
        #expect(callbacksOnMainThread.allSatisfy { $0 })
    }

    @Test("真实 PTY 写入 cat 并收到回显")
    func writesInput() async throws {
        let session = TerminalSession(launch: TerminalLaunch(executable: "/bin/cat", arguments: []))
        defer { session.terminate() }
        var received = Data()
        var exit: Int32?
        session.onOutput = { received.append($0) }
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 80, rows: 24))
        session.write(Data("abc\n".utf8))
        try #require(await waitUntil { text(received).contains("abc") })
        session.terminate()
        try #require(await waitUntil { exit != nil })
        #expect(!session.isRunning)
    }

    @Test("resize 修改真实 PTY 的行列数")
    func resizesPTY() async throws {
        let session = TerminalSession(launch: TerminalLaunch(executable: "/bin/sh", arguments: []))
        defer { session.terminate() }
        var received = Data()
        var exit: Int32?
        session.onOutput = { received.append($0) }
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 80, rows: 24))
        session.resize(cols: 120, rows: 30)
        session.write(Data("stty size\n".utf8))
        try #require(await waitUntil { text(received).contains("30 120") })
        #expect(session.lastSize.cols == 120)
        #expect(session.lastSize.rows == 30)
        session.write(Data("exit\n".utf8))
        try #require(await waitUntil { exit != nil })
    }

    @Test("真实子进程使用配置的工作目录与终端环境")
    func launchDirectoryAndEnvironment() async throws {
        let session = TerminalSession(launch: TerminalLaunch(
            executable: "/bin/sh", arguments: ["-c", "printf '%s|%s|%s|' \"$TERM\" \"$COLORTERM\" \"$LANG\"; /bin/pwd"],
            directory: "/private/tmp", environment: ["LANG": "zh_CN.UTF-8", "TERM": "dumb"]
        ))
        defer { session.terminate() }
        var exit: Int32?
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 80, rows: 24))
        try #require(await waitUntil { exit != nil })
        #expect(exit == 0)
        #expect(text(session.recentOutput).contains("xterm-256color|truecolor|zh_CN.UTF-8|/private/tmp"))
    }

    @Test("运行中重复 start 不重启、不清空输出、不改尺寸")
    func runningStartIsIdempotent() async throws {
        let session = shell("printf ready; exec /bin/cat")
        defer { session.terminate() }
        var exit: Int32?
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 80, rows: 24))
        try #require(await waitUntil { text(session.recentOutput).contains("ready") })
        let retained = session.recentOutput
        #expect(session.start(cols: 120, rows: 30))
        #expect(session.start(cols: 0, rows: 0))
        #expect(session.recentOutput == retained)
        #expect(session.lastSize.cols == 80)
        #expect(session.lastSize.rows == 24)
        session.write(Data("still-running\n".utf8))
        try #require(await waitUntil { text(session.recentOutput).contains("still-running") })
        session.terminate()
        try #require(await waitUntil { exit != nil })
    }

    @Test("退出后保留输出；重开清空旧输出，并使用保留的尺寸")
    func restartPreservesSizeAndClearsOutput() async throws {
        let session = shell("read line; printf 'value:%s;' \"$line\"; stty size")
        defer { session.terminate() }
        var exits: [Int32] = []
        session.onExit = { exits.append($0) }
        try #require(session.start(cols: 96, rows: 32))
        session.write(Data("first\n".utf8))
        try #require(await waitUntil { exits.count == 1 })
        let firstOutput = session.recentOutput
        #expect(text(firstOutput).contains("value:first;"))
        #expect(text(firstOutput).contains("32 96"))
        session.write(Data("ignored\n".utf8))
        #expect(session.recentOutput == firstOutput)
        try #require(session.start(cols: session.lastSize.cols, rows: session.lastSize.rows))
        #expect(session.recentOutput.isEmpty)
        session.write(Data("second\n".utf8))
        try #require(await waitUntil { exits.count == 2 })
        #expect(exits == [0, 0])
        #expect(text(session.recentOutput).contains("value:second;"))
        #expect(!text(session.recentOutput).contains("first"))
        #expect(text(session.recentOutput).contains("32 96"))
    }

    @Test("无效尺寸不启动会话或污染最后的有效尺寸")
    func invalidSizesDoNotChangeState() async throws {
        let session = shell("printf ready; exec /bin/cat")
        defer { session.terminate() }
        #expect(session.lastSize.cols == 80)
        #expect(session.lastSize.rows == 24)
        session.resize(cols: 100, rows: 40)
        for (cols, rows) in [(0, 24), (80, 0), (1001, 24), (80, 1001), (-1, 24)] {
            #expect(!session.start(cols: cols, rows: rows))
            session.resize(cols: cols, rows: rows)
            #expect(!session.isRunning)
            #expect(session.lastSize.cols == 100)
            #expect(session.lastSize.rows == 40)
        }
        var exit: Int32?
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 100, rows: 40))
        try #require(await waitUntil { text(session.recentOutput).contains("ready") })
        session.resize(cols: 0, rows: 1001)
        #expect(session.lastSize.cols == 100)
        #expect(session.lastSize.rows == 40)
        session.terminate()
        try #require(await waitUntil { exit != nil })
    }

    @Test("terminate 发 SIGHUP，退出状态为 128 加信号编号，重复调用安全")
    func terminationReportsSignal() async throws {
        let session = shell("printf ready; exec /bin/cat")
        defer { session.terminate() }
        var exits: [Int32] = []
        session.onExit = { exits.append($0) }
        session.terminate()
        try #require(session.start(cols: 80, rows: 24))
        try #require(await waitUntil { text(session.recentOutput).contains("ready") })
        session.terminate()
        session.terminate()
        try #require(await waitUntil { !exits.isEmpty })
        #expect(exits == [128 + SIGHUP])
        #expect(!session.isRunning)
        #expect(text(session.recentOutput).contains("ready"))
        session.terminate()
    }

    @Test("execve 失败以 127 退出且不遗留运行状态")
    func failedExecutableExits127() async throws {
        let session = TerminalSession(launch: TerminalLaunch(
            executable: "/desktop-shell-missing-executable", arguments: [], directory: "/tmp"
        ))
        defer { session.terminate() }
        var exit: Int32?
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 80, rows: 24))
        try #require(await waitUntil { exit != nil })
        #expect(exit == 127)
        #expect(!session.isRunning)
    }

    @Test("chdir 失败以 127 退出，不在错误目录执行命令")
    func failedDirectoryExits127() async throws {
        let session = TerminalSession(launch: TerminalLaunch(
            executable: "/bin/sh", arguments: ["-c", "printf should-not-run"],
            directory: "/desktop-shell-missing-directory"
        ))
        defer { session.terminate() }
        var exit: Int32?
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 80, rows: 24))
        try #require(await waitUntil { exit != nil })
        #expect(exit == 127)
        #expect(!session.isRunning)
        #expect(!text(session.recentOutput).contains("should-not-run"))
    }

    @Test("密集短输出合并交付，进程退出前的尾部不丢失")
    func batchesOutputAndDrainsExitTail() async throws {
        let session = shell("i=0; while [ \"$i\" -lt 1200 ]; do printf 0123456789; i=$((i + 1)); done")
        defer { session.terminate() }
        var received = Data()
        var batches = 0
        var exit: Int32?
        session.onOutput = { received.append($0); batches += 1 }
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 80, rows: 24))
        try #require(await waitUntil { exit != nil })
        #expect(exit == 0)
        #expect(received == Data(String(repeating: "0123456789", count: 1200).utf8))
        #expect(batches > 0)
        #expect(batches < 100)
        #expect(session.recentOutput == received)
    }

    @Test("持续短输出分成多批，主线程相邻回调至少间隔 15 ms")
    func outputCallbacksRespectBatchInterval() async throws {
        let session = shell("i=0; while [ \"$i\" -lt 64 ]; do printf x; /bin/sleep 0.004; i=$((i + 1)); done")
        defer { session.terminate() }
        var received = Data()
        var callbackTimes: [ContinuousClock.Instant] = []
        var exit: Int32?
        session.onOutput = {
            callbackTimes.append(ContinuousClock.now)
            received.append($0)
        }
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 80, rows: 24))
        try #require(await waitUntil { exit != nil })
        #expect(exit == 0)
        #expect(received == Data(repeating: 0x78, count: 64))
        try #require(callbackTimes.count >= 3)
        for (previous, next) in zip(callbackTimes, callbackTimes.dropFirst()) {
            #expect(previous.duration(to: next) >= .milliseconds(15))
        }
    }

    @Test("释放运行中的会话会结束并回收它自己的子进程")
    func releasedSessionReapsItsChild() async throws {
        var session: TerminalSession? = shell("printf '%s\\n' \"$$\"; exec /bin/cat")
        weak let releasedSession = session
        var received = Data()
        var childPID: pid_t?
        var childWasReaped = false
        defer {
            session?.terminate()
            releasedSession?.terminate()
            // Only the PID printed by this test's own child can need fallback cleanup.
            if let childPID, !childWasReaped { _ = kill(childPID, SIGHUP) }
        }
        session?.onOutput = { received.append($0) }
        try #require(session?.start(cols: 80, rows: 24) == true)
        try #require(await waitUntil { received.contains(0x0A) })
        let pid = try #require(pid_t(text(received).trimmingCharacters(in: .whitespacesAndNewlines)))
        try #require(pid > 0 && pid != getpid())
        childPID = pid
        try #require(kill(pid, 0) == 0)
        session = nil
        #expect(releasedSession == nil)
        childWasReaped = await waitUntil {
            let result = kill(pid, 0)
            return result == -1 && errno == ESRCH
        }
        #expect(childWasReaped)
    }

    @Test("PTY 写入背压后仍完整传输，重推缓冲只保留最近 256 KB")
    func writeBackpressurePreservesData() async throws {
        let session = shell("stty raw -echo; printf ready; sleep 0.15; exec /bin/cat")
        defer { session.terminate() }
        var received = Data()
        var exit: Int32?
        session.onOutput = { received.append($0) }
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 80, rows: 24))
        try #require(await waitUntil { text(received).contains("ready") })
        received.removeAll()
        let payload = Data(String(repeating: "0123456789abcdef", count: 32768).utf8)
        session.write(payload)
        try #require(await waitUntil(timeout: 10) { received.count >= payload.count })
        #expect(received == payload)
        #expect(session.recentOutput.count == capacity)
        #expect(session.recentOutput == Data(payload.suffix(capacity)))
        session.terminate()
        try #require(await waitUntil { exit != nil })
    }

    @Test("主线程繁忙时 PTY 施加背压，恢复后完整交付积压输出")
    func stalledMainThreadBackpressuresChild() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("finished")
        let session = TerminalSession(launch: TerminalLaunch(
            executable: "/bin/sh", arguments: ["-c", "stty raw -echo; printf ready; read token; /usr/bin/head -c 1048576 /dev/zero; printf done > finished"],
            directory: directory.path
        ))
        defer { session.terminate() }
        var received = Data()
        var exit: Int32?
        session.onOutput = { received.append($0) }
        session.onExit = { exit = $0 }
        try #require(session.start(cols: 80, rows: 24))
        try #require(await waitUntil { text(received).contains("ready") })
        received.removeAll()
        session.write(Data("go\n".utf8))
        // Deliberately stall main-thread delivery. The IO queue remains runnable.
        // A bounded reader must leave the writer blocked before it reaches the marker.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline && !FileManager.default.fileExists(atPath: marker.path) {
            usleep(5000)
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        try #require(await waitUntil(timeout: 10) { exit != nil })
        #expect(exit == 0)
        #expect(received == Data(repeating: 0, count: 1048576))
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

}
