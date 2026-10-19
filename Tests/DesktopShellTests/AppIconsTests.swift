import AppKit
import Testing
@testable import DesktopShell

struct AppIconsTests {
    private let app = AppConfig.App(id: "editor", name: "Editor", bundleId: "test.editor")

    private func icon() -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<16 { for x in 0..<32 { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        #expect((bitmap.colorAt(x: 16, y: 8)?.alphaComponent ?? 0) > 0)
        let image = NSImage(size: NSSize(width: 32, height: 16))
        image.addRepresentation(bitmap)
        return image
    }

    @MainActor @Test("导出不占主线程；所有等待者在最近一次导出完成后仅回复一次，重新加载不复用旧成功表")
    func waitsForLatestExport() async throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        var config = AppConfig.example
        config.apps = [app]
        let configFile = fixture.root.appendingPathComponent("config.json")
        try JSONEncoder().encode(config).write(to: configFile)
        let paths = AppPaths(supportDir: fixture.root, mediaDir: fixture.root.appendingPathComponent("media"), webDir: fixture.root)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); gate.signal() }
        let (started, continuation) = AsyncStream<(String, Bool)>.makeStream()
        defer { continuation.finish() }
        let exporter = AppIcons(loadIcon: { bundleID in
            continuation.yield((bundleID, Thread.isMainThread))
            // A finite timeout bounds regressions that accidentally block the main thread.
            guard gate.wait(timeout: .now() + 5) == .success else { return nil }
            return bundleID == "test.editor" ? icon() : nil
        })
        let state = AppState(paths: paths, appIcons: exporter)
        var results: [Set<String>] = []
        let (finished, completed) = AsyncStream<Set<String>>.makeStream()
        defer { completed.finish() }
        state.exportAppIcons()
        for _ in 0..<2 {
            state.withAppIcons { ids in
                #expect(Thread.isMainThread)
                results.append(ids)
                completed.yield(ids)
            }
        }
        #expect(results.isEmpty)
        guard results.isEmpty else { return }
        var starts = started.makeAsyncIterator()
        let first = try #require(await starts.next())
        #expect(first.0 == "test.editor")
        #expect(first.1 == false)

        // Reload while the first generation is still running. Its successful result
        // must not settle any request for the now-missing application.
        config.apps[0].bundleId = "test.missing"
        let reloadedData = try JSONEncoder().encode(config)
        try reloadedData.write(to: configFile)
        state.reloadConfig()
        state.exportAppIcons()
        gate.signal()
        let second = try #require(await starts.next())
        #expect(second.0 == "test.missing")
        #expect(second.1 == false)
        #expect(results.isEmpty)
        gate.signal()
        var replies = finished.makeAsyncIterator()
        #expect(await replies.next() == [])
        #expect(await replies.next() == [])
        #expect(results == [[], []])
        var immediate: Set<String>?
        state.withAppIcons { immediate = $0 }
        #expect(immediate == [])
        #expect(FileManager.default.fileExists(atPath: paths.mediaDir.appendingPathComponent("app-icons/editor.png").path))
        #expect(try Data(contentsOf: configFile) == reloadedData)
    }

    @Test("图标导出创建目录、写出非空 128×128 PNG，仅替换同名旧文件")
    func exportsPNG() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let exporter = AppIcons(loadIcon: { id in id == "test.editor" ? icon() : nil })
        #expect(exporter.export(apps: [app], mediaDir: fixture.root) == ["editor"])
        let file = fixture.root.appendingPathComponent("app-icons/editor.png")
        let data = try Data(contentsOf: file)
        #expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect(bitmap.pixelsWide == 128)
        #expect(bitmap.pixelsHigh == 128)
        #expect((bitmap.colorAt(x: 64, y: 64)?.alphaComponent ?? 0) > 0)
        let marker = try fixture.file("app-icons/keep.txt", contents: "keep")
        try Data("old".utf8).write(to: file)
        #expect(exporter.export(apps: [app], mediaDir: fixture.root) == ["editor"])
        #expect(try Data(contentsOf: file) == data)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "keep")
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).sorted() == ["editor.png", "keep.txt"])
    }

    @Test("找不到应用或写入失败时成功表为空，旧文件和占位目录不动")
    func failuresPreserveExistingFiles() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let old = try fixture.file("app-icons/editor.png", contents: "old")
        #expect(AppIcons(loadIcon: { _ in nil }).export(apps: [app], mediaDir: fixture.root).isEmpty)
        #expect(try String(contentsOf: old, encoding: .utf8) == "old")
        try FileManager.default.removeItem(at: old)
        _ = try fixture.directory("app-icons/editor.png")
        let marker = try fixture.file("app-icons/editor.png/keep", contents: "keep")
        #expect(AppIcons(loadIcon: { _ in icon() }).export(apps: [app], mediaDir: fixture.root).isEmpty)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "keep")
        #expect(try FileManager.default.contentsOfDirectory(atPath: old.deletingLastPathComponent().path) == ["editor.png"])
    }

    @Test("符号链接或普通文件占用 app-icons 时整次不导出")
    func rejectsInvalidDirectory() throws {
        for symlink in [true, false] {
            let fixture = try TemporaryTestDirectory()
            defer { fixture.cleanup() }
            let directory = fixture.root.appendingPathComponent("app-icons")
            let outside = try fixture.directory("outside")
            if symlink {
                try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
            } else {
                _ = try fixture.file("app-icons", contents: "keep")
            }
            var calls = 0
            let result = AppIcons(loadIcon: { _ in calls += 1; return icon() }).export(apps: [app], mediaDir: fixture.root)
            #expect(result.isEmpty)
            #expect(calls == 0)
            #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
            if !symlink { #expect(try String(contentsOf: directory, encoding: .utf8) == "keep") }
        }
    }

    @Test("文件符号链接仅替换链接本身，不写入其目标；非法 id 不导出")
    func outputLinksAndInvalidIDs() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        _ = try fixture.directory("app-icons")
        let target = try fixture.file("outside.png", contents: "outside")
        let file = fixture.root.appendingPathComponent("app-icons/editor.png")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        let invalid = AppConfig.App(id: "../bad", name: "Bad", bundleId: "test.bad")
        #expect(AppIcons(loadIcon: { _ in icon() }).export(apps: [app, invalid], mediaDir: fixture.root) == ["editor"])
        #expect(try String(contentsOf: target, encoding: .utf8) == "outside")
        #expect(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("bad.png").path))
    }
}
