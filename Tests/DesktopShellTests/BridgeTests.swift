import Foundation
import Testing
@testable import DesktopShell

struct BridgeTests {
    @Test("getConfig 新字段去空白且保留 null 键，仅使用最近成功的图标 id")
    func newPublicFields() throws {
        for value: String? in [nil, "", " \t\n", " Arvin \n"] {
            var config = AppConfig.example
            config.user = value.map { .init(name: $0) }
            config.character.motto = value
            let reply = ConfigReply.make(config: config, avatars: [], backgrounds: [],
                voices: [MediaItem(id: "1", url: "/media/voice/1.mp3")],
                iconIDs: ["cursor", "not-configured"], uiState: UiState())
            #expect(JSONSerialization.isValidJSONObject(reply))
            let publicConfig = try #require(reply["config"] as? [String: Any])
            let user = try #require(publicConfig["user"] as? [String: Any])
            let character = try #require(publicConfig["character"] as? [String: Any])
            if value == " Arvin \n" {
                #expect(user["name"] as? String == "Arvin")
                #expect(character["motto"] as? String == "Arvin")
            } else {
                #expect(user["name"] is NSNull)
                #expect(character["motto"] is NSNull)
            }
            let apps = try #require(publicConfig["apps"] as? [[String: Any]])
            #expect(apps.count == 2)
            #expect(apps[0]["iconUrl"] as? String == "/media/app-icons/cursor.png")
            #expect(apps[1]["iconUrl"] is NSNull)
            let media = try #require(reply["media"] as? [String: [[String: String]]])
            #expect(media["voices"] == [["id": "1", "url": "/media/voice/1.mp3"]])
            #expect(allKeys(reply).isDisjoint(with: ["path", "bundleId", "remindersList", "background"]))
        }
    }

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
        for action in ["deleteFile", "", "GETCONFIG"] {
            #expect(BridgeRequest.parse(["action": action]) == .failure(.unknownAction))
            #expect(BridgeRequest.parse(["action": action, "path": "/private"]) == .failure(.unknownAction))
        }
    }

    @Test("焦点动作接受无参数请求并解析为独立动作")
    func keyboardFocusRequests() {
        for action in ["focusInput", "blurInput"] {
            switch BridgeRequest.parse(["action": action]) {
            case .success(let request): #expect(String(describing: request) == action)
            case .failure(let error): Issue.record("\(action) rejected: \(error.rawValue)")
            }
        }
    }

    @Test("焦点动作拒绝任何多余参数，包含 null 和空字符串")
    func keyboardFocusRejectsExtraKeys() {
        for action in ["focusInput", "blurInput"] {
            for value: Any in [NSNull(), "", true, 0, []] {
                #expect(BridgeRequest.parse(["action": action, "extra": value]) == .failure(.invalid))
            }
        }
    }

    @Test("四个新动作识别合法请求，不再作为延期动作")
    func actionRequestsRecognized() {
        let bodies: [[String: Any]] = [
            ["action": "openProject", "projectId": "p-1"],
            ["action": "openProjectWith", "projectId": "p-1", "appId": "app_2"],
            ["action": "launchApp", "appId": "app_2"],
            ["action": "saveUiState", "avatarId": "1"],
            ["action": "saveUiState", "backgroundId": "bg"],
            ["action": "saveUiState", "avatarId": NSNull(), "backgroundId": NSNull()],
        ]
        for body in bodies {
            if case .failure(let error) = BridgeRequest.parse(body) {
                Issue.record("合法动作被拒绝：\(body["action"]!) / \(error)")
            }
        }
    }

    @Test("新动作拒绝缺失、错误类型、非法 id 和额外参数")
    func actionRequestValidation() {
        let required = [("openProject", ["projectId"]), ("openProjectWith", ["projectId", "appId"]), ("launchApp", ["appId"])]
        let invalidIDs: [Any] = [NSNull(), 1, true, ["x"], ["id": "x"], "", "../etc", "a b", "a/b", "中文", "x.y"]
        for (action, keys) in required {
            var valid: [String: Any] = ["action": action]
            for key in keys { valid[key] = "valid-id_1" }
            for key in keys {
                var missing = valid; missing.removeValue(forKey: key)
                #expect(BridgeRequest.parse(missing) == .failure(.invalid))
                for value in invalidIDs {
                    var body = valid; body[key] = value
                    #expect(BridgeRequest.parse(body) == .failure(.invalid))
                }
            }
            for key in ["path", "bundleId", "url", "extra"] {
                var body = valid; body[key] = NSNull()
                #expect(BridgeRequest.parse(body) == .failure(.invalid))
            }
        }
        #expect(BridgeRequest.parse(["action": "saveUiState"]) == .failure(.invalid))
        for key in ["avatarId", "backgroundId"] {
            for value in invalidIDs where !(value is NSNull) {
                #expect(BridgeRequest.parse(["action": "saveUiState", key: value]) == .failure(.invalid))
            }
        }
        for key in ["voiceEnabled", "desktopIconsHidden", "path", "url"] {
            #expect(BridgeRequest.parse(["action": "saveUiState", "avatarId": "1", key: true]) == .failure(.invalid))
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
        #expect(Set(publicConfig.keys) == ["user", "character", "greetings", "projects", "apps"])
        #expect((publicConfig["character"] as? [String: String]) == ["name": "爱弥斯", "motto": "愿星光一直落在你走的路上"])
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
        let apps = try #require(publicConfig["apps"] as? [[String: Any]])
        #expect(apps.map { $0["id"] as? String } == ["cursor", "safari"])
        #expect(apps.map { $0["name"] as? String } == ["Cursor", "Safari"])
        #expect(apps.allSatisfy { $0["iconUrl"] is NSNull })
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

    @Test("解析保留动作 id 与外观缺失、null、set 三种语义")
    func actionPayloads() {
        #expect(BridgeRequest.parse(["action": "openProject", "projectId": "p"]) == .success(.openProject("p")))
        #expect(BridgeRequest.parse(["action": "openProjectWith", "projectId": "p", "appId": "a"]) == .success(.openProjectWith(projectId: "p", appId: "a")))
        #expect(BridgeRequest.parse(["action": "launchApp", "appId": "a"]) == .success(.launchApp("a")))
        #expect(BridgeRequest.parse(["action": "saveUiState", "avatarId": "1"]) == .success(.saveUiState(avatar: .set("1"), background: .unchanged)))
        #expect(BridgeRequest.parse(["action": "saveUiState", "backgroundId": NSNull()]) == .success(.saveUiState(avatar: .unchanged, background: .clear)))
        #expect(BridgeRequest.parse(["action": "saveUiState", "avatarId": NSNull(), "backgroundId": "bg"]) == .success(.saveUiState(avatar: .clear, background: .set("bg"))))
        #expect(BridgeRequest.parse(["action": "saveUiState", "avatarId": "1", "backgroundId": NSNull()]) == .success(.saveUiState(avatar: .set("1"), background: .clear)))
    }

    @Test("外观更新只修改请求的字段并保留两个菜单开关")
    func appearanceUpdates() {
        let state = UiState(avatarId: "old", backgroundId: "old-bg", voiceEnabled: false, desktopIconsHidden: true)
        let avatars = [MediaItem(id: "1", url: "/media/avatars/1.png")]
        let backgrounds = [MediaItem(id: "bg", url: "/media/backgrounds/bg.jpg")]
        let cases: [(UiPatch, UiPatch, String?, String?)] = [
            (.set("1"), .unchanged, "1", "old-bg"),
            (.unchanged, .set("bg"), "old", "bg"),
            (.clear, .unchanged, nil, "old-bg"),
            (.unchanged, .clear, "old", nil),
            (.clear, .clear, nil, nil),
            (.set("1"), .set("bg"), "1", "bg"),
        ]
        for (avatar, background, expectedAvatar, expectedBackground) in cases {
            #expect(UiStateUpdate.apply(to: state, avatar: avatar, background: background, avatars: avatars, backgrounds: backgrounds)
                == .success(UiState(avatarId: expectedAvatar, backgroundId: expectedBackground, voiceEnabled: false, desktopIconsHidden: true)))
        }
    }

    @Test("外观更新拒绝空补丁、非法 id、错类别和缺失素材")
    func appearanceValidation() {
        let state = UiState()
        let avatars = [MediaItem(id: "1", url: "/media/avatars/1.png")]
        let backgrounds = [MediaItem(id: "bg", url: "/media/backgrounds/bg.jpg")]
        let cases: [(UiPatch, UiPatch, BridgeError)] = [
            (.unchanged, .unchanged, .invalid),
            (.set(""), .unchanged, .invalid), (.unchanged, .set("../bg"), .invalid),
            (.set("a b"), .set("bg"), .invalid), (.set("missing"), .set("bad/id"), .invalid),
            (.set("missing"), .unchanged, .notFound), (.unchanged, .set("missing"), .notFound),
            (.set("bg"), .unchanged, .notFound), (.unchanged, .set("1"), .notFound),
        ]
        for (avatar, background, expected) in cases {
            #expect(UiStateUpdate.apply(to: state, avatar: avatar, background: background, avatars: avatars, backgrounds: backgrounds) == .failure(expected))
        }
    }

    @MainActor @Test("外观保存实时扫描素材、持久化且返回值与内存一致")
    func appearancePersistence() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let paths = AppPaths(supportDir: fixture.root, mediaDir: fixture.root.appendingPathComponent("media"), webDir: fixture.root)
        let state = AppState(paths: paths)
        state.uiState = UiState(voiceEnabled: false, desktopIconsHidden: true)
        #expect(state.updateAppearance(avatar: .set("1"), background: .unchanged) == .failure(.notFound))
        _ = try fixture.file("media/avatars/1.png")
        _ = try fixture.file("media/backgrounds/bg.jpg")
        let expected = UiState(avatarId: "1", backgroundId: "bg", voiceEnabled: false, desktopIconsHidden: true)
        #expect(state.updateAppearance(avatar: .set("1"), background: .set("bg")) == .success(expected))
        #expect(state.uiState == expected)
        #expect(UiStateStore(supportDir: fixture.root).load() == expected)
        let saved = try Data(contentsOf: fixture.root.appendingPathComponent("ui.json"))
        #expect(state.updateAppearance(avatar: .clear, background: .set("missing")) == .failure(.notFound))
        #expect(state.uiState == expected)
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent("ui.json")) == saved)
        #expect(state.updateAppearance(avatar: .clear, background: .clear) == .success(UiState(voiceEnabled: false, desktopIconsHidden: true)))
        #expect(AppState(paths: paths).uiState == UiState(voiceEnabled: false, desktopIconsHidden: true))
    }

    @MainActor @Test("写入失败时外观恢复修改前的全部状态，保留原有文件障碍")
    func appearanceSaveRollback() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        _ = try fixture.file("media/avatars/1.png")
        let state = AppState(paths: AppPaths(supportDir: fixture.root, mediaDir: fixture.root.appendingPathComponent("media"), webDir: fixture.root))
        let before = UiState(avatarId: "old", backgroundId: "old-bg", voiceEnabled: false, desktopIconsHidden: true)
        state.uiState = before
        let sentinel = try fixture.file("ui.json/sentinel", contents: "preserved")
        #expect(state.updateAppearance(avatar: .set("1"), background: .clear) == .failure(.failed))
        #expect(state.uiState == before)
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "preserved")
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


extension BridgeTests {
    @Test("提醒新增按 Character 校验并修剪标题，允许缺省或 null 项目")
    func addTodoParsing() {
        for project: Any? in [nil, NSNull(), "project-1"] {
            var body: [String: Any] = ["action": "addTodo", "text": "  测试 👨‍👩‍👧‍👦 \n"]
            body["projectId"] = project
            #expect(BridgeRequest.parse(body) == .success(.addTodo(text: "测试 👨‍👩‍👧‍👦", projectId: project as? String)))
        }
        let long = String(repeating: "👨‍👩‍👧‍👦", count: 500)
        #expect(BridgeRequest.parse(["action": "addTodo", "text": long]) == .success(.addTodo(text: long, projectId: nil)))
        for value: Any in ["", " \n\t", String(repeating: "a", count: 501), 1, true, NSNull()] {
            #expect(BridgeRequest.parse(["action": "addTodo", "text": value]) == .failure(.invalid))
        }
        #expect(BridgeRequest.parse(["action": "addTodo"]) == .failure(.invalid))
        for value: Any in ["", "bad/id", "中文", 1, true] {
            #expect(BridgeRequest.parse(["action": "addTodo", "text": "x", "projectId": value]) == .failure(.invalid))
        }
        #expect(BridgeRequest.parse(["action": "addTodo", "text": "x", "extra": NSNull()]) == .failure(.invalid))
    }
    @Test("提醒完成状态严格接受 CFBoolean，拒绝数字一和多余参数")
    func setTodoParsing() {
        for value in [true, false] {
            #expect(BridgeRequest.parse(["action": "setTodoDone", "todoId": "todo-1", "done": value]) == .success(.setTodoDone(id: "todo-1", done: value)))
        }
        for value: Any in [1, 0, NSNumber(value: 1), "true", NSNull()] {
            #expect(BridgeRequest.parse(["action": "setTodoDone", "todoId": "todo-1", "done": value]) == .failure(.invalid))
        }
        for id: Any in ["", "bad/id", 1, NSNull()] {
            #expect(BridgeRequest.parse(["action": "setTodoDone", "todoId": id, "done": true]) == .failure(.invalid))
        }
        #expect(BridgeRequest.parse(["action": "setTodoDone", "todoId": "x"]) == .failure(.invalid))
        #expect(BridgeRequest.parse(["action": "setTodoDone", "done": true]) == .failure(.invalid))
        #expect(BridgeRequest.parse(["action": "setTodoDone", "todoId": "x", "done": true, "text": "x"]) == .failure(.invalid))
    }
}
