import Foundation
import Testing
@testable import DesktopShell

struct PageEventTests {
    @Test("audioSpectrum 只有事件名与 12 个数值且可 JSON 序列化")
    func audioSpectrum() throws {
        let bands = (0..<12).map { Double($0) / 11 }
        let event = PageEvent.audioSpectrum(bands)
        #expect(Set(event.keys) == ["event", "bands"])
        #expect(event["event"] as? String == "audioSpectrum")
        #expect(event["bands"] as? [Double] == bands)
        #expect(JSONSerialization.isValidJSONObject(event))
        let data = try JSONSerialization.data(withJSONObject: event)
        let decoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["bands"] as? [Double] == bands)
    }

    @Test("实时频谱不进入重载缓存，也不替换其他事件")
    func spectrumIsNotReplayed() {
        var cache = PageEventCache()
        cache.remember(PageEvent.paused(false))
        cache.remember(PageEvent.audioSpectrum(Array(repeating: 0.5, count: 12)))
        let replay = cache.replay(safeArea: .init(top: 0, right: 0, bottom: 0, left: 0))
        #expect(replay.compactMap { $0["event"] as? String } == ["safeArea", "paused"])
        #expect(replay.last?["paused"] as? Bool == false)
    }

    @Test("safeArea 仅包含事件名和四个 CSS 像素数值")
    func safeArea() {
        let event = PageEvent.safeArea(SafeAreaInsets(top: 24.5, right: 0, bottom: 70, left: 3))
        #expect(Set(event.keys) == ["event", "top", "right", "bottom", "left"])
        #expect(event["event"] as? String == "safeArea")
        #expect(event["top"] as? CGFloat == 24.5 && event["right"] as? CGFloat == 0)
        #expect(event["bottom"] as? CGFloat == 70 && event["left"] as? CGFloat == 3)
        #expect(JSONSerialization.isValidJSONObject(event))
    }

    @Test("paused 使用平铺的布尔值")
    func paused() {
        for value in [false, true] {
            let event = PageEvent.paused(value)
            #expect(Set(event.keys) == ["event", "paused"])
            #expect(event["event"] as? String == "paused" && event["paused"] as? Bool == value)
        }
    }

    @Test("uiState 保留明确的 null，排除原生桌面图标开关")
    func uiState() {
        for state in [UiState(), UiState(avatarId: "12", backgroundId: "bg", voiceEnabled: false, desktopIconsHidden: true)] {
            let event = PageEvent.uiState(state)
            #expect(Set(event.keys) == ["event", "avatarId", "backgroundId", "voiceEnabled"])
            #expect(event["event"] as? String == "uiState" && event["voiceEnabled"] as? Bool == state.voiceEnabled)
            if let id = state.avatarId { #expect(event["avatarId"] as? String == id) }
            else { #expect(event["avatarId"] is NSNull) }
            if let id = state.backgroundId { #expect(event["backgroundId"] as? String == id) }
            else { #expect(event["backgroundId"] is NSNull) }
            #expect(JSONSerialization.isValidJSONObject(event))
        }
    }

    @Test("缓存只保留白名单最新事件，按固定顺序使用各页面自己的安全区域")
    func replayCache() {
        var cache = PageEventCache()
        let zero = SafeAreaInsets(top: 0, right: 0, bottom: 0, left: 0)
        #expect(cache.replay(safeArea: zero).compactMap { $0["event"] as? String } == ["safeArea"])
        cache.remember(["event": "todos", "items": []])
        cache.remember(PageEvent.uiState(UiState()))
        cache.remember(PageEvent.paused(false))
        cache.remember(["event": "systemStats", "cpu": 42])
        cache.remember(PageEvent.paused(true))
        cache.remember(PageEvent.safeArea(zero))
        cache.remember(["event": "audioSpectrum", "bands": []])
        cache.remember(["event": "unknown"]); cache.remember([:])
        let first = cache.replay(safeArea: SafeAreaInsets(top: 24, right: 0, bottom: 50, left: 0))
        #expect(first.compactMap { $0["event"] as? String } == ["safeArea", "paused", "uiState", "systemStats", "todos"])
        #expect(first.first?["top"] as? CGFloat == 24)
        #expect(first.dropFirst().first?["paused"] as? Bool == true)
        let second = cache.replay(safeArea: zero)
        #expect(second.first?["top"] as? CGFloat == 0 && second.count == 5)
    }

    @MainActor @Test("外观持久化后才通知；失败及隐藏桌面文件不通知")
    func appearanceNotifications() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let state = AppState(paths: AppPaths(supportDir: fixture.root, mediaDir: fixture.root.appendingPathComponent("media"), webDir: fixture.root))
        var changes: [UiState] = []
        state.onUiStateChanged = { value in
            #expect(UiStateStore(supportDir: fixture.root).load() == value)
            changes.append(value)
        }
        state.uiState.desktopIconsHidden = true; try state.saveUiState()
        #expect(changes.isEmpty)
        #expect(state.updateAppearance(avatar: .set("missing"), background: .unchanged) == .failure(.notFound))
        #expect(changes.isEmpty)
        _ = try fixture.file("media/avatars/1.png")
        #expect(state.updateAppearance(avatar: .set("1"), background: .clear) == .success(state.uiState))
        #expect(changes == [state.uiState])
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("ui.json"))
        _ = try fixture.directory("ui.json")
        let before = state.uiState
        #expect(state.updateAppearance(avatar: .clear, background: .clear) == .failure(.failed))
        #expect(changes == [before] && state.uiState == before)
    }

    @MainActor @Test("语音开关保存并通知，重启保持；写入失败也保留切换并通知")
    func voiceNotifications() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let paths = AppPaths(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root)
        let state = AppState(paths: paths)
        var changes: [Bool] = []; state.onUiStateChanged = { changes.append($0.voiceEnabled) }
        state.toggleVoice()
        #expect(!state.uiState.voiceEnabled && changes == [false])
        #expect(!AppState(paths: paths).uiState.voiceEnabled)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("ui.json"))
        _ = try fixture.directory("ui.json")
        state.toggleVoice()
        #expect(state.uiState.voiceEnabled && changes == [false, true])
    }

    @MainActor @Test("重读配置成功替换，损坏时保留上次有效配置和原文件")
    func reloadConfig() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let state = AppState(paths: AppPaths(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root))
        var config = state.config; config.character.name = "reloaded"
        let url = fixture.root.appendingPathComponent("config.json")
        try JSONEncoder().encode(config).write(to: url)
        state.reloadConfig(); #expect(state.config == config)
        try Data("{broken".utf8).write(to: url)
        state.reloadConfig(); #expect(state.config == config)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{broken")
    }

    @MainActor @Test("重载时配置文件缺失应保留当前配置，不重新生成示例文件")
    func missingReloadConfig() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let url = fixture.root.appendingPathComponent("config.json")
        var config = AppConfig.example; config.character.name = "retained custom configuration"
        try JSONEncoder().encode(config).write(to: url)
        let state = AppState(paths: AppPaths(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root))
        try FileManager.default.removeItem(at: url)
        state.reloadConfig()
        #expect(state.config == config)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

}


extension PageEventTests {
    @Test("todos 事件完整序列化 null，非 granted 时永不泄露 items")
    func todoEvent() throws {
        let input = [TodoItem(id: "a", text: "", done: false, projectId: nil, due: nil),
                     TodoItem(id: "b", text: "title", done: true, projectId: "p", due: .init(date: "2026-01-05", time: nil)),
                     TodoItem(id: "c", text: "third", done: false, projectId: nil, due: .init(date: "2026-01-05", time: "09:05"))]
        let event = PageEvent.todos(access: "granted", items: input)
        #expect(Set(event.keys) == ["event", "access", "items"])
        #expect(event["event"] as? String == "todos" && event["access"] as? String == "granted")
        let items = try #require(event["items"] as? [[String: Any]])
        try #require(items.count == 3)
        #expect(Set(items[0].keys) == ["id", "text", "done", "projectId", "due"])
        #expect(items[0]["id"] as? String == "a" && items[0]["text"] as? String == "" && items[0]["done"] as? Bool == false)
        #expect(items[0]["projectId"] is NSNull && items[0]["due"] is NSNull)
        #expect(items[1]["projectId"] as? String == "p" && items[1]["done"] as? Bool == true)
        let due = try #require(items[1]["due"] as? [String: Any])
        #expect(Set(due.keys) == ["date", "time"] && due["date"] as? String == "2026-01-05" && due["time"] is NSNull)
        #expect((items[2]["due"] as? [String: Any])?["time"] as? String == "09:05")
        #expect(JSONSerialization.isValidJSONObject(event))
        for access in ["denied", "notDetermined", "restricted", "writeOnly"] {
            let event = PageEvent.todos(access: access, items: input)
            #expect(event["access"] as? String == access)
            #expect((event["items"] as? [[String: Any]])?.isEmpty == true)
        }
    }
}

extension PageEventTests {
    @Test("config 推送与 getConfig 公共配置一致，项目回复复用投影且不泄露路径")
    func configEvent() throws {
        var config = AppConfig.example
        config.projects[0].remindersList = "Private list"
        let event = PageEvent.config(config)
        #expect(Set(event.keys) == ["event", "config"])
        #expect(event["event"] as? String == "config")
        #expect(JSONSerialization.isValidJSONObject(event))
        let value = try #require(event["config"] as? [String: Any])
        let reply = ConfigReply.make(config: config, avatars: [], backgrounds: [], uiState: UiState())
        #expect(NSDictionary(dictionary: value).isEqual(to: try #require(reply["config"] as? [String: Any])))
        #expect(Set(value.keys) == ["user", "character", "greetings", "projects", "terminal"])
        let project = try #require((value["projects"] as? [[String: Any]])?.first)
        #expect(Set(project.keys) == ["id", "name", "tags", "hasReminders"])
        #expect(project["id"] as? String == "desktop-shell")
        #expect(project["hasReminders"] as? Bool == true)
        #expect(NSDictionary(dictionary: project).isEqual(to: ConfigReply.makeProject(config.projects[0])))
        let serialized = try JSONSerialization.data(withJSONObject: event)
        let text = try #require(String(data: serialized, encoding: .utf8))
        for privateValue in ["remindersList", "bundle" + "Id", "Private list", "video/aemeath.mp4", "~/Desktop"] {
            #expect(!text.contains(privateValue))
        }
    }

    @Test("config 不进入页面重载缓存且不影响已有状态")
    func configIsNotReplayed() {
        var cache = PageEventCache()
        cache.remember(PageEvent.paused(true))
        cache.remember(PageEvent.config(.example))
        let replay = cache.replay(safeArea: .init(top: 0, right: 0, bottom: 0, left: 0))
        #expect(replay.compactMap { $0["event"] as? String } == ["safeArea", "paused"])
        #expect(replay.last?["paused"] as? Bool == true)
    }
}

extension PageEventTests {
    @Test("projectDrop 悬停和结果均可 JSON 序列化，只有公开字段，不进入重载缓存")
    func projectDrop() throws {
        let project = AppConfig.Project(id: "folder", name: "文件夹", path: "/private/source", tags: [])
        let outcome = FileDropTracking.dropOutcome(results: [.success(project), .failure(.duplicate)])
        for event in [PageEvent.projectDrop(over: true), PageEvent.projectDrop(over: false),
                      PageEvent.projectDrop(over: false, result: outcome),
                      PageEvent.projectDrop(over: false, result: FileDropTracking.dropOutcome(results: []))] {
            #expect(Set(event.keys) == ["event", "over", "result"])
            #expect(event["event"] as? String == "projectDrop")
            #expect(event["over"] is Bool)
            #expect(JSONSerialization.isValidJSONObject(event))
            let data = try JSONSerialization.data(withJSONObject: event)
            #expect(!String(decoding: data, as: UTF8.self).contains("/private/source"))
            var cache = PageEventCache(); cache.remember(event)
            #expect(cache.replay(safeArea: .init(top: 0, right: 0, bottom: 0, left: 0)).count == 1)
        }
        #expect(PageEvent.projectDrop(over: true)["result"] is NSNull)
        let result = try #require(PageEvent.projectDrop(over: false, result: outcome)["result"] as? [String: Any])
        #expect(Set(result.keys) == ["added", "error"])
        #expect(result["error"] as? String == "duplicate")
        let added = try #require(result["added"] as? [[String: String]])
        #expect(added == [["id": "folder", "name": "文件夹"]])
        let empty = try #require(PageEvent.projectDrop(over: false, result: FileDropTracking.dropOutcome(results: []))["result"] as? [String: Any])
        #expect(empty["error"] is NSNull && (empty["added"] as? [[String: String]]) == [])
    }
}
