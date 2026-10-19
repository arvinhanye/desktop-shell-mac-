import AppKit
import Testing
@testable import DesktopShell

struct WindowLevelsTests {
    private let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

    @Test("组件位于桌面图标层 +3，不依赖固定系统层级数值")
    func widgetLevel() {
        #expect(WindowLevels.widget(iconLevel: iconLevel) == iconLevel + 3)
        #expect(WindowLevels.widget(iconLevel: -100) == -97)
    }

    @Test("显示桌面文件时视频位于图标层 -1")
    func visibleDesktopIcons() {
        #expect(WindowLevels.video(iconLevel: iconLevel, iconsHidden: false) == iconLevel - 1)
        #expect(WindowLevels.video(iconLevel: -100, iconsHidden: false) == -101)
    }

    @Test("隐藏桌面文件时视频升至图标层 +3，取消后恢复")
    func hiddenDesktopIcons() {
        let levels = [false, true, false].map {
            WindowLevels.video(iconLevel: iconLevel, iconsHidden: $0)
        }
        #expect(levels == [iconLevel - 1, iconLevel + 3, iconLevel - 1])
        #expect(WindowLevels.video(iconLevel: -100, iconsHidden: true) == -97)
    }

    @Test("日志把图标附近层级写为相对偏移")
    func nearbyDescriptions() {
        #expect(WindowLevels.describe(iconLevel + 3, iconLevel: iconLevel) == "icon+3")
        #expect(WindowLevels.describe(iconLevel - 1, iconLevel: iconLevel) == "icon-1")
        #expect(WindowLevels.describe(iconLevel, iconLevel: iconLevel) == "icon+0")
        #expect(WindowLevels.describe(iconLevel + 2, iconLevel: iconLevel) == "icon+2")
    }

    @Test("普通窗口等远离图标的层级保留原值，极值不溢出")
    func distantDescriptions() {
        #expect(WindowLevels.describe(0, iconLevel: iconLevel) == "0")
        #expect(WindowLevels.describe(3, iconLevel: iconLevel) == "3")
        #expect(WindowLevels.describe(Int.max, iconLevel: Int.min) == String(Int.max))
        #expect(WindowLevels.describe(Int.min, iconLevel: Int.max) == String(Int.min))
    }

    @Test("真实 NSPanel 配置完成后仍在图标层 +3，保留原有窗口属性")
    @MainActor
    func configuredPanelLevel() {
        _ = NSApplication.shared
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        defer { panel.close() }

        WidgetWindow.configure(panel, iconLevel: iconLevel)

        #expect(panel.level.rawValue == WindowLevels.widget(iconLevel: iconLevel))
        #expect(panel.level.rawValue == iconLevel + 3)
        #expect(panel.hidesOnDeactivate == false)
        #expect(panel.isFloatingPanel == false)
        #expect(panel.collectionBehavior == [.canJoinAllSpaces, .stationary, .ignoresCycle])
        #expect(panel.ignoresMouseEvents)
        #expect(panel.hasShadow == false)
        #expect(panel.isOpaque == false)
        #expect(panel.backgroundColor == .clear)
    }
}
