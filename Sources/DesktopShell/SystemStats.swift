import Foundation
import Darwin
import IOKit.ps

struct BatteryStatus: Equatable {
    var level: Int?
    var isCharging: Bool
    var onBattery: Bool
    static let unknown = BatteryStatus(level: nil, isCharging: false, onBattery: false)
}

enum SystemStats {
    static func parseBattery(_ sources: [[String: Any]]) -> BatteryStatus {
        guard let source = sources.first(where: { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }) else {
            return .unknown
        }

        // Missing or invalid capacities are unknown, not an empty battery.
        // CFBoolean is also an NSNumber, but is not a capacity measurement.
        func capacity(_ key: String) -> Double? {
            guard let number = source[key] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let value = number.doubleValue
            return value.isFinite && value >= 0 ? value : nil
        }
        var level: Int?
        if let current = capacity(kIOPSCurrentCapacityKey),
           let maximum = capacity(kIOPSMaxCapacityKey), maximum > 0 {
            // Clamp before converting to Int, also avoiding multiplication overflow.
            level = Int((min(current / maximum, 1) * 100).rounded())
        }
        return BatteryStatus(
            level: level,
            isCharging: source[kIOPSIsChargingKey] as? Bool ?? false,
            onBattery: source[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
        )
    }

    static func readBattery() -> BatteryStatus {
        if let override = ProcessInfo.processInfo.environment["DESKTOPSHELL_FAKE_BATTERY"] {
            if let level = Int(override), (0...100).contains(level) {
                return BatteryStatus(level: level, isCharging: false, onBattery: true)
            }
            Log.error("DesktopShell: invalid DESKTOPSHELL_FAKE_BATTERY; reading actual battery status")
        }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unknown
        }
        let descriptions = sources.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return parseBattery(descriptions)
    }
}

struct CPUTicks: Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

struct MemoryUsage: Equatable {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var percent: Double
}

extension SystemStats {
    static func cpuUsage(from: CPUTicks, to: CPUTicks) -> Double? {
        // Subtract in the counter's width, then widen before summing four deltas.
        let user = UInt64(to.user &- from.user)
        let system = UInt64(to.system &- from.system)
        let idle = UInt64(to.idle &- from.idle)
        let nice = UInt64(to.nice &- from.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return (Double(user + system + nice) / Double(total) * 1000).rounded() / 10
    }

    static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            logReadFailure("cpu", code: result)
            return nil
        }
        // HOST_CPU_LOAD_INFO order is USER, SYSTEM, IDLE, NICE.
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                        idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    static func memoryUsage(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64,
                            compressedPages: UInt64, pageSize: UInt64, totalBytes: UInt64) -> MemoryUsage {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        // Saturate before the final physical-memory cap, including unusual inputs.
        let pages = [wiredPages, compressedPages].reduce(appPages) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            return overflow ? UInt64.max : sum
        }
        let (bytes, overflow) = pages.multipliedReportingOverflow(by: pageSize)
        let used = min(overflow ? UInt64.max : bytes, totalBytes)
        let percent = totalBytes == 0 ? 0 : (Double(used) / Double(totalBytes) * 1000).rounded() / 10
        return MemoryUsage(usedBytes: used, totalBytes: totalBytes, percent: percent)
    }

    static func readMemory() -> MemoryUsage? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            logReadFailure("memory", code: result)
            return nil
        }
        return memoryUsage(internalPages: UInt64(info.internal_page_count),
                           purgeablePages: UInt64(info.purgeable_count),
                           wiredPages: UInt64(info.wire_count),
                           compressedPages: UInt64(info.compressor_page_count),
                           pageSize: UInt64(vm_kernel_page_size),
                           totalBytes: ProcessInfo.processInfo.physicalMemory)
    }

    private static let readFailureLock = NSLock()
    private static var loggedReadFailures = Set<String>()

    private static func logReadFailure(_ source: String, code: kern_return_t) {
        readFailureLock.lock()
        let first = loggedReadFailures.insert("\(source):\(code)").inserted
        readFailureLock.unlock()
        if first { Log.error("DesktopShell stats: \(source) read failed code=\(code)") }
    }
}
