struct PowerState: Equatable {
    var allWindowsOccluded = false
    var screensAsleep = false
    var sessionInactive = false
    var battery = BatteryStatus.unknown
    var manualPause = false
}

enum PauseReason: String, CaseIterable {
    case occluded, screensAsleep, sessionInactive, lowBattery, manual
}

func pauseReasons(for state: PowerState) -> Set<PauseReason> {
    var reasons = Set<PauseReason>()
    if state.allWindowsOccluded { reasons.insert(.occluded) }
    if state.screensAsleep { reasons.insert(.screensAsleep) }
    if state.sessionInactive { reasons.insert(.sessionInactive) }
    if state.battery.onBattery, let level = state.battery.level, level < 20 {
        reasons.insert(.lowBattery)
    }
    if state.manualPause { reasons.insert(.manual) }
    return reasons
}
