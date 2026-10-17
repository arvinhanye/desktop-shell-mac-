import Foundation
import IOKit.ps
import Testing
@testable import DesktopShell

struct BatteryParseTests {
    private func battery(current: Any = 50, maximum: Any = 100) -> [String: Any] {
        [kIOPSTypeKey: kIOPSInternalBatteryType,
         kIOPSCurrentCapacityKey: current, kIOPSMaxCapacityKey: maximum,
         kIOPSIsChargingKey: false, kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue]
    }

    @Test("内置电池放电50%")
    func discharging() {
        #expect(SystemStats.parseBattery([battery()]) == BatteryStatus(level: 50, isCharging: false, onBattery: true))
    }

    @Test("接电源充电中80%")
    func charging() {
        var source = battery(current: 80)
        source[kIOPSIsChargingKey] = true
        source[kIOPSPowerSourceStateKey] = kIOPSACPowerValue
        #expect(SystemStats.parseBattery([source]) == BatteryStatus(level: 80, isCharging: true, onBattery: false))
    }

    @Test("没有电源返回unknown")
    func noBattery() {
        #expect(SystemStats.parseBattery([]) == .unknown)
    }

    @Test("UPS和无类型的电源不当作内置电池")
    func ignoresOtherSources() {
        var ups = battery(current: 5)
        ups[kIOPSTypeKey] = kIOPSUPSType
        var untyped = battery(current: 5)
        untyped.removeValue(forKey: kIOPSTypeKey)
        #expect(SystemStats.parseBattery([ups, untyped]) == .unknown)
    }

    @Test("外部电源在前时仍选择内置电池")
    func selectsInternalBattery() {
        var ups = battery(current: 5)
        ups[kIOPSTypeKey] = kIOPSUPSType
        #expect(SystemStats.parseBattery([ups, battery(current: 80)]) == BatteryStatus(level: 80, isCharging: false, onBattery: true))
    }

    @Test("换算百分比并四舍五入，输出限制在0到100", arguments: [
        (4000.0, 5000.0, 80), (1, 3, 33), (2, 3, 67), (1, 8, 13),
        (0, 5000, 0), (5000, 5000, 100), (6000, 5000, 100),
        (Double(Int.max), Double(Int.max), 100)
    ])
    func convertsCapacity(_ current: Double, _ maximum: Double, _ expected: Int) {
        #expect(SystemStats.parseBattery([battery(current: current, maximum: maximum)]).level == expected)
    }

    @Test("缺少容量时保留供电状态但电量为nil")
    func missingCapacity() {
        var source = battery()
        source.removeValue(forKey: kIOPSCurrentCapacityKey)
        #expect(SystemStats.parseBattery([source]) == BatteryStatus(level: nil, isCharging: false, onBattery: true))
        source = battery()
        source.removeValue(forKey: kIOPSMaxCapacityKey)
        #expect(SystemStats.parseBattery([source]).level == nil)
    }

    @Test("异常容量不崩溃，也不伪装成低电量")
    func malformedCapacity() {
        for (current, maximum) in [
            (50, 0), (50, -100), (-1, 100), ("50", 100), (50, "100"),
            (true, 100), (50, true), (Double.nan, 100), (50, Double.nan),
            (Double.infinity, 100), (50, Double.infinity)
        ] as [(Any, Any)] {
            let result = SystemStats.parseBattery([battery(current: current, maximum: maximum)])
            #expect(result == BatteryStatus(level: nil, isCharging: false, onBattery: true))
        }
    }

    @Test("缺少供电或充电字段时不猜测正在使用电池")
    func missingFlags() {
        var source = battery()
        source.removeValue(forKey: kIOPSIsChargingKey)
        source.removeValue(forKey: kIOPSPowerSourceStateKey)
        #expect(SystemStats.parseBattery([source]) == BatteryStatus(level: 50, isCharging: false, onBattery: false))
    }

    @Test("读取IOKit字典的NSNumber桥接值")
    func bridgedNumbers() {
        var source = battery(current: NSNumber(value: 4000), maximum: NSNumber(value: 5000))
        source[kIOPSIsChargingKey] = NSNumber(value: true)
        source[kIOPSPowerSourceStateKey] = kIOPSACPowerValue
        #expect(SystemStats.parseBattery([source]) == BatteryStatus(level: 80, isCharging: true, onBattery: false))
    }
}
