import AppKit

@MainActor
final class DesktopWindow: NSWindow {
    private let screenLabel = NSTextField(labelWithString: "")

    init(screen: NSScreen) {
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
        backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        isOpaque = true

        let placeholder = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        placeholder.wantsLayer = true
        placeholder.layer?.backgroundColor = backgroundColor.cgColor
        contentView = placeholder

        screenLabel.textColor = .white
        screenLabel.font = .systemFont(ofSize: 24)
        screenLabel.alignment = .center
        screenLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholder.addSubview(screenLabel)
        NSLayoutConstraint.activate([
            screenLabel.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            screenLabel.centerYAnchor.constraint(equalTo: placeholder.centerYAnchor)
        ])

        update(screen: screen)
    }

    func update(screen: NSScreen) {
        // Use global coordinates so displays left of or below the primary screen keep their origin.
        setFrame(screen.frame, display: true)
        screenLabel.stringValue = "\(screen.localizedName)  \(Int(screen.frame.width))×\(Int(screen.frame.height))"
    }
}
