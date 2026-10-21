import AppKit

@MainActor
final class HitTestController {
    private var windows: [WidgetWindow] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isRunning = false
    private var changeCountAtMouseDown: Int?
    var passThroughEnabled = true {
        didSet { updateMouseHandling() }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let events: NSEvent.EventTypeMask = [
            .leftMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseUp, .rightMouseUp, .otherMouseUp
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.handle(event)
            return event
        }
        updateMouseHandling()
    }

    func updateWindows(_ windows: [WidgetWindow]) {
        for window in self.windows {
            window.onHitRegionsChanged = nil
            window.onDropRegionsChanged = nil
        }
        self.windows = windows
        for window in windows {
            window.onHitRegionsChanged = { [weak self] in self?.updateMouseHandling() }
            window.onDropRegionsChanged = { [weak self] in self?.updateMouseHandling() }
        }
        updateMouseHandling()
    }

    func stop() {
        isRunning = false
        changeCountAtMouseDown = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        for window in windows {
            window.onHitRegionsChanged = nil
            window.onDropRegionsChanged = nil
            window.cancelFileDrop()
        }
        windows.removeAll()
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        } else if event.type == .leftMouseUp {
            changeCountAtMouseDown = nil
        }
        updateMouseHandling()
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
        let mouse = NSEvent.mouseLocation
        if NSEvent.pressedMouseButtons != 0 {
            let pasteboard = NSPasteboard(name: .drag)
            guard FileDropTracking.isFileDrag(changeCountAtMouseDown: changeCountAtMouseDown,
                currentChangeCount: pasteboard.changeCount,
                hasFileURLs: pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])) else {
                // Ordinary drags and Finder marquee selections keep their original owner.
                return
            }
            for window in windows {
                let inside = FileDropTracking.isInDropRegion(mouse: mouse, windowFrame: window.frame, regions: window.dropRegions)
                if window.ignoresMouseEvents == inside { window.ignoresMouseEvents = !inside }
                if !inside { window.cancelFileDrop() }
            }
            return
        }
        changeCountAtMouseDown = nil
        for window in windows {
            window.cancelFileDrop()
            let ignores = !HitTesting.isInteractive(mouse: mouse, windowFrame: window.frame, regions: window.hitRegions)
            if window.ignoresMouseEvents != ignores { window.ignoresMouseEvents = ignores }
        }
    }
}
