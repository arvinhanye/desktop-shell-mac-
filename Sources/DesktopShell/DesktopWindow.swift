import AppKit

@MainActor
final class DesktopWindow: NSWindow {
    private let webContainer: WebContainer
    private(set) var safeAreaInsets = SafeAreaInsets(top: 0, right: 0, bottom: 0, left: 0)

    init(screen: NSScreen, backgroundPlayer: BackgroundPlayer, paths: AppPaths) {
        webContainer = WebContainer(paths: paths)
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        hasShadow = false
        isReleasedWhenClosed = false
        backgroundColor = .black
        isOpaque = true

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        contentView = content
        let videoView = backgroundPlayer.makeVideoView()
        videoView.frame = content.bounds
        content.addSubview(videoView)
        webContainer.webView.frame = content.bounds
        content.addSubview(webContainer.webView)

        update(screen: screen)
    }

    func update(screen: NSScreen) {
        // Use global coordinates so displays left of or below the primary screen keep their origin.
        setFrame(screen.frame, display: true)
    }

    func updateSafeArea(_ insets: SafeAreaInsets) {
        safeAreaInsets = insets
    }

    override func close() {
        webContainer.webView.stopLoading()
        super.close()
    }
}
