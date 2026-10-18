import AppKit

@MainActor
final class ScreenManager: NSObject {
    @MainActor private struct WindowPair {
        let video: VideoWindow
        let widget: WidgetWindow

        func applyDesktopIconsHidden(_ hidden: Bool) {
            video.setDesktopIconsHidden(hidden)
            // The two windows share a level when icons are hidden; widgets must stay in front.
            video.orderFront(nil)
            widget.orderFront(nil)
        }

        func close() {
            widget.close()
            video.close()
        }
    }
    private var windows: [CGDirectDisplayID: WindowPair] = [:]
    private var eventCache = PageEventCache()
    private var isObserving = false
    private var desktopIconsHidden = false
    var onWindowsChanged: (([VideoWindow]) -> Void)?
    var onWidgetWindowsChanged: (([WidgetWindow]) -> Void)?
    private let backgroundPlayer: BackgroundPlayer
    private let appState: AppState

    init(backgroundPlayer: BackgroundPlayer, appState: AppState) {
        self.backgroundPlayer = backgroundPlayer
        self.appState = appState
        super.init()
    }

    func start() {
        guard !isObserving else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        isObserving = true
        synchronizeScreens()
    }

    func stop() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        isObserving = false

        for window in windows.values {
            window.close()
        }
        windows.removeAll()
        onWindowsChanged?([])
        onWidgetWindowsChanged?([])
    }

    func broadcast(_ event: [String: Any]) {
        eventCache.remember(event)
        for pair in windows.values { pair.widget.send(event) }
    }

    func reloadPages() {
        for pair in windows.values { pair.widget.reload() }
    }

    private func replayEvents(to widget: WidgetWindow) {
        for event in eventCache.replay(safeArea: widget.safeAreaInsets) {
            widget.send(event)
        }
    }

    func setDesktopIconsHidden(_ hidden: Bool) {
        desktopIconsHidden = hidden
        for pair in windows.values { pair.applyDesktopIconsHidden(hidden) }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        synchronizeScreens()
    }

    private func synchronizeScreens() {
        var activeDisplayIDs = Set<CGDirectDisplayID>()

        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                Log.error("DesktopShell: missing display ID for \(screen.localizedName)")
                continue
            }

            let displayID = screenNumber.uint32Value
            activeDisplayIDs.insert(displayID)
            let insets = SafeAreaInsets.compute(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame
            )

            if let pair = windows[displayID] {
                pair.video.setFrame(screen.frame, display: true)
                pair.widget.update(screen: screen)
                if pair.widget.safeAreaInsets != insets {
                    pair.widget.updateSafeArea(insets)
                    pair.widget.send(PageEvent.safeArea(insets))
                }
            } else {
                let video = VideoWindow(screen: screen, backgroundPlayer: backgroundPlayer)
                let widget = WidgetWindow(screen: screen, appState: appState)
                let pair = WindowPair(video: video, widget: widget)
                windows[displayID] = pair
                widget.updateSafeArea(insets)
                widget.onPageLoaded = { [weak self, weak widget] in
                    guard let widget else { return }
                    self?.replayEvents(to: widget)
                }
                pair.applyDesktopIconsHidden(desktopIconsHidden)
            }
        }

        let removedDisplayIDs = Set(windows.keys).subtracting(activeDisplayIDs)
        for displayID in removedDisplayIDs {
            windows.removeValue(forKey: displayID)?.close()
        }
        onWindowsChanged?(windows.values.map(\.video))
        onWidgetWindowsChanged?(windows.values.map(\.widget))
    }
}

// Cache policy is independent of AppKit so ordering and per-screen replay can be tested.
struct PageEventCache {
    private static let replayOrder = ["paused", "uiState", "systemStats", "todos"]
    private var latest: [String: [String: Any]] = [:]

    mutating func remember(_ event: [String: Any]) {
        guard let name = event["event"] as? String, Self.replayOrder.contains(name) else { return }
        latest[name] = event
    }

    func replay(safeArea: SafeAreaInsets) -> [[String: Any]] {
        [PageEvent.safeArea(safeArea)] + Self.replayOrder.compactMap { latest[$0] }
    }
}
