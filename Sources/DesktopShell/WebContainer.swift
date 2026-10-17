import WebKit

@MainActor
final class WebContainer: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView

    init(paths: AppPaths) {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            ShellSchemeHandler(resolver: SchemeResolver(webRoot: paths.webDir, mediaRoot: paths.mediaDir)),
            forURLScheme: "shell"
        )
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
        webView.load(URLRequest(url: URL(string: "shell://app/index.html")!))
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.request.url?.scheme == "shell" else {
            NSLog("DesktopShell: cancelled navigation to %@", navigationAction.request.url?.absoluteString ?? "<missing URL>")
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
        NSLog("DesktopShell: page load failed: %@", String(describing: error))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("DesktopShell: navigation failed: %@", String(describing: error))
    }
}
