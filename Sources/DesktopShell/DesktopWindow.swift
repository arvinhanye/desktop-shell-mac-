import AppKit

@MainActor
final class VideoWindow: NSWindow {
    init(screen: NSScreen, backgroundPlayer: BackgroundPlayer) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        setDesktopIconsHidden(false)
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        backgroundColor = .black
        isOpaque = true
        contentView = backgroundPlayer.makeVideoView()
        setFrame(screen.frame, display: true)
    }

    func setDesktopIconsHidden(_ hidden: Bool) {
        level = NSWindow.Level(rawValue: WindowLevels.video(
            iconLevel: Int(CGWindowLevelForKey(.desktopIconWindow)),
            iconsHidden: hidden
        ))
    }
}

@MainActor
final class WidgetWindow: NSPanel {
    private let webContainer: WebContainer
    private let glassLayer = GlassLayer(frame: .zero)
    private var glassRegionCount = 0
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
    private(set) var safeAreaInsets = SafeAreaInsets(top: 0, right: 0, bottom: 0, left: 0)
    private(set) var hitRegions: [CGRect] = []
    private(set) var dropRegions: [CGRect] = []
    var onDropRegionsChanged: (() -> Void)?
    var onHitRegionsChanged: (() -> Void)?
    var onPageLoaded: (() -> Void)? {
        get { webContainer.onPageLoaded }
        set { webContainer.onPageLoaded = newValue }
    }

    func send(_ event: [String: Any]) { webContainer.send(event) }
    func reload() {
        // The old document may unload without sending blurInput.
        acceptsKeyboard = false
        if isKeyWindow { NSApp.deactivate() }
        webContainer.reload()
    }

    init(screen: NSScreen, appState: AppState) {
        webContainer = WebContainer(appState: appState)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        Self.configure(self, iconLevel: Int(CGWindowLevelForKey(.desktopIconWindow)))

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        glassLayer.frame = container.bounds
        glassLayer.autoresizingMask = [.width, .height]
        webContainer.webView.frame = container.bounds
        container.addSubview(glassLayer)
        container.addSubview(webContainer.webView)
        contentView = container

        update(screen: screen)
        webContainer.bind(to: self)
    }

    static func configure(_ panel: NSPanel, iconLevel: Int) {
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // isFloatingPanel's setter resets the level, so assign the desktop level last.
        panel.level = NSWindow.Level(rawValue: WindowLevels.widget(iconLevel: iconLevel))
    }

    func update(screen: NSScreen) {
        // Use global coordinates so displays left of or below the primary screen keep their origin.
        setFrame(screen.frame, display: true)
    }

    func updateSafeArea(_ insets: SafeAreaInsets) {
        safeAreaInsets = insets
    }

    func setHitRegions(_ regions: [CGRect]) {
        hitRegions = regions
        onHitRegionsChanged?()
    }

    func setDropRegions(_ regions: [CGRect]) {
        dropRegions = regions
        webContainer.refreshDropHover()
        onDropRegionsChanged?()
    }

    func cancelFileDrop() { webContainer.cancelFileDrop() }

    func setGlassRegions(_ regions: [GlassRegion]) {
        glassLayer.update(regions)
        if glassRegionCount != regions.count {
            glassRegionCount = regions.count
            Log.notice("DesktopShell bridge: setGlassRegions regions=\(regions.count)")
        }
    }

    override func resignKey() {
        super.resignKey()
        // AppKit may return keyboard ownership before the page sends blurInput.
        acceptsKeyboard = false
    }

    override func close() {
        onHitRegionsChanged = nil
        onDropRegionsChanged = nil
        setDropRegions([])
        setGlassRegions([])
        webContainer.stop()
        super.close()
    }
}
