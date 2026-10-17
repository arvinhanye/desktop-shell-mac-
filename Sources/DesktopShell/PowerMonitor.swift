import AppKit
import IOKit.ps

@MainActor
final class PowerMonitor: NSObject {
    private let backgroundPlayer: BackgroundPlayer
    private let workspaceCenter = NSWorkspace.shared.notificationCenter
    private var windows: [DesktopWindow] = []
    private var batterySource: CFRunLoopSource?
    private var state = PowerState()
    private var isRunning = false
    private var hasAppliedState = false
    private(set) var reasons = Set<PauseReason>()

    var manualPause: Bool { state.manualPause }

    init(backgroundPlayer: BackgroundPlayer) {
        self.backgroundPlayer = backgroundPlayer
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        workspaceCenter.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(screensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(sessionDidResignActive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(sessionDidBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        // The C callback is delivered only by the main run loop. The source does
        // not retain this context; stop/deinit invalidate it before self goes away.
        batterySource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().refreshBattery()
            }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let batterySource {
            CFRunLoopAddSource(CFRunLoopGetMain(), batterySource, .commonModes)
        } else {
            NSLog("DesktopShell power: failed to register battery notifications")
        }

        state.battery = SystemStats.readBattery()
        updateWindows(windows)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        workspaceCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let batterySource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .commonModes)
            CFRunLoopSourceInvalidate(batterySource)
        }
        batterySource = nil
        windows.removeAll()
        hasAppliedState = false
    }

    deinit {
        // Also protect the unretained C callback if an owner forgets to stop.
        if let batterySource { CFRunLoopSourceInvalidate(batterySource) }
        workspaceCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func updateWindows(_ windows: [DesktopWindow]) {
        self.windows = windows
        guard isRunning else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        for window in windows {
            NotificationCenter.default.addObserver(
                self, selector: #selector(occlusionDidChange),
                name: NSWindow.didChangeOcclusionStateNotification, object: window
            )
        }
        updateOcclusion()
    }

    func setManualPause(_ paused: Bool) {
        state.manualPause = paused
        applyPolicy()
    }

    @objc private func occlusionDidChange() { updateOcclusion() }

    private func updateOcclusion() {
        // With no desktop windows there is no visible video to decode either.
        state.allWindowsOccluded = windows.allSatisfy { !$0.occlusionState.contains(.visible) }
        applyPolicy()
    }

    @objc private func screensDidSleep() {
        state.screensAsleep = true
        applyPolicy()
    }

    @objc private func screensDidWake() {
        state.screensAsleep = false
        updateOcclusion()
    }

    @objc private func sessionDidResignActive() {
        state.sessionInactive = true
        applyPolicy()
    }

    @objc private func sessionDidBecomeActive() {
        state.sessionInactive = false
        updateOcclusion()
    }

    private func refreshBattery() {
        guard isRunning else { return }
        state.battery = SystemStats.readBattery()
        applyPolicy()
    }

    private func applyPolicy() {
        guard isRunning else { return }
        let next = pauseReasons(for: state)
        guard !hasAppliedState || next != reasons else { return }
        let paused = !next.isEmpty
        if !hasAppliedState || paused != !reasons.isEmpty {
            if paused { backgroundPlayer.pause() } else { backgroundPlayer.play() }
        }
        reasons = next
        hasAppliedState = true
        let description = "[" + next.map(\.rawValue).sorted().joined(separator: ", ") + "]"
        NSLog("DesktopShell power: paused=%@ reasons=%@", paused ? "true" : "false", description)
    }
}
