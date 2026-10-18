import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var screenManager: ScreenManager?
    private var backgroundPlayer: BackgroundPlayer?
    private var powerMonitor: PowerMonitor?
    private var hitTestController: HitTestController?
    private var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = AppPaths.current
        Log.notice("DesktopShell supportDir: \(paths.supportDir.path)")
        Log.notice("DesktopShell mediaDir: \(paths.mediaDir.path)")
        Log.notice("DesktopShell webDir: \(paths.webDir.path)")
        let appState = AppState(paths: paths)
        self.appState = appState
        let config = appState.config
        let videoURL = SchemeResolver(webRoot: paths.webDir, mediaRoot: paths.mediaDir)
            .fileURL(forPath: "/media/" + config.background.video)
        if videoURL == nil {
            Log.error("背景视频不存在：\(config.background.video)，请先运行 scripts/prepare-media.sh")
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
        let pauseItem = NSMenuItem(title: "暂停动画", action: #selector(togglePause(_:)), keyEquivalent: "")
        pauseItem.target = self
        pauseItem.state = .off
        menu.addItem(pauseItem)
        let hideIconsItem = NSMenuItem(title: "隐藏桌面文件", action: #selector(toggleDesktopIcons(_:)), keyEquivalent: "")
        hideIconsItem.target = self
        hideIconsItem.state = appState.uiState.desktopIconsHidden ? .on : .off
        menu.addItem(hideIconsItem)
        menu.addItem(.separator())
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

        let manager = ScreenManager(backgroundPlayer: player, appState: appState)
        screenManager = manager
        manager.setDesktopIconsHidden(appState.uiState.desktopIconsHidden)
        let monitor = PowerMonitor(backgroundPlayer: player)
        powerMonitor = monitor
        manager.onWindowsChanged = { [weak monitor] windows in
            monitor?.updateWindows(windows)
        }
        let hitTesting = HitTestController()
        hitTesting.passThroughEnabled = !appState.uiState.desktopIconsHidden
        hitTestController = hitTesting
        manager.onWidgetWindowsChanged = { [weak hitTesting] windows in
            hitTesting?.updateWindows(windows)
        }
        manager.start()
        monitor.start()
        hitTesting.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenManager?.onWindowsChanged = nil
        screenManager?.onWidgetWindowsChanged = nil
        hitTestController?.stop()
        hitTestController = nil
        powerMonitor?.stop()
        powerMonitor = nil
        screenManager?.stop()
        screenManager = nil
        backgroundPlayer?.pause()
        backgroundPlayer = nil

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        guard let powerMonitor else { return }
        powerMonitor.setManualPause(!powerMonitor.manualPause)
        sender.state = powerMonitor.manualPause ? .on : .off
    }

    @objc private func toggleDesktopIcons(_ sender: NSMenuItem) {
        guard let screenManager, let appState else { return }
        appState.uiState.desktopIconsHidden.toggle()
        hitTestController?.passThroughEnabled = !appState.uiState.desktopIconsHidden
        screenManager.setDesktopIconsHidden(appState.uiState.desktopIconsHidden)
        sender.state = appState.uiState.desktopIconsHidden ? .on : .off
        Log.notice("DesktopShell: desktop icons hidden=\(appState.uiState.desktopIconsHidden ? "true" : "false")")
        do {
            try appState.saveUiState()
        } catch {
            // A failed save affects the next launch, not the user's current choice.
            Log.error("DesktopShell: UI state save failed: \(String(describing: error))")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
