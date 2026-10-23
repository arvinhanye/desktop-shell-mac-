import Foundation
import Testing
@testable import DesktopShell

struct ProjectPreferencesTests {
    private func config() throws -> AppConfig {
        let data = Data("""
        {"background":{"video":"a"},"character":{"name":"A"},"greetings":[],
        "apps":[{"id":"editor","name":"Editor","bundleId":"app.editor"}],
        "projects":[{"id":"a","name":"A","path":"~/a","remindersList":"Shared"},
                    {"id":"b","name":"B","path":"~/b","remindersList":"Shared"}],
        "projectOrder":["b","missing","b","a"]}
        """.utf8)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    @Test("显示排序去重补尾且保留共享提醒的原始认领顺序")
    func displayOrder() throws {
        let c = try config()
        let reply = ConfigReply.makeConfig(c, iconIDs: [])
        let rows = try #require(reply["projects"] as? [[String: Any]])
        #expect(rows.compactMap { $0["id"] as? String } == ["b", "a"])
        #expect(c.projects.map(\.id) == ["a", "b"])
        #expect(TodoItems.listToProject(projects: c.projects, lists: [("list", "Shared")]) == ["list": "a"])
    }

    @Test("编辑动作进入白名单但不接受多余路径或空补丁")
    func requestContract() throws {
        _ = try BridgeRequest.parse(["action": "getProjectEditOptions", "projectId": "a"]).get()
        _ = try BridgeRequest.parse(["action": "updateProject", "projectId": "a", "name": " New "]).get()
        _ = try BridgeRequest.parse(["action": "updateProject", "projectId": "a", "reminderListOptionId": NSNull()]).get()
        _ = try BridgeRequest.parse(["action": "reorderProjects", "projectIds": ["b", "a"]]).get()
        #expect(BridgeRequest.parse(["action": "updateProject", "projectId": "a"]) == .failure(.invalid))
        #expect(BridgeRequest.parse(["action": "getProjectEditOptions", "projectId": "a", "path": "/tmp"]) == .failure(.invalid))
        #expect(BridgeRequest.parse(["action": "reorderProjects", "projectIds": ["a", "a"]]) == .failure(.invalid))
    }

    @Test("显式列表ID优先于旧名称，失联时不回退到同名列表")
    func identifierBinding() throws {
        let data = Data("""
        {"id":"a","name":"A","path":"~/a","remindersList":"Old","remindersListId":"native-id"}
        """.utf8)
        let project = try JSONDecoder().decode(AppConfig.Project.self, from: data)
        #expect(TodoItems.listToProject(projects: [project], lists: [("native-id", "Renamed"), ("other", "Old")]) == ["native-id": "a"])
        #expect(TodoItems.listToProject(projects: [project], lists: [("other", "Old")]).isEmpty)
        let publicValue = ConfigReply.makeProject(project)
        #expect(publicValue["hasReminders"] as? Bool == true)
        #expect(publicValue["remindersListId"] == nil)
    }
}

extension ProjectPreferencesTests {
    @Test("改名保留身份和路径，默认应用移首保留其余关联")
    func updateFields() throws {
        var c = try config()
        c.apps.append(.init(id: "other", name: "Other", bundleId: "app.other"))
        var p = c.projects[0]
        p.apps = ["editor", "other", "missing"]
        p.tags = ["keep"]
        let updated = try ProjectPreferences.updating(p, name: "  New  ", appId: "other", reminderList: .unchanged, apps: c.apps).get()
        #expect(updated.name == "New" && updated.id == p.id && updated.path == p.path && updated.tags == ["keep"])
        #expect(updated.apps == ["other", "editor", "missing"])
        #expect(updated.remindersList == "Shared")
        #expect(ProjectPreferences.updating(p, name: " \n ", appId: nil, reminderList: .unchanged, apps: c.apps) == .failure(.invalid))
        #expect(ProjectPreferences.updating(p, name: String(repeating: "a", count: 101), appId: nil, reminderList: .unchanged, apps: c.apps) == .failure(.invalid))
        #expect(ProjectPreferences.updating(p, name: nil, appId: "absent", reminderList: .unchanged, apps: c.apps) == .failure(.notFound))
        let cleared = try ProjectPreferences.updating(p, name: nil, appId: nil, reminderList: .clear, apps: c.apps).get()
        #expect(cleared.remindersList == nil && cleared.remindersListId == nil)
    }

    @MainActor @Test("编辑读取最新配置且保持未知JSON键，排序只改显示顺序")
    func persistence() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let store = ConfigStore(supportDir: fixture.root)
        try store.save(config())
        let state = AppState(paths: .init(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root))
        let file = fixture.root.appendingPathComponent("config.json")
        var raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        raw["extension"] = ["keep": true]
        var projects = try #require(raw["projects"] as? [[String: Any]])
        projects[0]["extra"] = "untouched"
        projects.append(["id": "bad/id", "name": "Hidden", "path": "~/hidden", "extra": "hidden"])
        raw["projects"] = projects
        try JSONSerialization.data(withJSONObject: raw).write(to: file)
        var changes = 0; state.onConfigChanged = { changes += 1 }
        _ = try state.updateProject(projectId: "a", name: "Renamed", appId: nil, reminderListOption: .unchanged).get()
        try state.reorderProjects(projectIds: ["b", "a"]).get()
        let after = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect((after["extension"] as? [String: Bool])?["keep"] == true)
        let afterProjects = try #require(after["projects"] as? [[String: Any]])
        #expect(afterProjects.compactMap { $0["id"] as? String } == ["a", "b", "bad/id"])
        #expect(afterProjects[0]["extra"] as? String == "untouched")
        #expect(afterProjects[2]["extra"] as? String == "hidden")
        #expect(changes == 2)
        let bytes = try Data(contentsOf: file)
        if case .failure(let error) = state.reorderProjects(projectIds: ["a"]) { #expect(error == .notFound) }
        else { Issue.record("Stale order accepted") }
        #expect(try Data(contentsOf: file) == bytes && changes == 2)
        #expect(state.config.projects.map(\.id) == ["a", "b"])
    }

    @MainActor @Test("列表选项按ID消歧，撤权只读失联拒绝，不回退默认列表")
    func reminderOptions() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        var c = try config(); c.projects[0].remindersList = nil; c.projects[1].remindersList = nil
        try ConfigStore(supportDir: fixture.root).save(c)
        let state = AppState(paths: .init(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root))
        let backend = PreferencesReminderBackend()
        let reminders = RemindersStore(appState: state, backend: backend, notifications: NotificationCenter(),
            workspaceNotifications: NotificationCenter(), schedule: { _, _, _, _ in {} })
        state.remindersStore = reminders; reminders.start(); defer { reminders.stop() }
        let options = try state.projectEditOptions(projectId: "a").get()
        let lists = try #require(options["lists"] as? [[String: Any]])
        #expect(lists.count == 3)
        let token = try #require(lists.first { $0["source"] as? String == "First" }?["id"] as? String)
        #expect(isValidID(token) && token != "native/list-1")
        _ = try state.updateProject(projectId: "a", name: nil, appId: nil, reminderListOption: .set(token)).get()
        #expect(state.config.projects[0].remindersListId == "native/list-1")
        #expect(state.updateProject(projectId: "b", name: nil, appId: nil, reminderListOption: .set(token)) == .failure(.failed))
        backend.items[0].title = "Renamed"
        #expect((try state.projectEditOptions(projectId: "a").get()["binding"] as? [String: Any])?["status"] as? String == "linked")
        backend.items[0].canWrite = false
        var result: Result<TodoItem, BridgeError>?
        reminders.add(text: "test", projectId: "a") { result = $0 }
        #expect(result == .failure(.failed) && backend.writes.isEmpty)
        backend.items.removeFirst()
        reminders.add(text: "test", projectId: "a") { result = $0 }
        #expect(result == .failure(.notFound) && backend.writes.isEmpty)
        #expect((try state.projectEditOptions(projectId: "a").get()["binding"] as? [String: Any])?["status"] as? String == "missing")
        backend.access = "denied"
        _ = try state.updateProject(projectId: "a", name: "Without access", appId: nil, reminderListOption: .unchanged).get()
        #expect(state.updateProject(projectId: "a", name: nil, appId: nil, reminderListOption: .set(token)) == .failure(.failed))
        _ = try state.updateProject(projectId: "a", name: nil, appId: nil, reminderListOption: .clear).get()
        #expect(state.config.projects[0].remindersListId == nil)
    }
}

@MainActor private final class PreferencesReminderBackend: RemindersBackend {
    var access = "granted"
    let changeSource: AnyObject = NSObject()
    var items = [ReminderListSnapshot(id: "native/list-1", title: "Same", sourceTitle: "First", canWrite: true),
                 ReminderListSnapshot(id: "native/list-2", title: "Same", sourceTitle: "Second", canWrite: true),
                 ReminderListSnapshot(id: "read-only", title: "Read only", sourceTitle: "First", canWrite: false)]
    var writes: [String] = []
    func lists() -> [ReminderListSnapshot] { items }
    func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void) { completion(false) }
    func defaultListID() -> String? { "default" }
    func refresh() {}
    func fetch(completedSince: Date?, completion: @escaping @MainActor ([ReminderSnapshot]?) -> Void) { completion([]) }
    func add(text: String, listID: String) throws -> ReminderSnapshot {
        writes.append(listID)
        return .init(id: "new", title: text, isCompleted: false, completionDate: nil, creationDate: nil, due: nil, listId: listID)
    }
    func setDone(id: String, done: Bool) throws {}
}

extension ProjectPreferencesTests {
    @Test("编辑参数严格类型和长度边界，公开配置保持最小字段")
    func strictParameters() throws {
        let base: [String: Any] = ["action": "updateProject", "projectId": "a"]
        for patch: [String: Any] in [["name": NSNull()], ["name": 1], ["name": "  "],
            ["name": String(repeating: "家", count: 101)], ["appId": NSNull()], ["appId": "bad/id"],
            ["reminderListOptionId": 1], ["name": "OK", "path": "~/x"]] {
            #expect(BridgeRequest.parse(base.merging(patch) { _, new in new }) == .failure(.invalid))
        }
        let family = String(repeating: "👨‍👩‍👧‍👦", count: 100)
        _ = try BridgeRequest.parse(base.merging(["name": family]) { _, new in new }).get()
        for ids: Any in [NSNull(), [1], ["bad/id"], ["a", "a"]] {
            #expect(BridgeRequest.parse(["action": "reorderProjects", "projectIds": ids]) == .failure(.invalid))
        }
        let publicRows = try #require(ConfigReply.makeConfig(config(), iconIDs: [])["projects"] as? [[String: Any]])
        #expect(publicRows.allSatisfy { Set($0.keys) == ["id", "name", "tags", "apps", "hasReminders"] })
        #expect(!BridgeOrigin.isTrusted(isMainFrame: false, scheme: "shell", host: "app"))
    }

    @MainActor @Test("编辑保存失败不修改内存磁盘或发送配置通知")
    func writeRollback() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let store = ConfigStore(supportDir: fixture.root)
        try store.save(config())
        let state = AppState(paths: .init(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root))
        let before = state.config, file = fixture.root.appendingPathComponent("config.json")
        let bytes = try Data(contentsOf: file)
        var notifications = 0; state.onConfigChanged = { notifications += 1 }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.root.path) }
        #expect(state.updateProject(projectId: "a", name: "Changed", appId: nil, reminderListOption: .clear) == .failure(.failed))
        if case .failure(let error) = state.reorderProjects(projectIds: ["a", "b"]) { #expect(error == .failed) }
        else { Issue.record("Reorder wrote into read-only directory") }
        #expect(state.config == before && notifications == 0)
        #expect(try Data(contentsOf: file) == bytes)
    }

    @MainActor @Test("共享首认领者也拒绝重新绑定，选项稳定且删除后撤销")
    func sharedAndStaleOptions() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        var c = try config(); c.projects[0].remindersList = "Same"; c.projects[1].remindersList = "Same"
        try ConfigStore(supportDir: fixture.root).save(c)
        let state = AppState(paths: .init(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root))
        let backend = PreferencesReminderBackend()
        let reminders = RemindersStore(appState: state, backend: backend, notifications: NotificationCenter(),
            workspaceNotifications: NotificationCenter(), schedule: { _, _, _, _ in {} })
        state.remindersStore = reminders; reminders.start(); defer { reminders.stop() }
        let first = try state.projectEditOptions(projectId: "a").get()
        let binding = try #require(first["binding"] as? [String: Any])
        let token = try #require(binding["optionId"] as? String)
        #expect(binding["status"] as? String == "shared")
        #expect(state.updateProject(projectId: "a", name: nil, appId: nil, reminderListOption: .set(token)) == .failure(.failed))
        #expect((try state.projectEditOptions(projectId: "a").get()["binding"] as? [String: Any])?["optionId"] as? String == token)
        backend.items.removeFirst()
        #expect(state.updateProject(projectId: "a", name: nil, appId: nil, reminderListOption: .set(token)) == .failure(.notFound))
        #expect(backend.writes.isEmpty)
    }
}

extension ProjectPreferencesTests {
    @MainActor @Test("新增项目总在显示末尾，未知排序ID不会提前认领新项目")
    func addedProjectAtEnd() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        _ = try fixture.directory("new")
        var c = try config(); c.projectOrder = ["new", "b", "a"]
        let store = ConfigStore(supportDir: fixture.root); try store.save(c)
        let state = AppState(paths: .init(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root), projectHome: fixture.root)
        _ = try state.addProject(path: "~/new").get()
        #expect(ProjectPreferences.orderedProjects(state.config).map(\.id) == ["b", "a", "new"])
    }
}

extension ProjectPreferencesTests {
    @MainActor @Test("编辑默认应用与实际打开入口一致，跳过已失效关联")
    func effectiveDefaultApp() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        var c = try config(); c.projects[0].apps = ["removed", "editor"]
        let disk = ConfigStore(supportDir: fixture.root); try disk.save(c)
        let state = AppState(paths: .init(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root))
        func selected() throws -> String? {
            (try state.projectEditOptions(projectId: "a").get()["project"] as? [String: Any])?["appId"] as? String
        }
        #expect(try selected() == "editor")
        let reminders = RemindersStore(appState: state, backend: PreferencesReminderBackend(),
            notifications: NotificationCenter(), workspaceNotifications: NotificationCenter(), schedule: { _, _, _, _ in {} })
        state.remindersStore = reminders; reminders.start(); defer { reminders.stop() }
        #expect(try selected() == "editor")
        c.apps = []; try disk.save(c)
        #expect(try selected() == nil)
    }
}
