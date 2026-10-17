import Foundation
import os

enum Log {
    static let subsystem = "local.desktopshell.DesktopShell"
    private static let logger = Logger(subsystem: subsystem, category: "app")
    private static let stderrLock = NSLock()

    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        writeStderr(message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        writeStderr(message)
    }

    static func stderrLine(_ message: String, date: Date, processName: String, pid: Int32) -> String {
        // A call-local formatter avoids sharing mutable state across background queues.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return "\(formatter.string(from: date)) \(processName)[\(pid)] \(message)\n"
    }

    private static func writeStderr(_ message: String) {
        let process = ProcessInfo.processInfo
        let line = stderrLine(message, date: Date(), processName: process.processName,
                              pid: process.processIdentifier)
        // Serialize whole writes so concurrent messages do not interleave on stderr.
        stderrLock.lock()
        defer { stderrLock.unlock() }
        FileHandle.standardError.write(Data(line.utf8))
    }
}
