import Foundation
import Testing
@testable import DesktopShell

struct UiStateStoreTests {
    @Test("缺失文件返回默认值，读取不创建目录或文件")
    func missingFile() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let support = fixture.root.appendingPathComponent("missing/support")
        let state = UiStateStore(supportDir: support).load()
        #expect(state.avatarId == nil && state.backgroundId == nil)
        #expect(state.voiceEnabled && !state.desktopIconsHidden)
        #expect(!FileManager.default.fileExists(atPath: support.path))
    }

    @Test("四个字段读写往返并支持覆盖已有状态")
    func roundTrip() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let store = UiStateStore(supportDir: fixture.root)
        let state = UiState(avatarId: "12", backgroundId: "cover", voiceEnabled: false, desktopIconsHidden: true)
        try store.save(state)
        #expect(store.load() == state)
        try store.save(UiState())
        #expect(store.load() == UiState())
    }

    @Test("缺少字段时各自使用默认值", arguments: [
        ("{}", UiState()),
        (#"{"desktopIconsHidden":true}"#, UiState(desktopIconsHidden: true)),
        (#"{"voiceEnabled":false}"#, UiState(voiceEnabled: false)),
        (#"{"avatarId":"12"}"#, UiState(avatarId: "12")),
        (#"{"backgroundId":"cover"}"#, UiState(backgroundId: "cover"))
    ])
    func missingFields(_ json: String, _ expected: UiState) throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        _ = try fixture.file("ui.json", contents: json)
        #expect(UiStateStore(supportDir: fixture.root).load() == expected)
    }

    @Test("null字段按decodeIfPresent的默认值处理")
    func nullFields() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        _ = try fixture.file("ui.json", contents: #"{"avatarId":null,"backgroundId":null,"voiceEnabled":null,"desktopIconsHidden":null}"#)
        #expect(UiStateStore(supportDir: fixture.root).load() == UiState())
    }

    @Test("多余字段忽略，读取不重写原始文件")
    func ignoresExtraFields() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let json = #"{"desktopIconsHidden":true,"future":{"value":123}}"#
        let file = try fixture.file("ui.json", contents: json)
        #expect(UiStateStore(supportDir: fixture.root).load() == UiState(desktopIconsHidden: true))
        #expect(try Data(contentsOf: file) == Data(json.utf8))
    }

    @Test("损坏或字段类型错误时整份回退默认值并保留原文", arguments: [
        "{broken", "[]", "null", #"{"desktopIconsHidden":"true"}"#,
        #"{"voiceEnabled":1,"desktopIconsHidden":true}"#, #"{"avatarId":12}"#,
        #"{"backgroundId":false}"#
    ])
    func invalidJSON(_ json: String) throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let file = try fixture.file("ui.json", contents: json)
        #expect(UiStateStore(supportDir: fixture.root).load() == UiState())
        #expect(try Data(contentsOf: file) == Data(json.utf8))
    }

    @Test("保存自动创建多层支持目录")
    func createsDirectory() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let support = fixture.root.appendingPathComponent("new/nested/support")
        let store = UiStateStore(supportDir: support)
        try store.save(UiState(desktopIconsHidden: true))
        #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("ui.json").path))
        #expect(store.load().desktopIconsHidden)
    }

    @Test("输出格式化JSON且键名排序")
    func formattedOutput() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        try UiStateStore(supportDir: fixture.root).save(UiState(avatarId: "a", backgroundId: "b", voiceEnabled: false, desktopIconsHidden: true))
        let text = try String(contentsOf: fixture.root.appendingPathComponent("ui.json"), encoding: .utf8)
        let keys = text.split(separator: "\n").filter { $0.contains(":") }.map { String($0.split(separator: "\"")[1]) }
        #expect(keys == ["avatarId", "backgroundId", "desktopIconsHidden", "voiceEnabled"])
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["desktopIconsHidden"] as? Bool == true)
        #expect(object["voiceEnabled"] as? Bool == false)
    }

    @Test("支持目录被文件占用时保存抛错且不破坏该文件")
    func invalidSupportDirectory() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let file = try fixture.file("support", contents: "keep")
        #expect(throws: (any Error).self) { try UiStateStore(supportDir: file).save(UiState()) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "keep")
    }

    @Test("ui.json被目录占用时读取回退且保存抛错")
    func invalidFileDestination() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        _ = try fixture.directory("ui.json")
        let marker = try fixture.file("ui.json/keep.txt", contents: "keep")
        let store = UiStateStore(supportDir: fixture.root)
        #expect(store.load() == UiState())
        #expect(throws: (any Error).self) { try store.save(UiState(desktopIconsHidden: true)) }
        #expect(try String(contentsOf: marker, encoding: .utf8) == "keep")
    }
}
