import Carbon
import Foundation
import Testing
@testable import DesktopShell

struct HotKeyTests {
    @Test("缺省快捷键不报错，非法配置回退但标记原因")
    func defaultsAndInvalid() {
        let fallback = HotKey.resolve(nil)
        #expect(fallback.keyCode == UInt32(kVK_ANSI_Grave))
        #expect(fallback.modifiers == UInt32(optionKey))
        #expect(fallback.display == "⌥`")
        #expect(!fallback.usedDefaultBecauseInvalid)
        for (key, modifiers) in [("t", []), ("t", ["shift"]), ("t", ["meta"]),
                                 ("t", ["option", "option"]), ("unknown", ["command"]), (" ", ["control"])] {
            let value = HotKey.resolve(.init(key: key, modifiers: modifiers))
            #expect(value.keyCode == fallback.keyCode && value.modifiers == fallback.modifiers)
            #expect(value.display == fallback.display && value.usedDefaultBecauseInvalid)
        }
    }

    @Test("键名忽略大小写和首尾空白，覆盖各类物理键码", arguments: [
        (" t \n", kVK_ANSI_T, "T"), ("0", kVK_ANSI_0, "0"), ("`", kVK_ANSI_Grave, "`"),
        ("\\", kVK_ANSI_Backslash, "\\"), ("Space", kVK_Space, "Space"),
        ("TAB", kVK_Tab, "Tab"), ("return", kVK_Return, "↩"), ("escape", kVK_Escape, "⎋"),
        ("F1", kVK_F1, "F1"), ("f12", kVK_F12, "F12")
    ])
    func keys(_ key: String, _ code: Int, _ label: String) {
        let value = HotKey.resolve(.init(key: key, modifiers: ["command"]))
        #expect(value.keyCode == UInt32(code))
        #expect(value.display == "⌘" + label)
        #expect(!value.usedDefaultBecauseInvalid)
    }

    @Test("修饰键按 control option shift command 排列，输出 Carbon 位掩码")
    func combinations() {
        let value = HotKey.resolve(.init(key: "t", modifiers: ["command", "shift", "option", "control"]))
        #expect(value.modifiers == UInt32(cmdKey | shiftKey | optionKey | controlKey))
        #expect(value.display == "⌃⌥⇧⌘T")
    }

    @Test("公开配置和推送始终提供快捷键显示文字")
    func publicConfiguration() throws {
        var config = AppConfig.example
        #expect(ConfigReply.makeConfig(config)["terminal"] as? [String: String] == ["hotkey": "⌥`"])
        config.terminal = .init(hotkey: .init(key: "t", modifiers: ["command", "shift"]))
        let value = ConfigReply.makeConfig(config)
        #expect(value["terminal"] as? [String: String] == ["hotkey": "⇧⌘T"])
        #expect(value["apps"] == nil)
        #expect((value["projects"] as? [[String: Any]])?.allSatisfy { $0["apps"] == nil } == true)
        let event = try #require(PageEvent.config(config)["config"] as? [String: Any])
        #expect(NSDictionary(dictionary: event).isEqual(to: value))
    }

    @Test("快捷键结构错误只回退快捷键，缺省字段兼容旧配置")
    func decoding() throws {
        for raw: Any in ["bad", ["hotkey": 4], ["hotkey": ["key": 1, "modifiers": ["option"]]],
                         ["hotkey": ["key": "t"]], ["hotkey": ["key": "t", "modifiers": "command"]]] {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfig.example)) as? [String: Any])
            json["terminal"] = raw
            let config = try JSONDecoder().decode(AppConfig.self, from: JSONSerialization.data(withJSONObject: json))
            #expect(config.projects == AppConfig.example.projects)
            let shortcut = HotKey.resolve(config.terminal?.hotkey)
            #expect(shortcut.usedDefaultBecauseInvalid)
        }
        for json in ["{}", "{\"hotkey\":null}"] {
            let terminal = try JSONDecoder().decode(AppConfig.Terminal.self, from: Data(json.utf8))
            #expect(!HotKey.resolve(terminal.hotkey).usedDefaultBecauseInvalid)
        }
    }

    @Test("旧动作拒绝且编辑不能指定已移除的应用参数")
    func removedActions() {
        // Assemble legacy protocol names so the retired-symbol scan stays useful.
        for action in ["launch" + "App", "openProject" + "With"] {
            #expect(BridgeRequest.parse(["action": action]) == .failure(.unknownAction))
        }
        #expect(BridgeRequest.parse(["action": "updateProject", "projectId": "p", "app" + "Id": "editor"]) == .failure(.invalid))
    }
}
