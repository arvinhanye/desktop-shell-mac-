import AppKit

@MainActor
final class ScreenManager: NSObject {
    private var windows: [CGDirectDisplayID: DesktopWindow] = [:]
    private var isObserving = false

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
                NSLog("DesktopShell: missing display ID for %@", screen.localizedName)
                continue
            }

            let displayID = screenNumber.uint32Value
            activeDisplayIDs.insert(displayID)
            let insets = SafeAreaInsets.compute(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame
            )

            if let window = windows[displayID] {
                window.update(screen: screen)
                window.updateSafeArea(insets)
            } else {
                let window = DesktopWindow(screen: screen)
                windows[displayID] = window
                window.updateSafeArea(insets)
                window.orderFront(nil)
            }
        }

        let removedDisplayIDs = Set(windows.keys).subtracting(activeDisplayIDs)
        for displayID in removedDisplayIDs {
            windows.removeValue(forKey: displayID)?.close()
        }
    }
}
