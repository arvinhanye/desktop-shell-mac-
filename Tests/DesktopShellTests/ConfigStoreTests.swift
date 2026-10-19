import Foundation
import Testing
@testable import DesktopShell

struct ConfigStoreTests {
    @Test("新增称呼和签名读取后保留，旧文件不补字段也不重写")
    func userAndMottoCompatibility() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        for value: String? in [nil, "", " \n", "  测试文本  "] {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfig.example)) as? [String: Any])
            json["user"] = value.map { ["name": $0] }
            json["character"] = ["name": "爱弥斯", "motto": value].compactMapValues { $0 }
            let data = try JSONSerialization.data(withJSONObject: json)
            let file = fixture.root.appendingPathComponent("config.json")
            try data.write(to: file)
            let loaded = try ConfigStore(supportDir: fixture.root).load()
            let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any])
            #expect((encoded["user"] as? [String: String])?["name"] == value)
            #expect((encoded["character"] as? [String: String])?["motto"] == value)
            #expect(try Data(contentsOf: file) == data)
        }
    }

    @Test("首次示例包含称呼和签名且编码往返不变")
    func exampleNewFields() throws {
        let data = try JSONEncoder().encode(AppConfig.example)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["user"] as? [String: String])?["name"] == "Arvin")
        #expect((json["character"] as? [String: String])?["motto"] == "愿星光一直落在你走的路上")
        #expect(try JSONDecoder().decode(AppConfig.self, from: data) == AppConfig.example)
    }

    @Test("首次加载创建完整示例配置，中文直接可读")
    func createsExample() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let support = fixture.root.appendingPathComponent("nested/support", isDirectory: true)
        let config = try ConfigStore(supportDir: support).load()
        let file = support.appendingPathComponent("config.json")
        #expect(config == AppConfig.example)
        try #require(FileManager.default.fileExists(atPath: file.path))
        let data = try Data(contentsOf: file)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("爱弥斯"))
        #expect(!text.contains("\\u"))
        #expect(!text.contains("\\/"))
        #expect(text.contains("\n"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        #expect(data == (try encoder.encode(AppConfig.example)))
        #expect(try ConfigStore(supportDir: support).load() == config)
    }

    @Test("示例字段、七段问候与规范一致")
    func exampleContents() {
        let config = AppConfig.example
        #expect(config.background.video == "video/aemeath.mp4")
        #expect(config.character.name == "爱弥斯")
        #expect(config.greetings.map(\.from) == [0, 6, 12, 18, 20, 21, 23])
        #expect(config.greetings.map(\.title) == ["深夜了", "早上好", "下午好", "傍晚了", "晚上好", "晚上好", "深夜了"])
        #expect(config.greetings.map(\.wish) == [
            "时辰已晚，且捻熄灯盏，良宵安枕", "晨光熹微，愿您涤尽尘扰，理裳启新日",
            "愿清风伴您今日，时刻皆有阳光满心", "且舒怀抱，自在一刻尽欢愉",
            "且舒怀抱，自在一刻尽欢愉", "时辰已晚，且捻熄灯盏，良宵安枕", "时辰已晚，且捻熄灯盏，良宵安枕"
        ])
        #expect(config.projects.count == 1)
        #expect(config.projects.first?.id == "desktop-shell")
        #expect(config.projects.first?.name == "DesktopShell")
        #expect(config.projects.first?.path == "~/Desktop/desktop-shell")
        #expect(config.projects.first?.tags == ["dev"])
        #expect(config.projects.first?.apps == ["cursor"])
        #expect(config.apps.map(\.id) == ["cursor", "safari"])
        #expect(config.apps.map(\.name) == ["Cursor", "Safari"])
        #expect(config.apps.map(\.bundleId) == ["com.todesktop.230313mzl4w4u92", "com.apple.Safari"])
    }

    @Test("已有合法配置保持内容和文件原样，项目可省略 tags/apps")
    func readsExistingConfig() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let json = """
        {"background":{"video":"video/custom.mp4"},"character":{"name":"测试角色"},
         "greetings":[{"from":8,"title":"你好","wish":"测试祝福"}],
         "projects":[{"id":"p_1","name":"项目一","path":"~/project with spaces"}],
         "apps":[{"id":"editor-2","name":"编辑器","bundleId":"test.editor"}]}
        """
        let file = try fixture.file("config.json", contents: json)
        let before = try Data(contentsOf: file)
        let config = try ConfigStore(supportDir: fixture.root).load()
        #expect(config.background.video == "video/custom.mp4")
        #expect(config.character.name == "测试角色")
        #expect(config.greetings.first?.wish == "测试祝福")
        #expect(config.projects.first?.path == "~/project with spaces")
        #expect(config.projects.first?.tags == nil)
        #expect(config.projects.first?.apps == nil)
        #expect(config.apps.first?.bundleId == "test.editor")
        #expect(try Data(contentsOf: file) == before)
        #expect(try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config)) == config)
    }

    @Test("损坏或结构错误的 JSON 抛错且保留原始内容", arguments: ["{broken", "{}", "[]", "null"])
    func preservesInvalidJSON(_ json: String) throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let file = try fixture.file("config.json", contents: json)
        #expect(throws: (any Error).self) { try ConfigStore(supportDir: fixture.root).load() }
        #expect(try Data(contentsOf: file) == Data(json.utf8))
    }

    @Test("提醒列表字段可选且读取后保留，不重写旧配置")
    func remindersListCompatibility() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        for list: String? in [nil, "", "  ", "项目提醒"] {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfig.example)) as? [String: Any])
            var projects = try #require(json["projects"] as? [[String: Any]])
            projects[0]["remindersList"] = list
            json["projects"] = projects
            let data = try JSONSerialization.data(withJSONObject: json)
            let file = fixture.root.appendingPathComponent("config.json")
            try data.write(to: file)
            let loaded = try ConfigStore(supportDir: fixture.root).load()
            let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any])
            let decodedProjects = try #require(encoded["projects"] as? [[String: Any]])
            #expect(decodedProjects[0]["remindersList"] as? String == list)
            #expect(try Data(contentsOf: file) == data)
        }
        let example = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfig.example)) as? [String: Any])
        let projects = try #require(example["projects"] as? [[String: Any]])
        #expect(projects[0]["remindersList"] == nil)
    }

    @Test("目录占用 config.json 时抛错，不替换目录")
    func preservesNonFileConfig() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let directory = try fixture.directory("config.json")
        let marker = try fixture.file("config.json/keep.txt", contents: "keep")
        #expect(throws: (any Error).self) { try ConfigStore(supportDir: fixture.root).load() }
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(try String(contentsOf: marker, encoding: .utf8) == "keep")
    }

    @Test("支持目录被文件占用时传播写入错误")
    func creationFailure() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let file = try fixture.file("support", contents: "keep")
        #expect(throws: (any Error).self) { try ConfigStore(supportDir: file).load() }
        #expect(try String(contentsOf: file, encoding: .utf8) == "keep")
    }

    @Test("非法项目和应用 id 被过滤，问候过滤并排序但不重写文件")
    func sanitizesConfig() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let json = """
        {"background":{"video":"video/aemeath.mp4"},"character":{"name":"爱弥斯"},
         "greetings":[{"from":20,"title":"夜","wish":"夜"},{"from":24,"title":"丢弃","wish":"丢弃"},
                      {"from":6,"title":"早","wish":"早"},{"from":-1,"title":"丢弃","wish":"丢弃"},
                      {"from":0,"title":"零","wish":"零"},{"from":23,"title":"晚","wish":"晚"}],
         "projects":[{"id":"../x","name":"bad","path":"/tmp"},{"id":"a b","name":"bad","path":"/tmp"},
                     {"id":"","name":"bad","path":"/tmp"},{"id":"Good_1-x","name":"ok","path":"~/ok","tags":["dev"],"apps":["ok"]}],
         "apps":[{"id":"../x","name":"bad","bundleId":"bad"},{"id":"a b","name":"bad","bundleId":"bad"},
                 {"id":"","name":"bad","bundleId":"bad"},{"id":"ok","name":"ok","bundleId":"test.ok"}]}
        """
        let file = try fixture.file("config.json", contents: json)
        let config = try ConfigStore(supportDir: fixture.root).load()
        #expect(config.projects.map(\.id) == ["Good_1-x"])
        #expect(config.projects.first?.tags == ["dev"])
        #expect(config.projects.first?.apps == ["ok"])
        #expect(config.apps.map(\.id) == ["ok"])
        #expect(config.greetings.map(\.from) == [0, 6, 20, 23])
        #expect(config.greetings.map(\.title) == ["零", "早", "夜", "晚"])
        #expect(try Data(contentsOf: file) == Data(json.utf8))
    }

    @Test("id 仅接受非空 ASCII 字母数字下划线连字符", arguments: [
        ("a", true), ("AZaz09_-", true), ("0", true), ("_", true), ("-", true),
        ("", false), ("../x", false), ("a b", false), ("a.b", false), ("你好", false),
        ("é", false), ("a\n", false), ("a\0b", false), ("a/b", false), ("a\\b", false)
    ])
    func validatesIDs(_ value: String, _ expected: Bool) {
        #expect(isValidID(value) == expected)
    }
}
