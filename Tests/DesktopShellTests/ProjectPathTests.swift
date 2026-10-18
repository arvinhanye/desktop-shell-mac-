import Foundation
import Testing
@testable import DesktopShell

struct ProjectPathTests {
    private let home = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)

    @Test("项目路径展开当前 home 或保留绝对路径，标准化但不检查存在性")
    func resolvesSupportedForms() {
        for (input, expected) in [
            ("~", "/Users/fixture"), ("~/", "/Users/fixture"),
            ("~/x/y", "/Users/fixture/x/y"), ("~/x/../y", "/Users/fixture/y"),
            ("/", "/"), ("/tmp/a/../b/./", "/tmp/b"),
            ("/missing/项目 with spaces", "/missing/项目 with spaces"),
            ("~/literal%20name", "/Users/fixture/literal%20name"),
        ] {
            let result = ProjectPath.resolve(input, home: home)
            #expect(result?.isFileURL == true)
            #expect(result?.path == expected)
        }
    }

    @Test("项目路径拒绝相对路径、其他用户 home 和 URL 字符串")
    func rejectsUnsupportedForms() {
        for path in ["", " ", "x/y", "./x", "../x", "~user/x", "~user", " ~", " ~/x", "file:///tmp/x", "https://example.invalid"] {
            #expect(ProjectPath.resolve(path, home: home) == nil)
        }
    }
}
