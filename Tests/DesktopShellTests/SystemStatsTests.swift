import Foundation
import Testing
@testable import DesktopShell

struct SystemStatsTests {
    @Test("CPU 使用 user/system/nice 差值计算而非累计值")
    func cpuDeltas() {
        let before = CPUTicks(user: 100, system: 200, idle: 300, nice: 400)
        let after = CPUTicks(user: 120, system: 230, idle: 340, nice: 410)
        #expect(SystemStats.cpuUsage(from: before, to: after) == 60)
    }

    @Test("CPU 空闲、全忙和零差值边界")
    func cpuBoundaries() {
        let zero = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        #expect(SystemStats.cpuUsage(from: zero, to: CPUTicks(user: 0, system: 0, idle: 5, nice: 0)) == 0)
        #expect(SystemStats.cpuUsage(from: zero, to: CPUTicks(user: 5, system: 0, idle: 0, nice: 0)) == 100)
        #expect(SystemStats.cpuUsage(from: zero, to: zero) == nil)
    }

    @Test("CPU 计数器回绕保留真实差值")
    func cpuWrap() {
        let before = CPUTicks(user: UInt32.max - 10, system: UInt32.max, idle: 100, nice: 5)
        let after = CPUTicks(user: 5, system: 3, idle: 180, nice: 5)
        #expect(SystemStats.cpuUsage(from: before, to: after) == 20)
    }

    @Test("CPU 百分比保留一位小数；总差值不在 UInt32 中溢出")
    func cpuPrecisionAndWideSum() {
        let zero = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        #expect(SystemStats.cpuUsage(from: zero, to: CPUTicks(user: 1, system: 0, idle: 5, nice: 0)) == 16.7)
        #expect(SystemStats.cpuUsage(from: zero, to: CPUTicks(user: .max, system: .max, idle: .max, nice: .max)) == 75)
    }

    @Test("内存采用 internal 减 purgeable 加 wired 和 compressor 的口径")
    func memoryFormula() {
        #expect(SystemStats.memoryUsage(internalPages: 1000, purgeablePages: 100, wiredPages: 200,
                                        compressedPages: 100, pageSize: 4096, totalBytes: 8_192_000)
            == MemoryUsage(usedBytes: 4_915_200, totalBytes: 8_192_000, percent: 60))
    }

    @Test("purgeable 超过 internal 时只扣到零")
    func excessPurgeable() {
        #expect(SystemStats.memoryUsage(internalPages: 10, purgeablePages: 20, wiredPages: 3,
                                        compressedPages: 2, pageSize: 4096, totalBytes: 40_960)
            == MemoryUsage(usedBytes: 20_480, totalBytes: 40_960, percent: 50))
    }

    @Test("内存封顶、总量零和一位小数")
    func memoryBoundaries() {
        #expect(SystemStats.memoryUsage(internalPages: 100, purgeablePages: 0, wiredPages: 0,
                                        compressedPages: 0, pageSize: 4096, totalBytes: 1000)
            == MemoryUsage(usedBytes: 1000, totalBytes: 1000, percent: 100))
        #expect(SystemStats.memoryUsage(internalPages: 100, purgeablePages: 0, wiredPages: 20,
                                        compressedPages: 30, pageSize: 4096, totalBytes: 0)
            == MemoryUsage(usedBytes: 0, totalBytes: 0, percent: 0))
        #expect(SystemStats.memoryUsage(internalPages: 1, purgeablePages: 0, wiredPages: 0,
                                        compressedPages: 0, pageSize: 4096, totalBytes: 12288).percent == 33.3)
    }

    @Test("内存异常大计数饱和而非溢出；页大小零仍为零")
    func memoryOverflow() {
        for (pages, wired, compressed, size) in [(UInt64.max, UInt64.max, UInt64.max, UInt64(4096)), (.max, 0, 0, 4096)] {
            #expect(SystemStats.memoryUsage(internalPages: pages, purgeablePages: 0, wiredPages: wired,
                                            compressedPages: compressed, pageSize: size, totalBytes: 8192)
                == MemoryUsage(usedBytes: 8192, totalBytes: 8192, percent: 100))
        }
        #expect(SystemStats.memoryUsage(internalPages: .max, purgeablePages: 0, wiredPages: .max,
                                        compressedPages: .max, pageSize: 0, totalBytes: .max).usedBytes == 0)
    }

    @Test("systemStats 平铺事件名与完整数值，电量缺失为显式 null")
    func eventPayload() throws {
        let memory = MemoryUsage(usedBytes: 9_876_543_210, totalBytes: 17_179_869_184, percent: 57.5)
        for level: Int? in [85, nil] {
            let event = PageEvent.systemStats(battery: BatteryStatus(level: level, isCharging: false, onBattery: true), cpu: 12.3, memory: memory)
            #expect(Set(event.keys) == ["event", "battery", "cpu", "memory"])
            #expect(event["event"] as? String == "systemStats" && event["cpu"] as? Double == 12.3)
            let battery = try #require(event["battery"] as? [String: Any])
            #expect(Set(battery.keys) == ["level", "charging", "onBattery"])
            #expect(battery["charging"] as? Bool == false && battery["onBattery"] as? Bool == true)
            if let level { #expect(battery["level"] as? Int == level) }
            else { #expect(battery["level"] is NSNull) }
            let value = try #require(event["memory"] as? [String: Any])
            #expect(Set(value.keys) == ["usedBytes", "totalBytes", "percent"])
            #expect(value["usedBytes"] as? UInt64 == memory.usedBytes && value["totalBytes"] as? UInt64 == memory.totalBytes)
            #expect(value["percent"] as? Double == memory.percent)
            #expect(JSONSerialization.isValidJSONObject(event))
        }
    }

    @MainActor private final class Fixture {
        var ticks: CPUTicks? = CPUTicks(user: 10, system: 0, idle: 10, nice: 0)
        var memory: MemoryUsage? = MemoryUsage(usedBytes: 1000, totalBytes: 2000, percent: 50)
        var cpuReads = 0
        var actions: [@MainActor () -> Void] = []
        var intervals: [TimeInterval] = []
        var tolerances: [TimeInterval] = []
        var cancellations = 0
        var events: [[String: Any]] = []
        func makeMonitor() -> SystemStatsMonitor {
            let monitor = SystemStatsMonitor(
                readCPU: { self.cpuReads += 1; return self.ticks },
                readMemory: { self.memory },
                readBattery: { BatteryStatus(level: 19, isCharging: false, onBattery: true) },
                schedule: { interval, tolerance, action in
                    self.intervals.append(interval); self.tolerances.append(tolerance); self.actions.append(action)
                    return { self.cancellations += 1 }
                })
            monitor.onSample = { self.events.append($0) }
            return monitor
        }
        func advance() { ticks = CPUTicks(user: 20, system: 0, idle: 40, nice: 0) }
    }

    @MainActor @Test("启动只读基准，每五秒采样，容差一秒，重复启动不重复注册")
    func monitorSchedule() throws {
        let fixture = Fixture(); let monitor = fixture.makeMonitor()
        monitor.start(); monitor.start()
        #expect(fixture.cpuReads == 1 && fixture.events.isEmpty)
        #expect(fixture.intervals == [5] && fixture.tolerances == [1])
        try #require(fixture.actions.count == 1)
        fixture.advance(); fixture.actions[0]()
        try #require(fixture.events.count == 1)
        #expect(fixture.events[0]["cpu"] as? Double == 25)
        #expect((fixture.events[0]["battery"] as? [String: Any])?["level"] as? Int == 19)
        monitor.stop()
    }

    @MainActor @Test("CPU 读取失败跳过并重新建立基准，不沿用失败前旧时间窗口")
    func cpuReadFailure() throws {
        let fixture = Fixture(); let monitor = fixture.makeMonitor()
        monitor.start(); try #require(fixture.actions.count == 1)
        fixture.ticks = nil; fixture.actions[0]()
        #expect(fixture.events.isEmpty)
        fixture.advance(); fixture.actions[0]()
        #expect(fixture.events.isEmpty)
        fixture.ticks = CPUTicks(user: 30, system: 0, idle: 50, nice: 0); fixture.actions[0]()
        try #require(fixture.events.count == 1)
        #expect(fixture.events[0]["cpu"] as? Double == 50)
        monitor.stop()
    }

    @MainActor @Test("首次 CPU 基准读取失败、零差值均不伪造采样")
    func missingBaselineAndNoDelta() throws {
        let fixture = Fixture(); fixture.ticks = nil
        let monitor = fixture.makeMonitor(); monitor.start()
        try #require(fixture.actions.count == 1)
        fixture.advance(); fixture.actions[0](); fixture.actions[0]()
        #expect(fixture.events.isEmpty)
        fixture.ticks = CPUTicks(user: 30, system: 0, idle: 50, nice: 0); fixture.actions[0]()
        #expect(fixture.events.count == 1)
        monitor.stop()
    }

    @MainActor @Test("内存读取失败跳过整次推送，但 CPU 基准继续前进")
    func memoryReadFailure() throws {
        let fixture = Fixture(); let monitor = fixture.makeMonitor(); monitor.start()
        try #require(fixture.actions.count == 1)
        fixture.advance(); fixture.memory = nil; fixture.actions[0]()
        #expect(fixture.events.isEmpty)
        fixture.memory = MemoryUsage(usedBytes: 1000, totalBytes: 2000, percent: 50)
        fixture.ticks = CPUTicks(user: 30, system: 0, idle: 50, nice: 0); fixture.actions[0]()
        try #require(fixture.events.count == 1)
        #expect(fixture.events[0]["cpu"] as? Double == 50)
        monitor.stop()
    }

    @MainActor @Test("停止与释放取消定时器；停止后的旧任务不影响重新启动")
    func stopRestartAndRelease() throws {
        let fixture = Fixture(); var monitor: SystemStatsMonitor? = fixture.makeMonitor()
        monitor?.start(); monitor?.stop(); monitor?.stop()
        #expect(fixture.cancellations == 1)
        try #require(fixture.actions.count == 1)
        fixture.advance(); fixture.actions[0]()
        #expect(fixture.cpuReads == 1 && fixture.events.isEmpty)
        monitor?.start(); try #require(fixture.actions.count == 2)
        fixture.ticks = CPUTicks(user: 30, system: 0, idle: 50, nice: 0)
        fixture.actions[0](); #expect(fixture.events.isEmpty)
        fixture.actions[1](); #expect(fixture.events.count == 1)
        weak var weakMonitor = monitor; monitor = nil
        #expect(weakMonitor == nil && fixture.cancellations == 2)
        fixture.actions[1](); #expect(fixture.events.count == 1)
    }
}
