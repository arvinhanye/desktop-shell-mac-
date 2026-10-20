import AppKit
import Testing
@testable import DesktopShell

struct LaunchAtLoginTests {
    @Test("已启用的登录项显示勾选")
    func enabledMenuState() {
        #expect(LaunchAtLogin.menuState(.enabled) == .on)
    }

    @Test("等待用户批准的登录项显示混合状态而非已启用")
    func approvalMenuState() {
        #expect(LaunchAtLogin.menuState(.requiresApproval) == .mixed)
    }

    @Test("未注册的登录项显示未勾选")
    func unregisteredMenuState() {
        #expect(LaunchAtLogin.menuState(.notRegistered) == .off)
    }

    @Test("首次未找到登录项时显示未勾选")
    func notFoundMenuState() {
        #expect(LaunchAtLogin.menuState(.notFound) == .off)
    }

    @Test("未知系统状态不显示为已启用")
    func unknownMenuState() {
        #expect(LaunchAtLogin.menuState(.unknown) == .off)
    }

    @Test("点击已启用的登录项会请求取消注册")
    func enabledAction() {
        #expect(LaunchAtLogin.action(for: .enabled) == .unregister)
    }

    @Test("点击待批准的登录项只打开系统设置")
    func approvalAction() {
        #expect(LaunchAtLogin.action(for: .requiresApproval) == .openSettings)
    }

    @Test("点击未注册的登录项会请求注册")
    func unregisteredAction() {
        #expect(LaunchAtLogin.action(for: .notRegistered) == .register)
    }

    @Test("首次未找到登录项时点击会请求注册")
    func notFoundAction() {
        #expect(LaunchAtLogin.action(for: .notFound) == .register)
    }

    @Test("点击未知系统状态的登录项会尝试注册")
    func unknownAction() {
        #expect(LaunchAtLogin.action(for: .unknown) == .register)
    }
}
