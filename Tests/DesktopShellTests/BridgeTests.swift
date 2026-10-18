import Foundation
import Testing
@testable import DesktopShell

struct BridgeTests {
    @Test("导航仅新增 shell://app 发起的精确 srcdoc 子框架例外")
    func srcdocNavigation() {
        let url = URL(string: "about:srcdoc")!
        #expect(WebNavigationPolicy.allows(url: url, targetIsMainFrame: false, sourceScheme: "shell", sourceHost: "app"))
        for mainFrame: Bool? in [true, nil] {
            #expect(!WebNavigationPolicy.allows(url: url, targetIsMainFrame: mainFrame, sourceScheme: "shell", sourceHost: "app"))
        }
        for scheme in ["http", "https", "file", "about", "SHELL", ""] {
            #expect(!WebNavigationPolicy.allows(url: url, targetIsMainFrame: false, sourceScheme: scheme, sourceHost: "app"))
        }
        for host in ["evil", "", "APP", "app.evil"] {
            #expect(!WebNavigationPolicy.allows(url: url, targetIsMainFrame: false, sourceScheme: "shell", sourceHost: host))
        }
    }

    @Test("导航保留原有 shell 规则，拒绝其他 about、外部及缺失 URL")
    func otherNavigation() {
        for mainFrame: Bool? in [true, false, nil] {
            for address in ["shell://app/index.html", "shell://app/media/avatars/1.png", "shell://evil/index.html"] {
                #expect(WebNavigationPolicy.allows(url: URL(string: address), targetIsMainFrame: mainFrame, sourceScheme: "", sourceHost: ""))
            }
            for address in ["about:blank", "about:srcdoc#x", "about:srcdoc?x", "about:SRCDOC", "ABOUT:srcdoc", "data:text/html,test", "https://example.invalid", "http://example.invalid", "file:///tmp/test.html"] {
                #expect(!WebNavigationPolicy.allows(url: URL(string: address), targetIsMainFrame: mainFrame, sourceScheme: "shell", sourceHost: "app"))
            }
            #expect(!WebNavigationPolicy.allows(url: nil, targetIsMainFrame: mainFrame, sourceScheme: "shell", sourceHost: "app"))
        }
    }

    @Test("来源仅接受大小写精确的 shell://app 主框架")
    func trustedOrigin() {
        #expect(BridgeOrigin.isTrusted(isMainFrame: true, scheme: "shell", host: "app"))
        #expect(!BridgeOrigin.isTrusted(isMainFrame: false, scheme: "shell", host: "app"))
        for scheme in ["http", "https", "file", "about", "SHELL", "", "shell:"] {
            #expect(!BridgeOrigin.isTrusted(isMainFrame: true, scheme: scheme, host: "app"))
        }
        for host in ["evil", "", "APP", "app.evil", "app "] {
            #expect(!BridgeOrigin.isTrusted(isMainFrame: true, scheme: "shell", host: host))
        }
    }

    @Test("非字典或缺少字符串 action 返回 invalid")
    func malformedRequests() {
        for body: Any in [NSNull(), "getConfig", 1, [], [:] as [String: Any],
                          ["action": 42], ["action": true], ["action": NSNull()]] {
            #expect(BridgeRequest.parse(body) == .failure(.invalid))
        }
    }

    @Test("未知与尚未实现的动作始终返回 unknown-action")
    func unimplementedActions() {
        for action in ["deleteFile", "", "GETCONFIG", "openProject", "openProjectWith", "launchApp",
                       "saveUiState", "addTodo", "setTodoDone", "focusInput", "blurInput"] {
            #expect(BridgeRequest.parse(["action": action]) == .failure(.unknownAction))
            #expect(BridgeRequest.parse(["action": action, "path": "/private"]) == .failure(.unknownAction))
        }
    }

    @Test("已实现动作只接受声明过的参数")
    func exactKeys() {
        #expect(BridgeRequest.parse(["action": "getConfig"]) == .success(.getConfig))
        #expect(BridgeRequest.parse(["action": "getConfig", "extra": NSNull()]) == .failure(.invalid))
        #expect(BridgeRequest.parse(["action": "setHitRegions"]) == .failure(.invalid))
        #expect(BridgeRequest.parse(["action": "setHitRegions", "regions": [], "extra": 1]) == .failure(.invalid))
    }

    @Test("点击区域解析保留原始数值供真实视口裁剪，接受 WK 桥接字典")
    func validRegions() throws {
        let body: NSDictionary = ["action": "setHitRegions", "regions": [[-10, -20, 40, 50], [0.5, 1.5, 2.5, 3.5]]]
        #expect(BridgeRequest.parse(body) == .success(.setHitRegions([[-10, -20, 40, 50], [0.5, 1.5, 2.5, 3.5]])))
        #expect(BridgeRequest.parse(["action": "setHitRegions", "regions": []]) == .success(.setHitRegions([])))
        let many = Array(repeating: [1.0, 2, 3, 4], count: 64)
        #expect(BridgeRequest.parse(["action": "setHitRegions", "regions": many]) == .success(.setHitRegions(many)))
    }

    @Test("点击区域沿用 HitTesting 校验，拒绝布尔、非有限值、非法形状及超量")
    func invalidRegions() {
        let invalid: [Any] = [NSNull(), 1, "[]", ["x": 1], [1, 2, 3, 4], [[1, 2, 3]],
            [[1, 2, 3, 4, 5]], [[true, 2, 3, 4]], [["1", 2, 3, 4]], [[1, 2, 0, 4]],
            [[1, 2, 3, -1]], [[Double.nan, 2, 3, 4]], [[1, Double.infinity, 3, 4]],
            [[1, 2, -Double.infinity, 4]], Array(repeating: [1, 2, 3, 4], count: 65)]
        for regions in invalid {
            #expect(BridgeRequest.parse(["action": "setHitRegions", "regions": regions]) == .failure(.invalid))
        }
    }

    @Test("getConfig 回复可序列化且只含公开字段")
    func publicReply() throws {
        var config = AppConfig.example
        config.projects[0].remindersList = "私有列表名"
        let ui = UiState(avatarId: "2", backgroundId: "bg-1", voiceEnabled: false, desktopIconsHidden: true)
        let reply = ConfigReply.make(config: config,
            avatars: [MediaItem(id: "2", url: "/media/avatars/2.PNG")],
            backgrounds: [MediaItem(id: "bg-1", url: "/media/backgrounds/bg-1.jpg")], uiState: ui)
        #expect(JSONSerialization.isValidJSONObject(reply))
        let decoded = try #require(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: reply)) as? [String: Any])
        #expect(Set(decoded.keys) == ["config", "media", "uiState"])
        let publicConfig = try #require(decoded["config"] as? [String: Any])
        #expect(Set(publicConfig.keys) == ["character", "greetings", "projects", "apps"])
        #expect((publicConfig["character"] as? [String: String]) == ["name": "爱弥斯"])
        let greetings = try #require(publicConfig["greetings"] as? [[String: Any]])
        #expect(greetings.count == 7)
        #expect(greetings[0]["from"] as? Int == 0)
        #expect(greetings[0]["title"] as? String == "深夜了")
        #expect(greetings[0]["wish"] as? String == "时辰已晚，且捻熄灯盏，良宵安枕")
        let projects = try #require(publicConfig["projects"] as? [[String: Any]])
        #expect(projects[0]["id"] as? String == "desktop-shell")
        #expect(projects[0]["name"] as? String == "DesktopShell")
        #expect(projects[0]["tags"] as? [String] == ["dev"])
        #expect(projects[0]["apps"] as? [String] == ["cursor"])
        #expect(projects[0]["hasReminders"] as? Bool == true)
        #expect(publicConfig["apps"] as? [[String: String]] == [["id": "cursor", "name": "Cursor"], ["id": "safari", "name": "Safari"]])
        let media = try #require(decoded["media"] as? [String: [[String: String]]])
        #expect(media["avatars"] == [["id": "2", "url": "/media/avatars/2.PNG"]])
        #expect(media["backgrounds"] == [["id": "bg-1", "url": "/media/backgrounds/bg-1.jpg"]])
        let publicUI = try #require(decoded["uiState"] as? [String: Any])
        #expect(publicUI["avatarId"] as? String == "2")
        #expect(publicUI["backgroundId"] as? String == "bg-1")
        #expect(publicUI["voiceEnabled"] as? Bool == false)
        let privateKeys: Set<String> = ["path", "remindersList", "bundleId", "background", "video", "desktopIconsHidden", "todos"]
        #expect(allKeys(decoded).isDisjoint(with: privateKeys))
    }

    @Test("缺省数组、空外观及列表名去空白后的 hasReminders")
    func replyDefaults() throws {
        for (list, expected): (String?, Bool) in [(nil, false), ("", false), (" \t\r\n", false), (" 项目提醒\n", true)] {
            var config = AppConfig.example
            config.projects[0].tags = nil
            config.projects[0].apps = nil
            config.projects[0].remindersList = list
            let reply = ConfigReply.make(config: config, avatars: [], backgrounds: [], uiState: UiState())
            let publicConfig = try #require(reply["config"] as? [String: Any])
            let projects = try #require(publicConfig["projects"] as? [[String: Any]])
            #expect(projects[0]["tags"] as? [String] == [])
            #expect(projects[0]["apps"] as? [String] == [])
            #expect(projects[0]["hasReminders"] as? Bool == expected)
            let ui = try #require(reply["uiState"] as? [String: Any])
            #expect(ui["avatarId"] == nil || ui["avatarId"] is NSNull)
            #expect(ui["backgroundId"] == nil || ui["backgroundId"] is NSNull)
            #expect(ui["voiceEnabled"] as? Bool == true)
        }
    }

    @MainActor @Test("共享状态读取并保存当前外观，隐藏图标不覆盖其他字段")
    func sharedStatePersistence() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        var config = AppConfig.example
        config.character.name = "fixture"
        try JSONEncoder().encode(config).write(to: fixture.root.appendingPathComponent("config.json"))
        try UiStateStore(supportDir: fixture.root).save(UiState(avatarId: "1", backgroundId: "bg", voiceEnabled: false))
        let paths = AppPaths(supportDir: fixture.root, mediaDir: fixture.root.appendingPathComponent("media"), webDir: fixture.root.appendingPathComponent("web"))
        let state = AppState(paths: paths)
        #expect(state.paths == paths)
        #expect(state.config == config)
        state.uiState.avatarId = "2"
        state.uiState.desktopIconsHidden.toggle()
        try state.saveUiState()
        let restarted = AppState(paths: paths)
        #expect(restarted.uiState == UiState(avatarId: "2", backgroundId: "bg", voiceEnabled: false, desktopIconsHidden: true))
    }

    @MainActor @Test("配置损坏时保留文件并回退示例，外观仍照常读取")
    func sharedStateFallback() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        let file = try fixture.file("config.json", contents: "{broken")
        try UiStateStore(supportDir: fixture.root).save(UiState(voiceEnabled: false, desktopIconsHidden: true))
        let state = AppState(paths: AppPaths(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root))
        #expect(state.config == AppConfig.example)
        #expect(state.uiState.voiceEnabled == false)
        #expect(state.uiState.desktopIconsHidden == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == "{broken")
    }

    @MainActor @Test("保存失败抛错但保留当前内存选择")
    func sharedStateSaveFailure() throws {
        let fixture = try TemporaryTestDirectory()
        defer { fixture.cleanup() }
        _ = try fixture.directory("ui.json")
        let state = AppState(paths: AppPaths(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root))
        state.uiState.desktopIconsHidden = true
        #expect(throws: (any Error).self) { try state.saveUiState() }
        #expect(state.uiState.desktopIconsHidden)
    }

    private func allKeys(_ value: Any) -> Set<String> {
        if let object = value as? [String: Any] {
            return object.values.reduce(into: Set(object.keys)) { $0.formUnion(allKeys($1)) }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { $0.formUnion(allKeys($1)) }
        }
        return []
    }
}
