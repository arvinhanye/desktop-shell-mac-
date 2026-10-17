import Foundation
import Testing
@testable import DesktopShell

struct SchemeResolverTests {
    @Test("首页、网页模块、语音以及带空格和中文的路径正常映射")
    func mapsFiles() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let index = try fixture.file("web/index.html")
        let module = try fixture.file("web/js/a.js")
        let audio = try fixture.file("media/voice/1.mp3")
        let named = try fixture.file("web/资源/my file.txt")
        let resolver = SchemeResolver(webRoot: index.deletingLastPathComponent(), mediaRoot: fixture.root.appendingPathComponent("media"))
        #expect(resolver.fileURL(forPath: "/") == index.resolvingSymlinksInPath().standardizedFileURL)
        #expect(resolver.fileURL(forPath: "/js/a.js") == module.resolvingSymlinksInPath().standardizedFileURL)
        #expect(resolver.fileURL(forPath: "/media/voice/1.mp3") == audio.resolvingSymlinksInPath().standardizedFileURL)
        #expect(resolver.fileURL(forPath: "/资源/my file.txt") == named.resolvingSymlinksInPath().standardizedFileURL)
    }

    @Test("拒绝点路径、空段、隐藏文件、NUL、相对路径和重复根斜线", arguments: [
        "/../secret", "/media/../config.json", "/a/./b", "/a//b", "/.hidden", "/media/.DS_Store",
        "/a/.hidden/b", "/a/b/", "/a\0b", "index.html", "", "//index.html", "/media//voice/1.mp3", "/media/"
    ])
    func rejectsInvalidPaths(_ path: String) throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        _ = try fixture.file("secret")
        _ = try fixture.file("config.json")
        _ = try fixture.file("web/index.html")
        _ = try fixture.file("web/a/b")
        _ = try fixture.file("web/.hidden")
        _ = try fixture.file("media/.DS_Store")
        _ = try fixture.file("media/voice/1.mp3")
        let resolver = SchemeResolver(webRoot: fixture.root.appendingPathComponent("web"), mediaRoot: fixture.root.appendingPathComponent("media"))
        #expect(resolver.fileURL(forPath: path) == nil)
    }

    @Test("目录、缺失文件和缺失首页均不返回 URL")
    func rejectsDirectoriesAndMissingFiles() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let web = try fixture.directory("web/js")
        let media = try fixture.directory("media/voice")
        let resolver = SchemeResolver(webRoot: web.deletingLastPathComponent(), mediaRoot: media.deletingLastPathComponent())
        for path in ["/", "/js", "/js/missing.js", "/media/voice", "/media/voice/missing.mp3"] {
            #expect(resolver.fileURL(forPath: path) == nil)
        }
    }

    @Test("共享前缀的 web2 目录不属于 web 根目录")
    func rejectsSiblingPrefix() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let web = try fixture.directory("web")
        let outside = try fixture.file("web2/x.html", contents: "outside")
        try FileManager.default.createSymbolicLink(at: web.appendingPathComponent("x.html"), withDestinationURL: outside)
        let resolver = SchemeResolver(webRoot: web, mediaRoot: fixture.root.appendingPathComponent("media"))
        #expect(resolver.fileURL(forPath: "/x.html") == nil)
    }

    @Test("两个根目录的文件链接和目录链接都不应逃逸")
    func rejectsEscapingSymlinks() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let web = try fixture.directory("web")
        let media = try fixture.directory("media")
        let outside = try fixture.file("outside/secret.txt", contents: "secret")
        for root in [web, media] {
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.txt"), withDestinationURL: outside)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape-dir"), withDestinationURL: outside.deletingLastPathComponent())
        }
        let resolver = SchemeResolver(webRoot: web, mediaRoot: media)
        for path in ["/escape.txt", "/escape-dir/secret.txt", "/media/escape.txt", "/media/escape-dir/secret.txt"] {
            #expect(resolver.fileURL(forPath: path) == nil)
        }
    }

    @Test("根目录内的文件和目录链接可访问，两个根都支持别名")
    func allowsInternalSymlinksAndRootAliases() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let web = try fixture.directory("web")
        let media = try fixture.directory("media")
        let script = try fixture.file("web/js/a.js")
        let voice = try fixture.file("media/voice/1.mp3")
        try FileManager.default.createSymbolicLink(at: web.appendingPathComponent("alias.js"), withDestinationURL: script)
        try FileManager.default.createSymbolicLink(at: web.appendingPathComponent("scripts"), withDestinationURL: script.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(at: media.appendingPathComponent("alias.mp3"), withDestinationURL: voice)
        let webAlias = fixture.root.appendingPathComponent("web-alias")
        let mediaAlias = fixture.root.appendingPathComponent("media-alias")
        try FileManager.default.createSymbolicLink(at: webAlias, withDestinationURL: web)
        try FileManager.default.createSymbolicLink(at: mediaAlias, withDestinationURL: media)
        let resolver = SchemeResolver(webRoot: webAlias, mediaRoot: mediaAlias)
        #expect(resolver.fileURL(forPath: "/alias.js") == script.resolvingSymlinksInPath().standardizedFileURL)
        #expect(resolver.fileURL(forPath: "/scripts/a.js") == script.resolvingSymlinksInPath().standardizedFileURL)
        #expect(resolver.fileURL(forPath: "/media/alias.mp3") == voice.resolvingSymlinksInPath().standardizedFileURL)
    }

    @Test("悬空链接和循环链接不是可读的普通文件")
    func rejectsBrokenAndCyclicLinks() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let web = try fixture.directory("web")
        try FileManager.default.createSymbolicLink(atPath: web.appendingPathComponent("missing").path, withDestinationPath: "nowhere")
        try FileManager.default.createSymbolicLink(atPath: web.appendingPathComponent("loop").path, withDestinationPath: "loop")
        let resolver = SchemeResolver(webRoot: web, mediaRoot: fixture.root.appendingPathComponent("media"))
        #expect(resolver.fileURL(forPath: "/missing") == nil)
        #expect(resolver.fileURL(forPath: "/loop") == nil)
    }

    @Test("URL.path 的百分号解码输入仍受相同穿越检查")
    func rejectsDecodedTraversal() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let web = try fixture.directory("web")
        let media = try fixture.directory("media")
        _ = try fixture.file("config.json", contents: "private config")
        let resolver = SchemeResolver(webRoot: web, mediaRoot: media)
        for rawURL in ["shell://app/media/..%2fconfig.json", "shell://app/%2e%2e/config.json"] {
            let url = try #require(URL(string: rawURL))
            #expect(resolver.fileURL(forPath: url.path) == nil)
        }
    }

    @Test("MIME 映射覆盖完整列表及大小写和未知扩展名", arguments: [
        ("html", "text/html"), ("js", "text/javascript"), ("mjs", "text/javascript"),
        ("css", "text/css"), ("json", "application/json"), ("png", "image/png"),
        ("jpg", "image/jpeg"), ("jpeg", "image/jpeg"), ("svg", "image/svg+xml"),
        ("webp", "image/webp"), ("mp3", "audio/mpeg"), ("mp4", "video/mp4"),
        ("woff2", "font/woff2"), ("woff", "font/woff"), ("ttf", "font/ttf"),
        ("otf", "font/otf"), ("txt", "text/plain"), ("MJS", "text/javascript"),
        ("JpEg", "image/jpeg"), ("unknown", "application/octet-stream"), ("", "application/octet-stream")
    ])
    func mimeTypes(_ ext: String, _ expected: String) {
        #expect(SchemeResolver.mimeType(forPathExtension: ext) == expected)
    }

    static let rangeCases: [(String?, Int, RangeResult)] = [
        (nil, 100, .full), ("", 100, .full),
        ("bytes=0-0", 100, .partial(0...0)), ("bytes=10-19", 100, .partial(10...19)),
        ("bytes=90-120", 100, .partial(90...99)), ("bytes=10-", 100, .partial(10...99)),
        ("bytes=-10", 100, .partial(90...99)), ("bytes=-100", 100, .partial(0...99)),
        ("bytes=-150", 100, .partial(0...99)), ("bytes=99-", 100, .partial(99...99)),
        ("bytes=100-", 100, .unsatisfiable), ("bytes=100-101", 100, .unsatisfiable),
        ("bytes=20-10", 100, .unsatisfiable), ("bytes=-0", 100, .unsatisfiable),
        ("bytes=-", 100, .unsatisfiable), ("bytes=", 100, .unsatisfiable),
        ("items=0-1", 100, .unsatisfiable), ("bytes=a-b", 100, .unsatisfiable),
        ("bytes=0-1-2", 100, .unsatisfiable), ("bytes=+1-2", 100, .unsatisfiable),
        ("bytes=1-+2", 100, .unsatisfiable), ("bytes= 1-2", 100, .unsatisfiable),
        (" ", 100, .unsatisfiable), ("bytes=１-２", 100, .unsatisfiable),
        ("bytes=999999999999999999999999-", 100, .unsatisfiable),
        ("bytes=0-999999999999999999999999", 100, .unsatisfiable),
        ("bytes=0-1,4-5", 100, .full), ("bytes=0-1,", 100, .full),
        (nil, 0, .unsatisfiable), ("", 0, .unsatisfiable), ("bytes=0-", 0, .unsatisfiable),
        ("bytes=-10", 0, .unsatisfiable), ("bytes=0-1,2-3", 0, .unsatisfiable),
        ("bytes=0-0", 1, .partial(0...0)), (nil, -1, .unsatisfiable),
        ("bytes=-\(Int.max)", 10, .partial(0...9)),
        ("bytes=\(Int.max - 1)-", Int.max, .partial((Int.max - 1)...(Int.max - 1)))
    ]

    @Test("Range 闭区间、开放区间、后缀、非法输入、多段及空文件", arguments: rangeCases)
    func ranges(_ header: String?, _ size: Int, _ expected: RangeResult) {
        #expect(SchemeResolver.parseRange(header, fileSize: size) == expected)
    }
}
