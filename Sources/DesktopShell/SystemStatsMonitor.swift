import Foundation

@MainActor
final class SystemStatsMonitor {
    typealias Schedule = (_ interval: TimeInterval, _ tolerance: TimeInterval,
                          _ action: @escaping @MainActor () -> Void) -> () -> Void

    var onSample: (([String: Any]) -> Void)?
    private let readCPU: () -> CPUTicks?
    private let readMemory: () -> MemoryUsage?
    private let readBattery: () -> BatteryStatus
    private let schedule: Schedule
    private let debugLogging = ProcessInfo.processInfo.environment["DESKTOPSHELL_DEBUG_STATS"] == "1"
    private var previousCPU: CPUTicks?
    private var generation: UUID?
    private var cancelSampling: (() -> Void)?

    init(readCPU: @escaping () -> CPUTicks? = SystemStats.readCPUTicks,
         readMemory: @escaping () -> MemoryUsage? = SystemStats.readMemory,
         readBattery: @escaping () -> BatteryStatus = SystemStats.readBattery,
         schedule: @escaping Schedule = { interval, tolerance, action in
             let timer = Timer(timeInterval: interval, repeats: true) { _ in
                 MainActor.assumeIsolated { action() }
             }
             timer.tolerance = tolerance
             RunLoop.main.add(timer, forMode: .common)
             return { timer.invalidate() }
         }) {
        self.readCPU = readCPU
        self.readMemory = readMemory
        self.readBattery = readBattery
        self.schedule = schedule
    }

    func start() {
        guard generation == nil else { return }
        let id = UUID()
        generation = id
        previousCPU = readCPU()
        Log.notice("DesktopShell stats: sampling every 5s")
        cancelSampling = schedule(5, 1) { [weak self] in
            guard let self, self.generation == id else { return }
            self.sample()
        }
    }

    func stop() {
        generation = nil
        cancelSampling?()
        cancelSampling = nil
        previousCPU = nil
    }

    deinit { cancelSampling?() }

    private func sample() {
        let before = previousCPU
        let current = readCPU()
        // Failure discards the baseline: resume with two consecutive good reads.
        // A memory failure still advances CPU so the next value covers one interval.
        previousCPU = current
        let memory = readMemory()
        guard let before, let current, let cpu = SystemStats.cpuUsage(from: before, to: current),
              let memory else { return }
        let battery = readBattery()
        onSample?(PageEvent.systemStats(battery: battery, cpu: cpu, memory: memory))
        if debugLogging {
            let level = battery.level.map(String.init) ?? "nil"
            Log.notice("DesktopShell stats: cpu=\(cpu) memory=\(memory.percent)% battery=\(level) charging=\(battery.isCharging) onBattery=\(battery.onBattery)")
        }
    }
}
