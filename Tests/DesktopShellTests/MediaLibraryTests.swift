import Foundation
import Testing
@testable import DesktopShell

struct MediaLibraryTests {
    @Test("单层素材过滤、自然顺序、扩展名原样及同 id 去重")
    func scansImages() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        for name in ["1.png", "2.PNG", "10.png", ".hidden.png", "CREDITS.txt", "bad name.png", "a.png", "a.jpg", "B.jpeg", "c.WEBP", "noext", "emoji-爱.png"] {
            _ = try fixture.file("avatars/" + name)
        }
        _ = try fixture.directory("avatars/dir.png")
        _ = try fixture.file("avatars/nested/3.png")
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("avatars/link.png"), withDestinationURL: fixture.root.appendingPathComponent("avatars/1.png"))
        #expect(MediaLibrary.scan(mediaDir: fixture.root, subdirectory: "avatars") == [
            MediaItem(id: "1", url: "/media/avatars/1.png"),
            MediaItem(id: "2", url: "/media/avatars/2.PNG"),
            MediaItem(id: "10", url: "/media/avatars/10.png"),
            MediaItem(id: "a", url: "/media/avatars/a.jpg"),
            MediaItem(id: "B", url: "/media/avatars/B.jpeg"),
            MediaItem(id: "c", url: "/media/avatars/c.WEBP"),
        ])
    }

    @Test("每次重新扫描，后加入的背景出现在下一次结果中")
    func rescansFiles() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        #expect(MediaLibrary.scan(mediaDir: fixture.root, subdirectory: "backgrounds").isEmpty)
        _ = try fixture.file("backgrounds/bg-1.jpg")
        #expect(MediaLibrary.scan(mediaDir: fixture.root, subdirectory: "backgrounds") == [MediaItem(id: "bg-1", url: "/media/backgrounds/bg-1.jpg")])
        _ = try fixture.file("backgrounds/bg-2.png")
        #expect(MediaLibrary.scan(mediaDir: fixture.root, subdirectory: "backgrounds").map(\.id) == ["bg-1", "bg-2"])
    }

    @Test("缺失目录、普通文件和符号链接均不作为素材目录扫描")
    func invalidDirectories() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        #expect(MediaLibrary.scan(mediaDir: fixture.root, subdirectory: "missing") == [])
        _ = try fixture.file("not-directory")
        #expect(MediaLibrary.scan(mediaDir: fixture.root, subdirectory: "not-directory") == [])
        _ = try fixture.file("outside/secret.png")
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("avatars"), withDestinationURL: fixture.root.appendingPathComponent("outside"))
        #expect(MediaLibrary.scan(mediaDir: fixture.root, subdirectory: "avatars") == [])
        #expect(MediaLibrary.scan(mediaDir: fixture.root, subdirectory: "../outside") == [])
    }
}
