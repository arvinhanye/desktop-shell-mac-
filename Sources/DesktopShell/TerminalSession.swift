import Darwin
import Foundation

struct TerminalLaunch {
    let executable: String
    let arguments: [String]
    let directory: String
    let environment: [String: String]

    init(executable: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
         arguments: [String] = ["-l"], directory: String = NSHomeDirectory(),
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
    }
}

func terminalEnvironment(_ environment: [String: String]) -> [String: String] {
    var result = environment
    result["TERM"] = "xterm-256color"
    result["COLORTERM"] = "truecolor"
    if result["LANG"] == nil { result["LANG"] = "en_US.UTF-8" }
    return result
}

struct TerminalSize: Equatable {
    let cols: Int
    let rows: Int

    static func validated(cols: Double, rows: Double) -> TerminalSize? {
        guard cols.isFinite, rows.isFinite,
              (1...1000).contains(cols), (1...1000).contains(rows),
              cols.rounded(.towardZero) == cols, rows.rounded(.towardZero) == rows else { return nil }
        return TerminalSize(cols: Int(cols), rows: Int(rows))
    }

    fileprivate var windowSize: winsize {
        winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
    }
}

struct TerminalOutputBuffer {
    private(set) var data = Data()

    mutating func append(_ incoming: Data) {
        data.append(incoming)
        let excess = data.count - 256 * 1024
        guard excess > 0 else { return }
        data.removeFirst(excess)
        let continuationCount = data.prefix { (0x80...0xBF).contains($0) }.count
        data.removeFirst(continuationCount)
    }
}

/// Public state and callbacks belong to the UI thread; PTY reads/writes never block it.
@MainActor
final class TerminalSession {
    private let launch: TerminalLaunch
    private var process: TerminalProcess?
    private var generation: UInt64 = 0
    private var output = TerminalOutputBuffer()
    private(set) var isRunning = false
    private(set) var lastSize = TerminalSize(cols: 80, rows: 24)
    var recentOutput: Data { output.data }
    var onOutput: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?

    init(launch: TerminalLaunch = TerminalLaunch()) { self.launch = launch }

    @discardableResult
    func start(cols: Int, rows: Int) -> Bool {
        if isRunning { return true }
        guard let size = TerminalSize.validated(cols: Double(cols), rows: Double(rows)) else { return false }
        guard let child = launchTerminal(launch, size: size) else { return false }
        generation &+= 1
        let current = generation
        lastSize = size
        output = TerminalOutputBuffer()
        isRunning = true
        let process = TerminalProcess(pid: child.pid, fd: child.fd, onOutput: { [weak self] bytes in
            guard let self, self.generation == current else { return }
            self.output.append(bytes)
            self.onOutput?(bytes)
        }, onExit: { [weak self] status in
            guard let self, self.generation == current else { return }
            self.isRunning = false
            self.process = nil
            self.onExit?(status)
        })
        self.process = process
        Log.notice("terminal session started pid=\(child.pid)")
        process.begin()
        return true
    }

    func write(_ data: Data) {
        guard isRunning, !data.isEmpty else { return }
        process?.write(data)
    }

    func resize(cols: Int, rows: Int) {
        guard let size = TerminalSize.validated(cols: Double(cols), rows: Double(rows)) else { return }
        lastSize = size
        process?.resize(size)
    }

    func terminate() { process?.terminate() }

    deinit { process?.terminate() }
}

/// All allocations and Swift collection access finish before forkpty.
func launchTerminal(_ launch: TerminalLaunch, size: TerminalSize) -> (pid: pid_t, fd: Int32)? {
    let environment = terminalEnvironment(launch.environment)
    let values = [launch.executable, launch.directory] + launch.arguments + environment.map { "\($0.key)=\($0.value)" }
    guard !values.contains(where: { $0.utf8.contains(0) }),
          !environment.keys.contains(where: { $0.isEmpty || $0.contains("=") }) else {
        Log.error("terminal launch failed errno=\(EINVAL)")
        return nil
    }
    let executable = strdup(launch.executable)
    let directory = strdup(launch.directory)
    var arguments = ([launch.executable] + launch.arguments).map { strdup($0) }
    var variables = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") }
    defer {
        free(executable)
        free(directory)
        arguments.forEach { free($0) }
        variables.forEach { free($0) }
    }
    guard let executable, let directory, !arguments.contains(where: { $0 == nil }),
          !variables.contains(where: { $0 == nil }) else {
        Log.error("terminal launch failed errno=\(ENOMEM)")
        return nil
    }
    arguments.append(nil)
    variables.append(nil)
    var fd: Int32 = -1
    var windowSize = size.windowSize
    let pid = arguments.withUnsafeMutableBufferPointer { argumentBuffer in
        variables.withUnsafeMutableBufferPointer { environmentBuffer in
            let argv = argumentBuffer.baseAddress!
            let envp = environmentBuffer.baseAddress!
            let pid = forkpty(&fd, nil, nil, &windowSize)
            if pid == 0 {
                // Child: only async-signal-safe C calls; never return into Swift.
                if chdir(directory) != 0 { _exit(127) }
                execve(executable, argv, envp)
                _exit(127)
            }
            return pid
        }
    }
    guard pid >= 0 else {
        Log.error("terminal forkpty failed errno=\(errno)")
        return nil
    }
    let flags = fcntl(fd, F_GETFL)
    guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0,
          fcntl(fd, F_SETFD, FD_CLOEXEC) >= 0 else {
        let code = errno
        close(fd)
        kill(pid, SIGKILL)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        Log.error("terminal fcntl failed errno=\(code)")
        return nil
    }
    return (pid, fd)
}

/// Sources sharing an fd must all finish cancellation before it may be reused.
/// Accessed only on TerminalProcess.queue.
private final class TerminalDescriptor {
    let fd: Int32
    private var sources = 0
    private var closing = false
    private var closed = false
    init(_ fd: Int32) { self.fd = fd }
    func retainSource() { sources += 1 }
    func releaseSource() { sources -= 1; closeIfReady() }
    func requestClose() { closing = true; closeIfReady() }
    private func closeIfReady() {
        if closing && sources == 0 && !closed { closed = true; close(fd) }
    }
}

/// Serial PTY worker; event entry points enqueue work on its own IO queue.
final class TerminalProcess {
    private let queue = DispatchQueue(label: "DesktopShell.terminal.io")
    private let pid: pid_t
    private let descriptor: TerminalDescriptor
    private let onOutput: @MainActor (Data) -> Void
    private let onExit: @MainActor (Int32) -> Void
    private var reader: DispatchSourceRead?
    private var readerSuspended = false
    private var writer: DispatchSourceWrite?
    private var exitSource: DispatchSourceProcess?
    private var pendingOutput = Data()
    private var outputScheduled = false
    private var pendingInput = Data()
    private var inputOffset = 0
    private var childHasExited = false
    private var exitStatus: Int32?
    private var exitDelivered = false

    init(pid: pid_t, fd: Int32, onOutput: @escaping @MainActor (Data) -> Void,
         onExit: @escaping @MainActor (Int32) -> Void) {
        self.pid = pid
        descriptor = TerminalDescriptor(fd)
        self.onOutput = onOutput
        self.onExit = onExit
    }

    func begin() {
        queue.async {
            let reader = DispatchSource.makeReadSource(fileDescriptor: self.descriptor.fd, queue: self.queue)
            self.descriptor.retainSource()
            reader.setCancelHandler { [descriptor = self.descriptor] in descriptor.releaseSource() }
            reader.setEventHandler { [weak self] in
                guard let self, !self.childHasExited else { return }
                _ = self.readAvailable()
            }
            self.reader = reader
            // The exit handler keeps this worker alive until the child has been reaped,
            // even when its UI owner has been released in the meantime.
            let exit = DispatchSource.makeProcessSource(identifier: self.pid, eventMask: .exit, queue: self.queue)
            exit.setEventHandler { self.childExited() }
            self.exitSource = exit
            reader.activate()
            exit.activate()
        }
    }

    func write(_ bytes: Data) {
        queue.async {
            guard !self.childHasExited else { return }
            self.pendingInput.append(bytes)
            self.writeAvailable()
        }
    }

    func resize(_ size: TerminalSize) {
        queue.async {
            guard !self.childHasExited else { return }
            var windowSize = size.windowSize
            if ioctl(self.descriptor.fd, 0x80087467, &windowSize) < 0 {
                Log.error("terminal resize failed errno=\(errno)")
            }
        }
    }

    func terminate() {
        queue.async {
            guard !self.childHasExited else { return }
            if kill(self.pid, SIGHUP) < 0 && errno != ESRCH {
                Log.error("terminal terminate failed errno=\(errno)")
            }
        }
    }

    /// True only after reaching the end of the currently available output.
    /// False means a later batch must continue reading before the child is reaped.
    private func readAvailable() -> Bool {
        var bytes = [UInt8](repeating: 0, count: 16384)
        var readCount = 0
        // Yield between bursts so a continuously writing child cannot starve writes,
        // resizing, termination or the 16 ms output timer on this serial queue.
        while readCount < 256 * 1024 {
            // Bound queued output as well as replay. Suspending the source lets the
            // PTY backpressure the child while the UI is busy, without dropping bytes.
            if pendingOutput.count >= 256 * 1024 {
                if !readerSuspended, let reader {
                    reader.suspend()
                    readerSuspended = true
                }
                return false
            }
            let capacity = min(bytes.count, 256 * 1024 - pendingOutput.count)
            let count = Darwin.read(descriptor.fd, &bytes, capacity)
            if count > 0 {
                pendingOutput.append(contentsOf: bytes.prefix(count))
                readCount += count
                scheduleOutput()
            } else if count == 0 || (count < 0 && errno == EIO) {
                cancelReader()
                return true
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN {
                return true
            } else {
                Log.error("terminal read failed errno=\(errno)")
                cancelReader()
                return true
            }
        }
        return false
    }

    private func scheduleOutput() {
        guard !outputScheduled, !pendingOutput.isEmpty else { return }
        outputScheduled = true
        queue.asyncAfter(deadline: .now() + .milliseconds(16)) {
            let bytes = self.pendingOutput
            self.pendingOutput.removeAll(keepingCapacity: true)
            DispatchQueue.main.async {
                self.onOutput(bytes)
                self.queue.async {
                    // Begin the next interval only after delivery on the main queue;
                    // a busy UI cannot cause previously queued callbacks to bunch up.
                    self.outputScheduled = false
                    if self.childHasExited {
                        self.drainBeforeReaping()
                    } else if self.readerSuspended, let reader = self.reader {
                        self.readerSuspended = false
                        reader.resume()
                    }
                    self.scheduleOutput()
                    self.deliverExitIfReady()
                }
            }
        }
    }

    private func cancelReader() {
        if readerSuspended {
            readerSuspended = false
            reader?.resume()
        }
        reader?.cancel()
        reader = nil
    }

    private func writeAvailable() {
        guard !childHasExited else { return }
        var written = 0
        while inputOffset < pendingInput.count && written < 256 * 1024 {
            let count = pendingInput.withUnsafeBytes { bytes in
                Darwin.write(descriptor.fd, bytes.baseAddress!.advanced(by: inputOffset),
                             min(bytes.count - inputOffset, 256 * 1024 - written))
            }
            if count > 0 { inputOffset += count; written += count }
            else if count < 0 && errno == EINTR { continue }
            else if count < 0 && errno == EAGAIN { waitForWritable(); return }
            else {
                Log.error("terminal write failed errno=\(count == 0 ? EIO : errno)")
                pendingInput.removeAll()
                inputOffset = 0
                writer?.cancel()
                writer = nil
                return
            }
        }
        if inputOffset < pendingInput.count { waitForWritable(); return }
        pendingInput.removeAll(keepingCapacity: true)
        inputOffset = 0
        writer?.cancel()
        writer = nil
    }

    private func waitForWritable() {
        guard writer == nil else { return }
        let source = DispatchSource.makeWriteSource(fileDescriptor: descriptor.fd, queue: queue)
        descriptor.retainSource()
        source.setCancelHandler { [descriptor] in descriptor.releaseSource() }
        source.setEventHandler { [weak self] in self?.writeAvailable() }
        writer = source
        source.activate()
    }

    func childExited() {
        queue.async { self.handleChildExit() }
    }

    private func handleChildExit() {
        guard !childHasExited else { return }
        childHasExited = true
        cancelReader()
        writer?.cancel()
        writer = nil
        pendingInput.removeAll()
        inputOffset = 0
        drainBeforeReaping()
    }

    private func drainBeforeReaping() {
        guard exitStatus == nil else { return }
        // On macOS, waitpid can discard unread PTY bytes or wait for terminal
        // teardown while those bytes still need reading. Drain first, including
        // when the reader was suspended at the output high-water mark. Keep the
        // same memory bound and resume here after the main queue acknowledges a
        // batch; reaching a per-turn read limit is not the end of the stream.
        guard readAvailable() else { return }
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(pid, &status, 0) } while result < 0 && errno == EINTR
        if result < 0 {
            Log.error("terminal waitpid failed errno=\(errno)")
            exitStatus = 127
        } else {
            let signal = status & 0x7F
            exitStatus = signal == 0 ? (status >> 8) & 0xFF : 128 + signal
        }
        exitSource?.cancel()
        exitSource = nil
        descriptor.requestClose()
        Log.notice("terminal session exited status=\(exitStatus!)")
        deliverExitIfReady()
    }

    private func deliverExitIfReady() {
        guard let status = exitStatus, !exitDelivered, !outputScheduled, pendingOutput.isEmpty else { return }
        exitDelivered = true
        DispatchQueue.main.async { self.onExit(status) }
    }
}
