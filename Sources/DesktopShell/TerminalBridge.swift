import WebKit
import CoreFoundation

enum TerminalRequest: Equatable {
    case ready(TerminalSize), input(String), resize(TerminalSize), toggleMaximize, hide

    static let actions: Set<String> = ["terminalReady", "terminalInput", "terminalResize", "toggleTerminalMaximize", "hideTerminal"]

    static func parse(_ body: Any) -> Result<TerminalRequest, BridgeError> {
        guard let body = body as? [String: Any], let action = body["action"] as? String else { return .failure(.invalid) }
        guard actions.contains(action) else { return .failure(.untrusted) }
        switch action {
        case "terminalReady", "terminalResize":
            guard Set(body.keys) == ["action", "cols", "rows"],
                  let cols = number(body["cols"]), let rows = number(body["rows"]),
                  let size = TerminalSize.validated(cols: cols, rows: rows) else { return .failure(.invalid) }
            return .success(action == "terminalReady" ? .ready(size) : .resize(size))
        case "terminalInput":
            // Match terminal.js's UTF-16 chunk limit, including surrogate pairs.
            guard Set(body.keys) == ["action", "data"], let data = body["data"] as? String,
                  !data.isEmpty, data.utf16.count <= 65536 else { return .failure(.invalid) }
            return .success(.input(data))
        default:
            guard Set(body.keys) == ["action"] else { return .failure(.invalid) }
            return .success(action == "hideTerminal" ? .hide : .toggleMaximize)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
    }
}

enum TerminalBridgeOrigin {
    static func isTrusted(isTerminalWebView: Bool, isMainFrame: Bool, scheme: String, host: String) -> Bool {
        isTerminalWebView && BridgeOrigin.isTrusted(isMainFrame: isMainFrame, scheme: scheme, host: host)
    }
}

extension PageEvent {
    static func terminalOutput(_ data: Data) -> [String: Any] { ["event": "terminalOutput", "data": data.base64EncodedString()] }
    static func terminalExited(_ status: Int32) -> [String: Any] { ["event": "terminalExited", "status": status] }
    static func terminalState(visible: Bool, maximized: Bool, hotkey: String, shell: String) -> [String: Any] {
        ["event": "terminalState", "visible": visible, "maximized": maximized, "hotkey": hotkey, "shell": shell]
    }
}

@MainActor
protocol TerminalSessionIO: AnyObject {
    var isRunning: Bool { get }
    var lastSize: TerminalSize { get }
    var recentOutput: Data { get }
    var onOutput: ((Data) -> Void)? { get set }
    var onExit: ((Int32) -> Void)? { get set }
    func start(cols: Int, rows: Int) -> Bool
    func write(_ data: Data)
    func resize(cols: Int, rows: Int)
    func terminate()
}

extension TerminalSession: TerminalSessionIO {}

@MainActor
final class TerminalBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var webView: WKWebView?
    private let session: TerminalSessionIO
    private let send: ([String: Any]) -> Void
    private let state: () -> [String: Any]
    private let toggleMaximize: () -> Bool
    private let hide: () -> Void
    private var ready = false

    init(session: TerminalSessionIO, send: @escaping ([String: Any]) -> Void,
         state: @escaping () -> [String: Any], toggleMaximize: @escaping () -> Bool, hide: @escaping () -> Void) {
        self.session = session
        self.send = send
        self.state = state
        self.toggleMaximize = toggleMaximize
        self.hide = hide
        super.init()
        session.onOutput = { [weak self] data in
            guard let self, self.ready else { return }
            self.send(PageEvent.terminalOutput(data))
        }
        session.onExit = { [weak self] status in
            guard let self, self.ready else { return }
            self.send(PageEvent.terminalExited(status))
        }
    }

    func beginPageLoad() { ready = false }

    func handle(_ request: TerminalRequest) -> Result<Any?, BridgeError> {
        switch request {
        case .ready(let size):
            if session.isRunning {
                session.resize(cols: size.cols, rows: size.rows)
                send(PageEvent.terminalOutput(session.recentOutput))
            } else if !session.start(cols: size.cols, rows: size.rows) {
                ready = false
                return .failure(.failed)
            }
            ready = true
            send(state())
        case .input(let data):
            guard ready else { return .failure(.failed) }
            if session.isRunning {
                session.write(Data(data.utf8))
            } else {
                let size = session.lastSize
                guard session.start(cols: size.cols, rows: size.rows) else { return .failure(.failed) }
            }
        case .resize(let size):
            guard ready else { return .failure(.failed) }
            session.resize(cols: size.cols, rows: size.rows)
        case .toggleMaximize:
            let maximized = toggleMaximize()
            send(state())
            return .success(["maximized": maximized])
        case .hide:
            hide()
        }
        return .success(nil)
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        let origin = message.frameInfo.securityOrigin
        guard let webView, TerminalBridgeOrigin.isTrusted(isTerminalWebView: message.webView === webView,
            isMainFrame: message.frameInfo.isMainFrame, scheme: origin.protocol, host: origin.host) else {
            reject(.untrusted, action: "?", replyHandler: replyHandler)
            return
        }
        let candidate = (message.body as? [String: Any])?["action"] as? String
        let action = candidate.flatMap { isValidID($0) && $0.count <= 64 ? $0 : nil } ?? "?"
        switch TerminalRequest.parse(message.body).flatMap(handle) {
        case .success(let value): replyHandler(value, nil)
        case .failure(let error): reject(error, action: action, replyHandler: replyHandler)
        }
    }

    private func reject(_ error: BridgeError, action: String, replyHandler: @MainActor @Sendable (Any?, String?) -> Void) {
        Log.error("terminal \(action) rejected: \(error.rawValue)")
        replyHandler(nil, error.rawValue)
    }
}
