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
            video.onMouseDown = nil
            widget.close()
            video.close()
        }

        func restoreWidgetOrder() {
            widget.order(.above, relativeTo: video.windowNumber)
        }
    }
    private var windows: [CGDirectDisplayID: WindowPair] = [:]
    private var isObserving = false
    private var desktopIconsHidden = false
    var onWindowsChanged: (([VideoWindow]) -> Void)?
    var onWidgetWindowsChanged: (([WidgetWindow]) -> Void)?
    private let backgroundPlayer: BackgroundPlayer
    private let paths: AppPaths

    init(backgroundPlayer: BackgroundPlayer, paths: AppPaths) {
        self.backgroundPlayer = backgroundPlayer
        self.paths = paths
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
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
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didBecomeActiveNotification,
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

    func setDesktopIconsHidden(_ hidden: Bool) {
        desktopIconsHidden = hidden
        for pair in windows.values { pair.applyDesktopIconsHidden(hidden) }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        synchronizeScreens()
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        guard desktopIconsHidden else { return }
        for pair in windows.values { pair.restoreWidgetOrder() }
    }

    private func restoreWidgetOrder(for displayID: CGDirectDisplayID) {
        guard desktopIconsHidden else { return }
        windows[displayID]?.restoreWidgetOrder()
    }

    private func synchronizeScreens() {
        var activeDisplayIDs = Set<CGDirectDisplayID>()

        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                NSLog("DesktopShell: missing display ID for %@", screen.localizedName)
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
                pair.widget.updateSafeArea(insets)
            } else {
                let video = VideoWindow(screen: screen, backgroundPlayer: backgroundPlayer)
                let widget = WidgetWindow(screen: screen, paths: paths)
                let pair = WindowPair(video: video, widget: widget)
                windows[displayID] = pair
                video.onMouseDown = { [weak self] in
                    self?.restoreWidgetOrder(for: displayID)
                }
                widget.updateSafeArea(insets)
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
