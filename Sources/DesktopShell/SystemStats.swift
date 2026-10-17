import Foundation
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
            NSLog("DesktopShell: invalid DESKTOPSHELL_FAKE_BATTERY; reading actual battery status")
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
