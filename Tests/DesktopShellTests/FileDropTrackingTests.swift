import Foundation
import Testing
@testable import DesktopShell

struct FileDropTrackingTests {
    @Test("仅剪贴板在按下后变化且带文件 URL 时识别文件拖动")
    func fileDrag() {
        for changed in [false, true] {
            for hasURLs in [false, true] {
                #expect(FileDropTracking.isFileDrag(changeCountAtMouseDown: 10,
                    currentChangeCount: changed ? 11 : 10, hasFileURLs: hasURLs) == (changed && hasURLs))
            }
        }
        #expect(!FileDropTracking.isFileDrag(changeCountAtMouseDown: nil, currentChangeCount: 11, hasFileURLs: true))
        #expect(FileDropTracking.isFileDrag(changeCountAtMouseDown: 11, currentChangeCount: 1, hasFileURLs: true))
    }

    @Test("第二块屏幕与负坐标屏幕的拖入区域使用网页左上坐标和半开边界")
    func dropRegion() {
        for origin in [CGPoint(x: 1920, y: 100), CGPoint(x: -1440, y: -300)] {
            let frame = CGRect(origin: origin, size: CGSize(width: 1440, height: 900))
            let regions = [CGRect(x: 20, y: 30, width: 100, height: 80)]
            for (webPoint, expected) in [
                (CGPoint(x: 20, y: 30), true), (CGPoint(x: 119.9, y: 109.9), true),
                (CGPoint(x: 19.9, y: 30), false), (CGPoint(x: 20, y: 29.9), false),
                (CGPoint(x: 120, y: 30), false), (CGPoint(x: 20, y: 110), false),
                (CGPoint(x: -1, y: 0), false), (CGPoint(x: 1440, y: 900), false),
            ] {
                let mouse = CGPoint(x: frame.minX + webPoint.x, y: frame.maxY - webPoint.y)
                #expect(FileDropTracking.isInDropRegion(mouse: mouse, windowFrame: frame, regions: regions) == expected)
            }
            #expect(!FileDropTracking.isInDropRegion(mouse: origin, windowFrame: frame, regions: []))
        }
    }

    @Test("拖入结果按顺序保留成功项，只保留第一个错误，不携带路径")
    func outcomes() {
        let a = AppConfig.Project(id: "a", name: "甲", path: "/private/a", tags: [], apps: [])
        let b = AppConfig.Project(id: "b", name: "乙", path: "/private/b", tags: [], apps: [])
        let all = FileDropTracking.dropOutcome(results: [.success(a), .success(b)])
        #expect(all.added.map(\.id) == ["a", "b"] && all.added.map(\.name) == ["甲", "乙"])
        #expect(all.error == nil)
        let partial = FileDropTracking.dropOutcome(results: [.failure(.duplicate), .success(a), .failure(.notDirectory), .success(b)])
        #expect(partial.added == all.added && partial.error == .duplicate)
        let failed = FileDropTracking.dropOutcome(results: [.failure(.notFound), .failure(.outsideHome)])
        #expect(failed.added.isEmpty && failed.error == .notFound)
        let empty = FileDropTracking.dropOutcome(results: [])
        #expect(empty.added.isEmpty && empty.error == nil)
    }
}
