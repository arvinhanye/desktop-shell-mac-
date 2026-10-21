import WebKit

@MainActor
final class WebContainer: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: FileDropWebView
    private let bridge: Bridge
    var onPageLoaded: (() -> Void)?
    private var pageGeneration = UUID()
    private var didLogSendFailure = false

    init(appState: AppState) {
        bridge = Bridge(appState: appState)
        let paths = appState.paths
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            ShellSchemeHandler(resolver: SchemeResolver(webRoot: paths.webDir, mediaRoot: paths.mediaDir)),
            forURLScheme: "shell"
        )
        configuration.userContentController.addScriptMessageHandler(WeakScriptMessageHandler(bridge), contentWorld: .page, name: "shell")
        webView = FileDropWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.addProject = { [appState] path in appState.addProject(path: path) }
        webView.sendDrop = { [weak self] event in self?.send(event) }
        webView.registerForDraggedTypes([.fileURL])

        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.isInspectable = ProcessInfo.processInfo.environment["DESKTOPSHELL_DEVTOOLS"] == "1"
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = [.width, .height]
    }

    func bind(to window: WidgetWindow) {
        bridge.window = window
        webView.dropWindow = window
        reload()
    }

    func send(_ event: [String: Any]) {
        let generation = pageGeneration
        webView.callAsyncJavaScript("window.shell?.receive?.(event)", arguments: ["event": event],
                                    in: nil, in: .page) { [weak self] result in
            if case .failure = result { self?.logSendFailure(for: generation) }
        }
    }

    func refreshDropHover() { webView.refreshDropHover() }
    func cancelFileDrop() { webView.cancelFileDrop() }

    func reload() {
        bridge.window?.setDropRegions([])
        webView.cancelFileDrop()
        resetDeliveryLog()
        webView.load(URLRequest(url: URL(string: "shell://app/index.html")!))
    }

    private func resetDeliveryLog() {
        pageGeneration = UUID()
        didLogSendFailure = false
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        bridge.window?.setGlassRegions([])
        bridge.window?.setDropRegions([])
        resetDeliveryLog()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let generation = pageGeneration
        // With the custom scheme, didFinish can precede ES-module evaluation.
        // Importing the existing entry joins its initialization (including top-level
        // await) without executing it twice, polling, or adding a Bridge action.
        webView.callAsyncJavaScript("await import('/js/main.js')", in: nil, in: .page) { [weak self] result in
            guard let self, self.pageGeneration == generation else { return }
            switch result {
            case .success: self.onPageLoaded?()
            case .failure: self.logSendFailure(for: generation)
            }
        }
    }

    private func logSendFailure(for generation: UUID) {
        guard pageGeneration == generation, !didLogSendFailure else { return }
        didLogSendFailure = true
        // Do not log JS errors or payloads: either may include user content.
        Log.error("DesktopShell: page event delivery failed")
    }

    func stop() {
        webView.cancelFileDrop()
        webView.dropWindow = nil
        webView.addProject = nil
        webView.sendDrop = nil
        onPageLoaded = nil
        resetDeliveryLog()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "shell", contentWorld: .page)
        bridge.window = nil
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let source = navigationAction.sourceFrame.securityOrigin
        guard WebNavigationPolicy.allows(url: navigationAction.request.url,
            targetIsMainFrame: navigationAction.targetFrame?.isMainFrame,
            sourceScheme: source.protocol, sourceHost: source.host) else {
            Log.notice("DesktopShell: cancelled navigation to \(navigationAction.request.url?.absoluteString ?? "<missing URL>")")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.error("DesktopShell: page load failed: \(String(describing: error))")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.error("DesktopShell: navigation failed: \(String(describing: error))")
    }
}

// Never pass external drags to WebKit: it would otherwise navigate to the file
// or deliver its path to page JavaScript. Only public project summaries leave here.
@MainActor
final class FileDropWebView: WKWebView {
    weak var dropWindow: WidgetWindow?
    var addProject: ((String) -> Result<AppConfig.Project, BridgeError>)?
    var sendDrop: (([String: Any]) -> Void)?
    private var isOver = false

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard let window = dropWindow, sender.draggingDestinationWindow === window,
              addProject != nil,
              sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return false }
        return FileDropTracking.isInDropRegion(mouse: window.convertPoint(toScreen: sender.draggingLocation),
            windowFrame: window.frame, regions: window.dropRegions)
    }

    private func updateHover(_ sender: NSDraggingInfo) -> NSDragOperation {
        let over = accepts(sender)
        if over != isOver {
            isOver = over
            sendDrop?(PageEvent.projectDrop(over: over))
        }
        return over ? .copy : []
    }

    func cancelFileDrop() {
        guard isOver else { return }
        isOver = false
        sendDrop?(PageEvent.projectDrop(over: false))
    }

    func refreshDropHover() {
        guard let window = dropWindow,
              FileDropTracking.isInDropRegion(mouse: NSEvent.mouseLocation, windowFrame: window.frame, regions: window.dropRegions) else {
            cancelFileDrop()
            return
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateHover(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateHover(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { cancelFileDrop() }
    override func draggingEnded(_ sender: NSDraggingInfo) { cancelFileDrop() }
    override func wantsPeriodicDraggingUpdates() -> Bool { false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { updateHover(sender) == .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard accepts(sender), let addProject,
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else {
            cancelFileDrop()
            return false
        }
        let results = urls.map { addProject($0.path) }
        let outcome = FileDropTracking.dropOutcome(results: results)
        isOver = false
        sendDrop?(PageEvent.projectDrop(over: false, result: outcome))
        Log.notice("DesktopShell drop: folders=\(urls.count) added=\(outcome.added.count) rejected=\(urls.count - outcome.added.count)")
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) { cancelFileDrop() }
}
