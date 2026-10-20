import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var loginItem: NSMenuItem?
    private var screenManager: ScreenManager?
    private var backgroundPlayer: BackgroundPlayer?
    private var powerMonitor: PowerMonitor?
    private var audioSpectrum: AudioSpectrum?
    private var playbackMonitor: PlaybackMonitor?
    private var statsMonitor: SystemStatsMonitor?
    private var hitTestController: HitTestController?
    private var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = AppPaths.current
        Log.notice("DesktopShell supportDir: \(paths.supportDir.path)")
        Log.notice("DesktopShell mediaDir: \(paths.mediaDir.path)")
        Log.notice("DesktopShell webDir: \(paths.webDir.path)")
        let appState = AppState(paths: paths)
        self.appState = appState
        appState.exportAppIcons()
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
        menu.delegate = self
        let pauseItem = NSMenuItem(title: "暂停动画", action: #selector(togglePause(_:)), keyEquivalent: "")
        pauseItem.target = self
        pauseItem.state = .off
        menu.addItem(pauseItem)
        let hideIconsItem = NSMenuItem(title: "隐藏桌面文件", action: #selector(toggleDesktopIcons(_:)), keyEquivalent: "")
        hideIconsItem.target = self
        hideIconsItem.state = appState.uiState.desktopIconsHidden ? .on : .off
        menu.addItem(hideIconsItem)
        let voiceItem = NSMenuItem(title: "点击语音", action: #selector(toggleVoice(_:)), keyEquivalent: "")
        voiceItem.target = self
        voiceItem.state = appState.uiState.voiceEnabled ? .on : .off
        menu.addItem(voiceItem)
        let loginItem = NSMenuItem(title: "开机自启", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        let loginStatus = LoginItemService.status
        loginItem.state = LaunchAtLogin.menuState(loginStatus)
        Log.notice("DesktopShell login item: status=\(loginStatus.rawValue)")
        menu.addItem(loginItem)
        self.loginItem = loginItem
        menu.addItem(.separator())
        let reloadItem = NSMenuItem(title: "重新加载", action: #selector(reloadPages), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)
        let configFolderItem = NSMenuItem(title: "打开配置文件夹", action: #selector(openConfigFolder), keyEquivalent: "")
        configFolderItem.target = self
        menu.addItem(configFolderItem)
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
        let audio = AudioSpectrum()
        audioSpectrum = audio
        let playback = PlaybackMonitor()
        playbackMonitor = playback
        playback.onChange = { [weak audio] playing in audio?.setPlayback(playing) }
        audio.onSpectrum = { [weak manager] bands in
            manager?.broadcast(PageEvent.audioSpectrum(bands))
        }
        monitor.onPausedChanged = { [weak manager, weak audio] paused in
            audio?.setPaused(paused)
            manager?.broadcast(PageEvent.paused(paused))
        }
        appState.onUiStateChanged = { [weak manager] state in
            manager?.broadcast(PageEvent.uiState(state))
        }
        manager.broadcast(PageEvent.uiState(appState.uiState))
        manager.onWindowsChanged = { [weak monitor] windows in
            monitor?.updateWindows(windows)
        }
        let hitTesting = HitTestController()
        hitTesting.passThroughEnabled = !appState.uiState.desktopIconsHidden
        hitTestController = hitTesting
        manager.onWidgetWindowsChanged = { [weak hitTesting] windows in
            hitTesting?.updateWindows(windows)
        }
        let stats = SystemStatsMonitor()
        statsMonitor = stats
        stats.onSample = { [weak manager] event in manager?.broadcast(event) }
        manager.start()
        playback.start()
        monitor.start()
        stats.start()
        hitTesting.start()
        let reminders = RemindersStore(appState: appState)
        appState.remindersStore = reminders
        reminders.onChange = { [weak manager] event in manager?.broadcast(event) }
        reminders.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenManager?.onWindowsChanged = nil
        screenManager?.onWidgetWindowsChanged = nil
        hitTestController?.stop()
        hitTestController = nil
        appState?.onUiStateChanged = nil
        powerMonitor?.onPausedChanged = nil
        playbackMonitor?.onChange = nil
        playbackMonitor?.stop()
        playbackMonitor = nil
        audioSpectrum?.stop()
        audioSpectrum = nil
        appState?.remindersStore?.onChange = nil
        appState?.remindersStore?.stop()
        appState?.remindersStore = nil
        statsMonitor?.onSample = nil
        statsMonitor?.stop()
        statsMonitor = nil
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
        loginItem = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        loginItem?.state = LaunchAtLogin.menuState(LoginItemService.status)
    }

    @objc private func toggleLaunchAtLogin() {
        // Read again rather than act on a possibly stale menu checkmark.
        LoginItemService.perform(LaunchAtLogin.action(for: LoginItemService.status))
        refreshLoginItem()
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

    @objc private func toggleVoice(_ sender: NSMenuItem) {
        guard let appState else { return }
        appState.toggleVoice()
        sender.state = appState.uiState.voiceEnabled ? .on : .off
    }

    @objc private func reloadPages() {
        appState?.reloadConfig()
        appState?.exportAppIcons()
        screenManager?.reloadPages()
        Log.notice("DesktopShell: reloaded config and pages; background.video changes require an app restart")
    }

    @objc private func openConfigFolder() {
        guard let appState else { return }
        do {
            try FileManager.default.createDirectory(at: appState.paths.supportDir, withIntermediateDirectories: true)
            if !NSWorkspace.shared.open(appState.paths.supportDir) {
                Log.error("DesktopShell: configuration folder open failed")
            }
        } catch {
            Log.error("DesktopShell: configuration folder creation failed")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
