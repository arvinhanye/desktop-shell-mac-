import Foundation
import Testing
@testable import DesktopShell

struct TerminalBridgeTests {
    @Test("终端五个动作解析合法消息，其他页面动作均拒绝")
    func requests() {
        #expect(TerminalRequest.parse(["action": "terminalReady", "cols": 80, "rows": 24]) == .success(.ready(TerminalSize(cols: 80, rows: 24))))
        #expect(TerminalRequest.parse(["action": "terminalResize", "cols": 1000, "rows": 1]) == .success(.resize(TerminalSize(cols: 1000, rows: 1))))
        #expect(TerminalRequest.parse(["action": "terminalInput", "data": "你好\r"]) == .success(.input("你好\r")))
        #expect(TerminalRequest.parse(["action": "toggleTerminalMaximize"]) == .success(.toggleMaximize))
        #expect(TerminalRequest.parse(["action": "hideTerminal"]) == .success(.hide))
        for action in ["getConfig", "openTerminal", "openProject", "unknown", ""] {
            #expect(TerminalRequest.parse(["action": action]) == .failure(.untrusted))
        }
    }

    @Test("终端请求严格拒绝额外参数、布尔尺寸、非整数和超限输入")
    func invalidRequests() {
        for action in ["terminalReady", "terminalResize"] {
            for value: Any in [0, 1001, -1, 1.5, true, "80", NSNull(), Double.infinity, Double.nan] {
                #expect(TerminalRequest.parse(["action": action, "cols": value, "rows": 24]) == .failure(.invalid))
                #expect(TerminalRequest.parse(["action": action, "cols": 80, "rows": value]) == .failure(.invalid))
            }
            #expect(TerminalRequest.parse(["action": action, "cols": 80]) == .failure(.invalid))
            #expect(TerminalRequest.parse(["action": action, "cols": 80, "rows": 24, "extra": 1]) == .failure(.invalid))
        }
        for action in ["hideTerminal", "toggleTerminalMaximize"] {
            #expect(TerminalRequest.parse(["action": action, "extra": 1]) == .failure(.invalid))
        }
        for value: Any in ["", String(repeating: "a", count: 65537), String(repeating: "😀", count: 32769), true, NSNull()] {
            #expect(TerminalRequest.parse(["action": "terminalInput", "data": value]) == .failure(.invalid))
        }
        let boundary = String(repeating: "😀", count: 32768)
        #expect(TerminalRequest.parse(["action": "terminalInput", "data": boundary]) == .success(.input(boundary)))
        #expect(TerminalRequest.parse(["action": "terminalInput", "data": "x", "extra": 1]) == .failure(.invalid))
        #expect(TerminalRequest.parse(["action": 1]) == .failure(.invalid))
    }

    @Test("终端权限同时绑定 WebView 身份、主框架和 app 来源")
    func origin() {
        #expect(TerminalBridgeOrigin.isTrusted(isTerminalWebView: true, isMainFrame: true, scheme: "shell", host: "app"))
        #expect(!TerminalBridgeOrigin.isTrusted(isTerminalWebView: false, isMainFrame: true, scheme: "shell", host: "app"))
        #expect(!TerminalBridgeOrigin.isTrusted(isTerminalWebView: true, isMainFrame: false, scheme: "shell", host: "app"))
        #expect(!TerminalBridgeOrigin.isTrusted(isTerminalWebView: true, isMainFrame: true, scheme: "https", host: "app"))
        #expect(!TerminalBridgeOrigin.isTrusted(isTerminalWebView: true, isMainFrame: true, scheme: "shell", host: "other"))
    }

    @Test("终端事件保留原始字节，状态仅含公开字段")
    func events() throws {
        let state = PageEvent.terminalState(visible: true, maximized: false, hotkey: "⌥`", shell: "zsh")
        #expect(Set(state.keys) == ["event", "visible", "maximized", "hotkey", "shell"])
        #expect(state["event"] as? String == "terminalState")
        #expect(state["visible"] as? Bool == true)
        #expect(state["maximized"] as? Bool == false)
        #expect(state["hotkey"] as? String == "⌥`")
        #expect(state["shell"] as? String == "zsh")
        let bytes = Data([0xE4, 0xBD])
        #expect(PageEvent.terminalOutput(bytes)["data"] as? String == "5L0=")
        #expect(PageEvent.terminalExited(7)["status"] as? Int32 == 7)
        #expect(JSONSerialization.isValidJSONObject(state))
    }

    @Test("ready 才启动、重载重放而不重开、退出后的首键只重启并沿用尺寸")
    @MainActor func sessionLifecycle() throws {
        let session = StubTerminalSession()
        var events: [[String: Any]] = []
        var maximized = false
        var hidden = false
        let bridge = TerminalBridge(session: session, send: { events.append($0) },
            state: { PageEvent.terminalState(visible: !hidden, maximized: maximized, hotkey: "⌥`", shell: "zsh") },
            toggleMaximize: { maximized.toggle(); return maximized }, hide: { hidden = true })
        #expect(throws: BridgeError.failed) { try bridge.handle(.input("x")).get() }
        _ = try bridge.handle(.ready(TerminalSize(cols: 120, rows: 30))).get()
        #expect(session.starts == [TerminalSize(cols: 120, rows: 30)])
        _ = try bridge.handle(.input("你好\r")).get()
        #expect(session.writes == [Data("你好\r".utf8)])
        session.emit(Data([0xE4, 0xBD]))
        #expect(events.last?["data"] as? String == "5L0=")
        bridge.beginPageLoad()
        let before = events.count
        session.emit(Data([0xA0]))
        #expect(events.count == before)
        #expect(throws: BridgeError.failed) { try bridge.handle(.input("stale")).get() }
        _ = try bridge.handle(.ready(TerminalSize(cols: 140, rows: 40))).get()
        #expect(session.starts.count == 1)
        #expect(session.lastSize == TerminalSize(cols: 140, rows: 40))
        #expect(events[events.count - 2]["data"] as? String == "5L2g")
        session.exit(9)
        #expect(events.last?["status"] as? Int32 == 9)
        _ = try bridge.handle(.input("discard")).get()
        #expect(session.starts == [TerminalSize(cols: 120, rows: 30), TerminalSize(cols: 140, rows: 40)])
        #expect(session.writes.count == 1)
        let reply = try bridge.handle(.toggleMaximize).get() as? [String: Bool]
        #expect(reply == ["maximized": true])
        #expect(events.last?["maximized"] as? Bool == true)
        _ = try bridge.handle(.hide).get()
        #expect(hidden)
    }

    @Test("启动失败必须回复 failed，不让随后输入绕过 ready")
    @MainActor func launchFailure() {
        let session = StubTerminalSession()
        session.startSucceeds = false
        let bridge = TerminalBridge(session: session, send: { _ in }, state: { [:] }, toggleMaximize: { false }, hide: {})
        #expect(throws: BridgeError.failed) { try bridge.handle(.ready(TerminalSize(cols: 80, rows: 24))).get() }
        #expect(throws: BridgeError.failed) { try bridge.handle(.input("x")).get() }
    }
}

@MainActor private final class StubTerminalSession: TerminalSessionIO {
    var isRunning = false
    var lastSize = TerminalSize(cols: 80, rows: 24)
    var recentOutput = Data()
    var onOutput: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?
    var startSucceeds = true
    var starts: [TerminalSize] = []
    var writes: [Data] = []
    func start(cols: Int, rows: Int) -> Bool {
        guard startSucceeds else { return false }
        lastSize = TerminalSize(cols: cols, rows: rows)
        starts.append(lastSize); isRunning = true; recentOutput = Data()
        return true
    }
    func write(_ data: Data) { writes.append(data) }
    func resize(cols: Int, rows: Int) { lastSize = TerminalSize(cols: cols, rows: rows) }
    func terminate() { isRunning = false }
    func emit(_ data: Data) { recentOutput.append(data); onOutput?(data) }
    func exit(_ status: Int32) { isRunning = false; onExit?(status) }
}
