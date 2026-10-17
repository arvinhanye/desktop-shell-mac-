import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var screenManager: ScreenManager?
    private var backgroundPlayer: BackgroundPlayer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = AppPaths.current
        NSLog("DesktopShell supportDir: %@", paths.supportDir.path)
        NSLog("DesktopShell mediaDir: %@", paths.mediaDir.path)
        NSLog("DesktopShell webDir: %@", paths.webDir.path)
        let config: AppConfig
        do {
            config = try ConfigStore(supportDir: paths.supportDir).load()
        } catch {
            NSLog("DesktopShell: configuration load failed, using in-memory example: %@", String(describing: error))
            config = .example
        }
        let videoURL = SchemeResolver(webRoot: paths.webDir, mediaRoot: paths.mediaDir)
            .fileURL(forPath: "/media/" + config.background.video)
        if videoURL == nil {
            NSLog("背景视频不存在：%@，请先运行 scripts/prepare-media.sh", config.background.video)
        }
        let player = BackgroundPlayer(videoURL: videoURL)
        backgroundPlayer = player

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

        let manager = ScreenManager(backgroundPlayer: player, paths: paths)
        screenManager = manager
        manager.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenManager?.stop()
        screenManager = nil
        backgroundPlayer?.pause()
        backgroundPlayer = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
