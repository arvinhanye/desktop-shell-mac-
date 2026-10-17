import WebKit

@MainActor
final class Bridge: NSObject, WKScriptMessageHandler {
    weak var window: WidgetWindow?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else {
            Log.error("DesktopShell bridge: 忽略格式错误的消息")
            return
        }
        guard action == "setHitRegions" else {
            Log.notice("DesktopShell bridge: 忽略未知 action \(action)")
            return
        }
        guard let window, let webView = message.webView else { return }
        guard let regions = HitTesting.parseRegions(body["regions"], viewport: webView.bounds.size) else {
            Log.error("DesktopShell bridge: 忽略格式错误的 setHitRegions")
            return
        }
        window.setHitRegions(regions)
    }
}

// WKUserContentController retains this proxy, not the window's bridge.
@MainActor
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
