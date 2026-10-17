import Foundation
import Testing
@testable import DesktopShell

struct HitTestingTests {
    private let viewport = CGSize(width: 200, height: 100)

    @Test("合法矩形保持顺序和小数坐标")
    func validRegions() {
        #expect(HitTesting.parseRegions([[10, 20, 30, 40], [0.5, 1.5, 2.5, 3.5]], viewport: viewport) == [
            CGRect(x: 10, y: 20, width: 30, height: 40),
            CGRect(x: 0.5, y: 1.5, width: 2.5, height: 3.5)
        ])
    }

    @Test("空数组合法，表示移除所有交互区域")
    func emptyRegions() {
        #expect(HitTesting.parseRegions([], viewport: viewport) == [])
    }

    @Test("非数组和缺少的输入整条丢弃")
    func invalidContainer() {
        for value: Any? in [nil, 1, "[]", ["x": 1], NSNull()] {
            #expect(HitTesting.parseRegions(value, viewport: viewport) == nil)
        }
    }

    @Test("条目必须恰好四个数字，一项非法即整条忽略")
    func malformedEntries() {
        for entry: Any in [[], [1, 2, 3], [1, 2, 3, 4, 5], ["1", 2, 3, 4], [1, true, 3, 4], NSNull(), 4] {
            #expect(HitTesting.parseRegions([[1, 2, 3, 4], entry], viewport: viewport) == nil)
        }
    }

    @Test("所有坐标及尺寸都必须有限", arguments: [Double.nan, .infinity, -.infinity])
    func rejectsNonFinite(_ number: Double) {
        for index in 0..<4 {
            var region = [1.0, 2, 3, 4]
            region[index] = number
            #expect(HitTesting.parseRegions([region], viewport: viewport) == nil)
        }
    }

    @Test("宽高必须大于零", arguments: [(0.0, 4.0), (-1, 4), (3, 0), (3, -1)])
    func rejectsNonPositiveSize(_ width: Double, _ height: Double) {
        #expect(HitTesting.parseRegions([[1, 2, width, height]], viewport: viewport) == nil)
    }

    @Test("允许64项，65项即使都在视口外也整条忽略")
    func countLimit() {
        #expect(HitTesting.parseRegions(Array(repeating: [1, 2, 3, 4], count: 64), viewport: viewport)?.count == 64)
        #expect(HitTesting.parseRegions(Array(repeating: [300, 200, 3, 4], count: 65), viewport: viewport) == nil)
    }

    @Test("矩形与视口求交集，完全在外或仅边缘相接的丢弃")
    func clipsRegions() {
        #expect(HitTesting.parseRegions([
            [-10, -20, 40, 50], [180, 80, 50, 50], [300, 0, 20, 20],
            [0, -50, 20, 20], [200, 0, 10, 10], [0, 100, 10, 10]
        ], viewport: viewport) == [
            CGRect(x: 0, y: 0, width: 30, height: 30),
            CGRect(x: 180, y: 80, width: 20, height: 20)
        ])
    }

    @Test("接受WK消息中的NSNumber，但拒绝桥接布尔值")
    func bridgedNumbers() {
        let region: [NSNumber] = [1, 2, 3, 4]
        #expect(HitTesting.parseRegions([region], viewport: viewport) == [CGRect(x: 1, y: 2, width: 3, height: 4)])
        #expect(HitTesting.parseRegions([[NSNumber(value: true), 2, 3, 4]], viewport: viewport) == nil)
    }

    @Test("极大但有限的矩形仍裁到有限视口")
    func hugeRegions() {
        #expect(HitTesting.parseRegions([[0, 0, Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]], viewport: viewport) == [CGRect(origin: .zero, size: viewport)])
    }

    @Test("网页区域包含左上，不包含右下", arguments: [
        (10.0, 80.0, true), (39, 41, true), (40, 80, false),
        (10, 40, false), (9, 80, false), (10, 81, false)
    ])
    func regionEdges(_ x: Double, _ y: Double, _ expected: Bool) {
        #expect(HitTesting.isInteractive(mouse: CGPoint(x: x, y: y),
            windowFrame: CGRect(x: 0, y: 0, width: 200, height: 100),
            regions: [CGRect(x: 10, y: 20, width: 30, height: 40)]) == expected)
    }

    @Test("副屏全局坐标含负Y时正确换算")
    func secondaryDisplay() {
        let frame = CGRect(x: 1792, y: -200, width: 1920, height: 1080)
        let regions = [CGRect(x: 20, y: 30, width: 100, height: 60)]
        #expect(HitTesting.isInteractive(mouse: CGPoint(x: 1812, y: 850), windowFrame: frame, regions: regions))
        #expect(!HitTesting.isInteractive(mouse: CGPoint(x: 1812, y: 790), windowFrame: frame, regions: regions))
        #expect(!HitTesting.isInteractive(mouse: CGPoint(x: 1912, y: 850), windowFrame: frame, regions: regions))
    }

    @Test("窗口边界遵循网页左上原点，即使区域越界也不接住外部光标")
    func windowEdges() {
        let frame = CGRect(x: -200, y: -100, width: 200, height: 100)
        let regions = [CGRect(x: -50, y: -50, width: 300, height: 200)]
        #expect(HitTesting.isInteractive(mouse: CGPoint(x: -200, y: 0), windowFrame: frame, regions: regions))
        for point in [CGPoint(x: -201, y: -1), CGPoint(x: 0, y: -1), CGPoint(x: -1, y: 1), CGPoint(x: -1, y: -100)] {
            #expect(!HitTesting.isInteractive(mouse: point, windowFrame: frame, regions: regions))
        }
    }

    @Test("多个区域任意命中，空区域始终穿透")
    func multipleRegions() {
        let frame = CGRect(origin: .zero, size: viewport)
        let point = CGPoint(x: 105, y: 45)
        #expect(HitTesting.isInteractive(mouse: point, windowFrame: frame, regions: [
            CGRect(x: 10, y: 20, width: 30, height: 40), CGRect(x: 100, y: 50, width: 10, height: 10)
        ]))
        #expect(!HitTesting.isInteractive(mouse: point, windowFrame: frame, regions: []))
    }
}
