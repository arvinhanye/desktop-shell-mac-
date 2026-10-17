import AppKit

@MainActor
final class HitTestController {
    private var windows: [WidgetWindow] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isRunning = false
    var passThroughEnabled = true {
        didSet { updateMouseHandling() }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let events: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseUp, .rightMouseUp, .otherMouseUp
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.updateMouseHandling()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.updateMouseHandling()
            return event
        }
        updateMouseHandling()
    }

    func updateWindows(_ windows: [WidgetWindow]) {
        for window in self.windows { window.onHitRegionsChanged = nil }
        self.windows = windows
        for window in windows {
            window.onHitRegionsChanged = { [weak self] in self?.updateMouseHandling() }
        }
        updateMouseHandling()
    }

    func stop() {
        isRunning = false
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        for window in windows { window.onHitRegionsChanged = nil }
        windows.removeAll()
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func updateMouseHandling() {
        guard isRunning else { return }
        // Hidden desktop files must never receive clicks, including outside the widgets.
        if !passThroughEnabled {
            for window in windows where window.ignoresMouseEvents {
                window.ignoresMouseEvents = false
            }
            return
        }
        // Keep the owner of a drag until every button is released, even if regions change.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let mouse = NSEvent.mouseLocation
        for window in windows {
            let ignores = !HitTesting.isInteractive(mouse: mouse, windowFrame: window.frame, regions: window.hitRegions)
            if window.ignoresMouseEvents != ignores { window.ignoresMouseEvents = ignores }
        }
    }
}
