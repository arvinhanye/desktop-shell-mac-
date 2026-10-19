import AppKit
import WebKit
import Testing
@testable import DesktopShell

struct GlassLayerTests {
    @Test("毛玻璃解析保留小数、越界原值、零圆角和最大圆角；空数组可清空")
    func validRegions() throws {
        let regions = try #require(GlassRegions.parse([[-1.25, 2.5, 20.5, 30.5, 10.25], [1, 2, 3, 4, 0]]))
        #expect(regions == [
            GlassRegion(rect: CGRect(x: -1.25, y: 2.5, width: 20.5, height: 30.5), radius: 10.25),
            GlassRegion(rect: CGRect(x: 1, y: 2, width: 3, height: 4), radius: 0),
        ])
        #expect(GlassRegions.parse([])?.isEmpty == true)
        #expect(GlassRegions.parse(Array(repeating: [0, 0, 10, 10, 5], count: 64))?.count == 64)
    }

    @Test("非法毛玻璃参数整体拒绝，不保留合法前缀")
    func invalidRegions() {
        let invalid: [Any] = [NSNull(), "[]", [1, 2, 3, 4, 0], [[0, 0, 10, 10]],
            [[0, 0, 10, 10, 1, 2]], [[0, 0, 0, 10, 0]], [[0, 0, 10, -1, 0]],
            [[0, 0, 10, 10, -1]], [[0, 0, 10, 10, 5.01]],
            Array(repeating: [0, 0, 10, 10, 1], count: 65)]
        for value in invalid { #expect(GlassRegions.parse(value) == nil) }
        for index in 0..<5 {
            for value: Any in [true, false, Double.nan, Double.infinity, -Double.infinity, "1", NSNull()] {
                var row: [Any] = [0, 0, 10, 10, 1]
                row[index] = value
                #expect(GlassRegions.parse([[0, 0, 10, 10, 1], row]) == nil)
            }
        }
        #expect(BridgeRequest.parse(["action": "setGlassRegions", "regions": [], "extra": 1]) == .failure(.invalid))
    }

    @Test("裁剪四边后收小圆角，完全在外和空视口清空，保留原始区域")
    func clip() throws {
        let regions = try #require(GlassRegions.parse([
            [-15.5, -10, 20, 20, 8], [98, 78, 10, 10, 5],
            [100, 0, 10, 10, 2], [-10, 0, 10, 10, 2],
            [0, 80, 10, 10, 2], [0, -10, 10, 10, 2],
        ]))
        #expect(GlassRegions.clip(regions, viewport: CGSize(width: 100, height: 80)) == [
            GlassRegion(rect: CGRect(x: 0, y: 0, width: 4.5, height: 10), radius: 2.25),
            GlassRegion(rect: CGRect(x: 98, y: 78, width: 2, height: 2), radius: 1),
        ])
        #expect(regions[0].radius == 8)
        for size in [CGSize.zero, CGSize(width: -1, height: 80), CGSize(width: CGFloat.infinity, height: 80)] {
            #expect(GlassRegions.clip(regions, viewport: size).isEmpty)
        }
    }

    @Test("真实毛玻璃视图复用、隐藏和圆角缓存；不命中鼠标且材质不跟随焦点")
    @MainActor
    func effectViews() throws {
        _ = NSApplication.shared
        let layer = GlassLayer(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let first = GlassRegion(rect: CGRect(x: 1.25, y: 2.5, width: 30, height: 40), radius: 5.5)
        layer.update([first, first])
        let views = try #require(layer.subviews as? [NSVisualEffectView])
        #expect(views.count == 2)
        #expect(layer.isFlipped)
        #expect(layer.hitTest(CGPoint(x: 10, y: 10)) == nil)
        for view in views {
            #expect(view.frame == first.rect)
            #expect(view.material == .hudWindow)
            #expect(view.blendingMode == .behindWindow)
            #expect(view.state == .active)
            #expect(view.appearance?.name == .darkAqua)
            #expect(!view.isHidden)
        }
        let mask = try #require(views[0].maskImage)
        #expect(views[1].maskImage === mask)
        #expect(mask.size == CGSize(width: 12, height: 12))
        #expect(mask.capInsets.top == 5.5 && mask.capInsets.right == 5.5)
        #expect(mask.capInsets.bottom == 5.5 && mask.capInsets.left == 5.5)
        #expect(mask.resizingMode == .stretch)
        let moved = GlassRegion(rect: CGRect(x: 20, y: 30, width: 30, height: 40), radius: 0)
        layer.update([moved])
        #expect(layer.subviews.count == 2)
        #expect(layer.subviews[0] === views[0])
        #expect(views[0].frame == moved.rect && !views[0].isHidden)
        #expect(views[1].isHidden)
        #expect(views[0].maskImage?.size == CGSize(width: 1, height: 1))
        layer.update([])
        #expect(views.allSatisfy { $0.isHidden })
        layer.update([first, first, first])
        #expect(layer.subviews.count == 3)
        #expect(views[0].maskImage === mask && views[1].maskImage === mask)
        #expect(layer.subviews.allSatisfy { !$0.isHidden })
    }

    @Test("窗口保留层级与鼠标设置，双层填满并随大小变化，导航和关闭清空毛玻璃")
    @MainActor
    func windowLifecycle() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GlassTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = AppPaths(supportDir: directory, mediaDir: directory.appendingPathComponent("media"), webDir: directory)
        let window = WidgetWindow(screen: screen, appState: AppState(paths: paths))
        defer { window.close() }
        let content = try #require(window.contentView)
        #expect(content.subviews.count == 2)
        let glass = try #require(content.subviews.first as? GlassLayer)
        let web = try #require(content.subviews.last as? WKWebView)
        #expect(glass.frame == content.bounds && web.frame == content.bounds)
        #expect(window.level.rawValue == Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
        #expect(window.ignoresMouseEvents && !window.canBecomeKey && !window.canBecomeMain)
        window.setContentSize(CGSize(width: 800, height: 600))
        #expect(glass.frame == content.bounds && web.frame == content.bounds)
        let regions = [GlassRegion(rect: CGRect(x: 10, y: 10, width: 50, height: 50), radius: 5)]
        window.setGlassRegions(regions)
        #expect(glass.subviews.count == 1 && !glass.subviews[0].isHidden)
        web.navigationDelegate?.webView?(web, didStartProvisionalNavigation: nil)
        #expect(glass.subviews.allSatisfy { $0.isHidden })
        window.setGlassRegions(regions)
        window.close()
        #expect(glass.subviews.allSatisfy { $0.isHidden })
    }

}
