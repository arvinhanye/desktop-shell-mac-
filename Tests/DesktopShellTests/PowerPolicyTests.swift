import Testing
@testable import DesktopShell

struct PowerPolicyTests {
    @Test("没有暂停条件时继续播放")
    func noConditions() {
        #expect(pauseReasons(for: PowerState()).isEmpty)
    }

    @Test("五种原因都能单独触发", arguments: PauseReason.allCases)
    func individualReason(_ reason: PauseReason) {
        var state = PowerState()
        switch reason {
        case .occluded: state.allWindowsOccluded = true
        case .screensAsleep: state.screensAsleep = true
        case .sessionInactive: state.sessionInactive = true
        case .lowBattery: state.battery = BatteryStatus(level: 15, isCharging: false, onBattery: true)
        case .manual: state.manualPause = true
        }
        #expect(pauseReasons(for: state) == [reason])
    }

    @Test("低电量严格小于20且必须使用电池，未知电量不触发", arguments: [
        (0 as Int?, true, true), (19, true, true), (20, true, false), (100, true, false),
        (15, false, false), (nil, true, false), (nil, false, false)
    ])
    func batteryBoundary(_ level: Int?, _ onBattery: Bool, _ shouldPause: Bool) {
        var state = PowerState()
        state.battery = BatteryStatus(level: level, isCharging: false, onBattery: onBattery)
        #expect(pauseReasons(for: state) == (shouldPause ? [.lowBattery] : []))
    }

    @Test("多个原因同时保留，不被最后一个条件覆盖")
    func allReasons() {
        let state = PowerState(
            allWindowsOccluded: true, screensAsleep: true, sessionInactive: true,
            battery: BatteryStatus(level: 19, isCharging: false, onBattery: true), manualPause: true
        )
        #expect(pauseReasons(for: state) == [.occluded, .screensAsleep, .sessionInactive, .lowBattery, .manual])
    }

    @Test("解除一个条件后仍保留其余暂停原因，全部解除后恢复")
    func clearsReasonsIndependently() {
        var state = PowerState(screensAsleep: true, manualPause: true)
        #expect(pauseReasons(for: state) == [.screensAsleep, .manual])
        state.screensAsleep = false
        #expect(pauseReasons(for: state) == [.manual])
        state.manualPause = false
        #expect(pauseReasons(for: state).isEmpty)
    }
}
