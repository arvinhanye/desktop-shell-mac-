import CoreGraphics
import Testing
@testable import DesktopShell

struct SafeAreaTests {
    @Test("Dock 在底部")
    func dockAtBottom() {
        let insets = SafeAreaInsets.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 80, width: 1440, height: 795)
        )

        #expect(insets == SafeAreaInsets(top: 25, right: 0, bottom: 80, left: 0))
    }

    @Test("Dock 在左侧")
    func dockAtLeft() {
        let insets = SafeAreaInsets.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 70, y: 0, width: 1370, height: 875)
        )

        #expect(insets == SafeAreaInsets(top: 25, right: 0, bottom: 0, left: 70))
    }

    @Test("Dock 在右侧")
    func dockAtRight() {
        let insets = SafeAreaInsets.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1370, height: 875)
        )

        #expect(insets == SafeAreaInsets(top: 25, right: 70, bottom: 0, left: 0))
    }

    @Test("副屏原点非零，只有菜单栏")
    func secondaryDisplayWithMenuBar() {
        let insets = SafeAreaInsets.compute(
            screenFrame: CGRect(x: 1440, y: -200, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        )

        #expect(insets == SafeAreaInsets(top: 25, right: 0, bottom: 0, left: 0))
    }

    @Test("没有菜单栏和 Dock")
    func fullScreenIsVisible() {
        let insets = SafeAreaInsets.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(insets == SafeAreaInsets(top: 0, right: 0, bottom: 0, left: 0))
    }

    @Test("visibleFrame 超出 frame，负边距归零")
    func oversizedVisibleFrame() {
        let insets = SafeAreaInsets.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: -10, y: -10, width: 1460, height: 935)
        )

        #expect(insets == SafeAreaInsets(top: 0, right: 0, bottom: 0, left: 0))
    }

    @Test("负横坐标副屏的左侧 Dock")
    func displayToLeftOfPrimary() {
        let insets = SafeAreaInsets.compute(
            screenFrame: CGRect(x: -1920, y: 300, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1850, y: 300, width: 1850, height: 1055)
        )

        #expect(insets == SafeAreaInsets(top: 25, right: 0, bottom: 0, left: 70))
    }

    @Test("各方向独立归零，保留有效边距")
    func clampOnlyNegativeInsets() {
        let insets = SafeAreaInsets.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: -10, y: 80, width: 1455, height: 795)
        )

        #expect(insets == SafeAreaInsets(top: 25, right: 0, bottom: 80, left: 0))
    }

    @Test("保留小数点尺寸，不转成像素或整数")
    func fractionalPointInsets() {
        let insets = SafeAreaInsets.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0.5, y: 80.25, width: 1439.25, height: 794.5)
        )

        #expect(insets == SafeAreaInsets(top: 25.25, right: 0.25, bottom: 80.25, left: 0.5))
    }
}
