import Foundation
import Testing
@testable import DesktopShell

struct TemporaryTestDirectory {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopShellTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func directory(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func file(_ path: String, contents: String = "fixture") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func cleanup() {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("临时目录清理失败：\(error)")
        }
    }
}

struct AppPathsTests {
    @Test("环境网页目录优先于包内资源和当前目录")
    func environmentWebWins() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let custom = try fixture.directory("custom web")
        let resources = try fixture.directory("Resources")
        _ = try fixture.directory("Resources/web")
        let cwd = try fixture.directory("repo")
        _ = try fixture.directory("repo/web")
        let paths = AppPaths.resolve(
            environment: ["DESKTOPSHELL_WEB_DIR": custom.path],
            bundleResourceURL: resources, currentDirectory: cwd, home: fixture.root,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        #expect(paths.webDir == custom)
    }

    @Test("包内网页存在时优先于开发目录")
    func bundleWebWins() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let resources = try fixture.directory("Resources")
        let web = try fixture.directory("Resources/web")
        let paths = AppPaths.resolve(
            environment: [:], bundleResourceURL: resources,
            currentDirectory: fixture.root, home: fixture.root,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        #expect(paths.webDir == web)
    }

    @Test("包内网页缺失时回到当前目录，默认支持目录来自注入 home")
    func developmentFallback() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let cwd = try fixture.directory("repo")
        let home = try fixture.directory("home")
        let paths = AppPaths.resolve(
            environment: [:], bundleResourceURL: fixture.root.appendingPathComponent("MissingResources"),
            currentDirectory: cwd, home: home, fileExists: { _ in false }
        )
        #expect(paths.webDir == cwd.appendingPathComponent("web", isDirectory: true))
        #expect(paths.supportDir == home.appendingPathComponent("Library/Application Support/DesktopShell", isDirectory: true))
        #expect(paths.mediaDir == paths.supportDir.appendingPathComponent("media", isDirectory: true))
    }

    @Test("支持目录覆盖不要求预先存在，media 始终跟随它")
    func supportOverride() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let support = fixture.root.appendingPathComponent("new support", isDirectory: true)
        let paths = AppPaths.resolve(
            environment: ["DESKTOPSHELL_SUPPORT_DIR": support.path], bundleResourceURL: nil,
            currentDirectory: fixture.root, home: fixture.root, fileExists: { _ in false }
        )
        #expect(paths.supportDir == support)
        #expect(paths.mediaDir == support.appendingPathComponent("media", isDirectory: true))
        #expect(!FileManager.default.fileExists(atPath: support.path))
    }

    @Test("空环境值按未设置处理")
    func emptyOverrides() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let paths = AppPaths.resolve(
            environment: ["DESKTOPSHELL_SUPPORT_DIR": "", "DESKTOPSHELL_WEB_DIR": ""],
            bundleResourceURL: nil, currentDirectory: fixture.root, home: fixture.root,
            fileExists: { _ in false }
        )
        #expect(paths.supportDir == fixture.root.appendingPathComponent("Library/Application Support/DesktopShell", isDirectory: true))
        #expect(paths.webDir == fixture.root.appendingPathComponent("web", isDirectory: true))
    }

    @Test("不可用的环境网页目录退回包内目录")
    func missingEnvironmentWebFallsBack() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let web = try fixture.directory("Resources/web")
        let paths = AppPaths.resolve(
            environment: ["DESKTOPSHELL_WEB_DIR": fixture.root.appendingPathComponent("missing").path],
            bundleResourceURL: web.deletingLastPathComponent(), currentDirectory: fixture.root,
            home: fixture.root, fileExists: { $0 == web }
        )
        #expect(paths.webDir == web)
    }

    @Test("相对环境路径以注入的当前目录为基准")
    func relativeOverrides() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let web = try fixture.directory("custom/web")
        let paths = AppPaths.resolve(
            environment: ["DESKTOPSHELL_SUPPORT_DIR": "local support", "DESKTOPSHELL_WEB_DIR": "custom/web"],
            bundleResourceURL: nil, currentDirectory: fixture.root, home: fixture.root,
            fileExists: { $0 == web }
        )
        #expect(paths.webDir == web)
        #expect(paths.supportDir == fixture.root.appendingPathComponent("local support", isDirectory: true))
    }
}
