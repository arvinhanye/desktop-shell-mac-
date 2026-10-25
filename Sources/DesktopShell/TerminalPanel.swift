import AppKit
import WebKit
import QuartzCore

enum TerminalPanelGeometry {
    static func frame(visibleFrame: CGRect, maximized: Bool) -> CGRect {
        let height = maximized ? visibleFrame.height - 16 : floor(visibleFrame.height * 0.45)
        return CGRect(x: visibleFrame.minX + 16, y: visibleFrame.maxY - 8 - height,
                      width: visibleFrame.width - 32, height: height)
    }
}

struct TerminalPresentation {
    private(set) var visible = false
    private(set) var maximized = false
    private var revision = UUID()

    mutating func request(visible: Bool) -> UUID {
        self.visible = visible
        revision = UUID()
        return revision
    }

    mutating func toggleMaximize() -> Bool { maximized.toggle(); return maximized }
    func isCurrent(_ revision: UUID) -> Bool { self.revision == revision }
}

enum TerminalNavigationPolicy {
    static func allows(url: URL?, targetIsMainFrame: Bool?) -> Bool {
        targetIsMainFrame == true && url?.scheme == "shell" && url?.host == "app"
    }
}

@MainActor
final class TerminalPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // web/styles/tokens.css --radius-lg; the native backing uses the same corner.
    private static let cornerRadius: CGFloat = 2

    init(webView: WKWebView, frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hidesOnDeactivate = false
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .floating

        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let glass = NSVisualEffectView(frame: content.bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.autoresizingMask = [.width, .height]
        let radius = Self.cornerRadius
        let mask = NSImage(size: NSSize(width: 2 * radius + 1, height: 2 * radius + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        glass.maskImage = mask
        content.addSubview(glass)
        webView.frame = content.bounds
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView)
        contentView = content
    }
}

@MainActor
final class TerminalController: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let paths: AppPaths
    private let hotKey: HotKey
    private let session = TerminalSession()
    private var panel: TerminalPanel?
    private var webView: WKWebView?
    private var bridge: TerminalBridge?
    private var presentation = TerminalPresentation()
    private var displayID: NSNumber?
    private var screenObserver: NSObjectProtocol?
    private var pageGeneration = UUID()
    private var didLogSendFailure = false
    // web/styles/tokens.css --duration-terminal.
    private static let animationDuration = 0.16

    init(paths: AppPaths, hotKey: HotKey) {
        self.paths = paths
        self.hotKey = hotKey
        super.init()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenParametersChanged() }
            }
    }

    func toggle() { presentation.visible ? hide() : show() }

    func show() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let target = TerminalPanelGeometry.frame(visibleFrame: screen.visibleFrame, maximized: presentation.maximized)
        createPanelIfNeeded(frame: target)
        guard let panel, let webView else { return }
        let revision = presentation.request(visible: true)
        if !panel.isVisible {
            panel.setFrame(target.offsetBy(dx: 0, dy: 24), display: false)
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(webView)
        send(state())
        animate(to: target, alpha: 1, revision: revision)
    }

    func hide() {
        guard let panel else { return }
        let revision = presentation.request(visible: false)
        send(state())
        animate(to: panel.frame.offsetBy(dx: 0, dy: 24), alpha: 0, revision: revision)
    }

    private func animate(to frame: CGRect, alpha: CGFloat, revision: UUID) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = alpha
        } completionHandler: { [weak self, weak panel] in
            // AppKit animation completions run on the main thread; make that
            // isolation explicit because its imported closure is Sendable.
            MainActor.assumeIsolated {
                guard let self, let panel, self.presentation.isCurrent(revision) else { return }
                panel.setFrame(frame, display: true)
                panel.alphaValue = alpha
                if !self.presentation.visible {
                    panel.orderOut(nil)
                    if NSApp.isActive { NSApp.deactivate() }
                }
            }
        }
    }

    private func toggleMaximize() -> Bool {
        let maximized = presentation.toggleMaximize()
        reposition()
        return maximized
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == displayID }
            ?? panel?.screen ?? NSScreen.main
    }

    private func screenParametersChanged() {
        if presentation.visible { reposition() }
    }

    private func reposition() {
        guard let screen = currentScreen(), panel != nil else { return }
        displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let frame = TerminalPanelGeometry.frame(visibleFrame: screen.visibleFrame, maximized: presentation.maximized)
        let revision = presentation.request(visible: presentation.visible)
        animate(to: frame, alpha: presentation.visible ? 1 : 0, revision: revision)
    }

    private func state() -> [String: Any] {
        let shell = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh").lastPathComponent
        return PageEvent.terminalState(visible: presentation.visible, maximized: presentation.maximized,
                                      hotkey: hotKey.display, shell: shell)
    }

    private func createPanelIfNeeded(frame: CGRect) {
        guard panel == nil else { return }
        let bridge = TerminalBridge(session: session, send: { [weak self] event in self?.send(event) },
            state: { [weak self] in self?.state() ?? [:] },
            toggleMaximize: { [weak self] in self?.toggleMaximize() ?? false }, hide: { [weak self] in self?.hide() })
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            ShellSchemeHandler(resolver: SchemeResolver(webRoot: paths.webDir, mediaRoot: paths.mediaDir)), forURLScheme: "shell")
        configuration.userContentController.addScriptMessageHandler(WeakScriptMessageHandler(bridge), contentWorld: .page, name: "shell")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.isInspectable = ProcessInfo.processInfo.environment["DESKTOPSHELL_DEVTOOLS"] == "1"
        webView.navigationDelegate = self
        webView.uiDelegate = self
        bridge.webView = webView
        self.bridge = bridge
        self.webView = webView
        panel = TerminalPanel(webView: webView, frame: frame)
        reload()
    }

    func reload() {
        guard let webView else { return }
        beginPageLoad()
        webView.load(URLRequest(url: URL(string: "shell://app/terminal.html")!))
    }

    private func beginPageLoad() {
        bridge?.beginPageLoad()
        pageGeneration = UUID()
        didLogSendFailure = false
    }

    private func send(_ event: [String: Any]) {
        let generation = pageGeneration
        webView?.callAsyncJavaScript("window.shell?.receive?.(event)", arguments: ["event": event], in: nil, in: .page) { [weak self] result in
            if case .failure = result { self?.logDeliveryFailure(generation: generation) }
        }
    }

    private func logDeliveryFailure(generation: UUID) {
        guard generation == pageGeneration, !didLogSendFailure else { return }
        didLogSendFailure = true
        Log.error("terminal event rejected: failed")
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        _ = presentation.request(visible: false)
        beginPageLoad()
        session.onOutput = nil
        session.onExit = nil
        session.terminate()
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "shell", contentWorld: .page)
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        bridge?.webView = nil
        panel?.orderOut(nil)
        panel = nil
        webView = nil
        bridge = nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { beginPageLoad() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let generation = pageGeneration
        // Join the existing ES module initialization before delivering state.
        webView.callAsyncJavaScript("await import('/terminal/terminal.js')", in: nil, in: .page) { [weak self] result in
            guard let self, generation == self.pageGeneration else { return }
            switch result {
            case .success: self.send(self.state())
            case .failure: self.logDeliveryFailure(generation: generation)
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(TerminalNavigationPolicy.allows(url: navigationAction.request.url,
            targetIsMainFrame: navigationAction.targetFrame?.isMainFrame) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.error("terminal navigation rejected: failed")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.error("terminal navigation rejected: failed")
    }
}
