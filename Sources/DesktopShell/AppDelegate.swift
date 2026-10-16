import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var screenManager: ScreenManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: "DesktopShell"
        )
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "退出 DesktopShell",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item

        let manager = ScreenManager()
        screenManager = manager
        manager.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenManager?.stop()
        screenManager = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
