import Foundation
import Testing
@testable import DesktopShell

struct TerminalPanelTests {
    @Test("终端面板普通和放大位置保留菜单栏与 Dock 安全区域")
    func geometry() {
        let screen = CGRect(x: 0, y: 87, width: 1792, height: 1003)
        #expect(TerminalPanelGeometry.frame(visibleFrame: screen, maximized: false)
            == CGRect(x: 16, y: 631, width: 1760, height: 451))
        #expect(TerminalPanelGeometry.frame(visibleFrame: screen, maximized: true)
            == CGRect(x: 16, y: 95, width: 1760, height: 987))
        #expect(TerminalPanelGeometry.frame(visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1040), maximized: false)
            == CGRect(x: -1904, y: 564, width: 1888, height: 468))
    }

    @Test("连续呼出收起时旧动画不能覆盖最后一次请求，放大状态跨收起保持")
    func latestPresentationWins() {
        var state = TerminalPresentation()
        #expect(!state.visible && !state.maximized)
        let first = state.request(visible: true)
        let maximized = state.toggleMaximize()
        #expect(maximized)
        let hide = state.request(visible: false)
        let show = state.request(visible: true)
        #expect(!state.isCurrent(first) && !state.isCurrent(hide) && state.isCurrent(show))
        #expect(state.visible && state.maximized)
        let restored = state.toggleMaximize()
        #expect(!restored)
    }

    @Test("终端导航仅允许本地 app 主框架，拒绝新窗口与外部来源")
    func navigation() {
        #expect(TerminalNavigationPolicy.allows(url: URL(string: "shell://app/terminal.html"), targetIsMainFrame: true))
        for value in ["https://example.com", "file:///tmp/page.html", "shell://other/terminal.html", "about:blank"] {
            #expect(!TerminalNavigationPolicy.allows(url: URL(string: value), targetIsMainFrame: true))
        }
        #expect(!TerminalNavigationPolicy.allows(url: URL(string: "shell://app/terminal.html"), targetIsMainFrame: false))
        #expect(!TerminalNavigationPolicy.allows(url: URL(string: "shell://app/terminal.html"), targetIsMainFrame: nil))
    }
}
