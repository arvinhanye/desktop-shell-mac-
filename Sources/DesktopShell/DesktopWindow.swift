import AppKit

@MainActor
final class VideoWindow: NSWindow {
    init(screen: NSScreen, backgroundPlayer: BackgroundPlayer) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        setDesktopIconsHidden(false)
        hasShadow = false
        isReleasedWhenClosed = false
        backgroundColor = .black
        isOpaque = true
        contentView = backgroundPlayer.makeVideoView()
        setFrame(screen.frame, display: true)
    }

    func setDesktopIconsHidden(_ hidden: Bool) {
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + (hidden ? 1 : -1))
        ignoresMouseEvents = !hidden
    }
}

@MainActor
final class WidgetWindow: NSWindow {
    private let webContainer: WebContainer
    private(set) var safeAreaInsets = SafeAreaInsets(top: 0, right: 0, bottom: 0, left: 0)
    private(set) var hitRegions: [CGRect] = []
    var onHitRegionsChanged: (() -> Void)?

    init(screen: NSScreen, paths: AppPaths) {
        webContainer = WebContainer(paths: paths)
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false

        contentView = webContainer.webView

        update(screen: screen)
        webContainer.bind(to: self)
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

    override func close() {
        onHitRegionsChanged = nil
        webContainer.stop()
        super.close()
    }
}
