import Foundation
import Testing
@testable import DesktopShell

struct LogTests {
    private func sampleDate() throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 17, hour: 6, minute: 25, second: 20,
            nanosecond: 438_000_000
        )))
    }

    @Test("stderr日志使用本地时间、毫秒、进程名和pid，末尾仅加一个换行")
    func exactFormat() throws {
        let line = Log.stderrLine("DesktopShell power: paused=false reasons=[]",
                                  date: try sampleDate(), processName: "DesktopShell", pid: 40167)
        #expect(line == "2026-10-17 06:25:20.438 DesktopShell[40167] DesktopShell power: paused=false reasons=[]\n")
    }

    @Test("中文和百分号保持原文，不作为格式占位符", arguments: [
        "背景视频不存在：video/爱弥斯.mp4，请先运行 scripts/prepare-media.sh",
        "电量 20%，占位符 %@ %d %% 原样保留",
        ""
    ])
    func preservesMessage(_ message: String) throws {
        let line = Log.stderrLine(message, date: try sampleDate(), processName: "测试进程", pid: 7)
        #expect(line == "2026-10-17 06:25:20.438 测试进程[7] \(message)\n")
    }

    @Test("后台并发格式化互不串扰")
    func concurrentFormatting() async throws {
        let date = try sampleDate()
        await withTaskGroup(of: String.self) { group in
            for index in 0..<100 {
                group.addTask {
                    Log.stderrLine("消息 \(index)%", date: date, processName: "worker", pid: Int32(index))
                }
            }
            var lines: Set<String> = []
            for await line in group { lines.insert(line) }
            let expected = Set((0..<100).map {
                "2026-10-17 06:25:20.438 worker[\($0)] 消息 \($0)%\n"
            })
            #expect(lines == expected)
        }
    }
}
