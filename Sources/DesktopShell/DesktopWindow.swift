import AppKit

@MainActor
final class DesktopWindow: NSWindow {
    private let screenLabel = NSTextField(labelWithString: "")
    private let safeAreaDebugView = SafeAreaDebugView(frame: .zero)

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

        safeAreaDebugView.frame = placeholder.bounds
        safeAreaDebugView.autoresizingMask = [.width, .height]
        placeholder.addSubview(safeAreaDebugView)

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

    func updateSafeArea(_ insets: SafeAreaInsets) {
        safeAreaDebugView.insets = insets
    }
}

@MainActor
private final class SafeAreaDebugView: NSView {
    var insets = SafeAreaInsets(top: 0, right: 0, bottom: 0, left: 0) {
        didSet { needsDisplay = true }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let safeRect = NSRect(
            x: bounds.minX + insets.left,
            y: bounds.minY + insets.bottom,
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom)
        )
        guard !safeRect.isEmpty else { return }

        NSColor.systemTeal.withAlphaComponent(0.15).setFill()
        NSBezierPath(rect: safeRect).fill()

        let lineWidth: CGFloat = 2
        if safeRect.width >= lineWidth && safeRect.height >= lineWidth {
            // Keep the full stroke inside the safe area rather than extending under the Dock.
            let outline = NSBezierPath(rect: safeRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            outline.lineWidth = lineWidth
            NSColor.systemTeal.withAlphaComponent(0.9).setStroke()
            outline.stroke()
        }

        let label = NSAttributedString(
            string: String(
                format: "top %g · right %g · bottom %g · left %g",
                Double(insets.top), Double(insets.right), Double(insets.bottom), Double(insets.left)
            ),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.white
            ]
        )
        let labelPadding: CGFloat = 12
        label.draw(at: NSPoint(
            x: safeRect.minX + labelPadding,
            y: safeRect.maxY - labelPadding - label.size().height
        ))
    }
}
