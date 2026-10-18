import WebKit

@MainActor
final class WebContainer: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private let bridge: Bridge

    init(appState: AppState) {
        bridge = Bridge(appState: appState)
        let paths = appState.paths
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            ShellSchemeHandler(resolver: SchemeResolver(webRoot: paths.webDir, mediaRoot: paths.mediaDir)),
            forURLScheme: "shell"
        )
        configuration.userContentController.addScriptMessageHandler(WeakScriptMessageHandler(bridge), contentWorld: .page, name: "shell")
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

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
        webView.load(URLRequest(url: URL(string: "shell://app/index.html")!))
    }

    func stop() {
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
