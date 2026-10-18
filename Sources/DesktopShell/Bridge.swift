import WebKit

@MainActor
final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var window: WidgetWindow?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        let origin = message.frameInfo.securityOrigin
        guard BridgeOrigin.isTrusted(isMainFrame: message.frameInfo.isMainFrame, scheme: origin.protocol, host: origin.host) else {
            // Do not inspect an untrusted frame's body, even for logging.
            reject(.untrusted, action: "?", replyHandler: replyHandler)
            return
        }
        let candidate = (message.body as? [String: Any])?["action"] as? String
        let action = candidate.flatMap { isValidID($0) && $0.count <= 64 ? $0 : nil } ?? "?"
        switch BridgeRequest.parse(message.body) {
        case .failure(let error):
            reject(error, action: action, replyHandler: replyHandler)
        case .success(.getConfig):
            let avatars = MediaLibrary.scan(mediaDir: appState.paths.mediaDir, subdirectory: "avatars")
            let backgrounds = MediaLibrary.scan(mediaDir: appState.paths.mediaDir, subdirectory: "backgrounds")
            Log.notice("DesktopShell bridge: getConfig avatars=\(avatars.count) backgrounds=\(backgrounds.count)")
            replyHandler(ConfigReply.make(config: appState.config, avatars: avatars,
                backgrounds: backgrounds, uiState: appState.uiState), nil)
        case .success(.setHitRegions(let values)):
            guard let window, let webView = message.webView else {
                reject(.failed, action: action, replyHandler: replyHandler)
                return
            }
            guard let regions = HitTesting.parseRegions(values, viewport: webView.bounds.size) else {
                reject(.invalid, action: action, replyHandler: replyHandler)
                return
            }
            window.setHitRegions(regions)
            replyHandler(nil, nil)
        }
    }

    private func reject(_ error: BridgeError, action: String, replyHandler: @MainActor @Sendable (Any?, String?) -> Void) {
        Log.error("DesktopShell bridge: \(action) rejected: \(error.rawValue)")
        replyHandler(nil, error.rawValue)
    }
}

// WKUserContentController retains this proxy, not the window's bridge.
@MainActor
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    private weak var target: WKScriptMessageHandlerWithReply?

    init(_ target: WKScriptMessageHandlerWithReply) { self.target = target }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let target else {
            Log.error("DesktopShell bridge: ? rejected: failed")
            replyHandler(nil, BridgeError.failed.rawValue)
            return
        }
        target.userContentController(userContentController, didReceive: message, replyHandler: replyHandler)
    }
}
