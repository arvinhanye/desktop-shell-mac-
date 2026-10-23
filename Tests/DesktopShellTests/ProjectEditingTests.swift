import Foundation
import Testing
@testable import DesktopShell

private final class EditingFileSystem: ProjectFileSystem {
    var directories: Set<String> = ["/Users/me", "/Users/me/a", "/Users/me/b", "/Users/me2/x", "/outside"]
    var files: Set<String> = ["/Users/me/file", "/outside-file"]
    var links: [String: String] = ["/Users/me/link": "/outside", "/Users/me/alias": "/Users/me/a"]
    var checks: [String] = []

    func exists(_ url: URL) -> Bool {
        checks.append("exists:\(url.path)")
        return directories.contains(url.path) || files.contains(url.path)
    }
    func isDirectory(_ url: URL) -> Bool {
        checks.append("directory:\(url.path)")
        return directories.contains(url.path)
    }
    func resolvingSymlinks(_ url: URL) -> URL {
        URL(fileURLWithPath: links[url.path] ?? url.path, isDirectory: true)
    }
}

struct ProjectEditingTests {
    private let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    @Test("只替换开头的全角波浪号和所有全角斜杠", arguments: [
        ("～/Desktop/a", "~/Desktop/a"), ("／etc", "/etc"),
        ("～／Desktop／a", "~/Desktop/a"), ("~/a～b", "~/a～b"),
        ("~/Desktop/a", "~/Desktop/a"), ("", ""),
        (" ～／a", " ～/a"), ("～／项目Ａ／a～b", "~/项目Ａ/a～b"),
    ])
    func normalizesFullWidthSymbols(_ input: String, _ expected: String) {
        #expect(ProjectEditing.normalizeFullWidth(input) == expected)
    }

    @Test("原路径不存在时重试全角符号并返回真实路径", arguments: [
        "～/Desktop/a", "～／Desktop／a", "／Users／me／Desktop／a", "~/Desktop／a",
    ])
    func retriesFullWidthPath(_ input: String) throws {
        let fs = EditingFileSystem()
        fs.directories.insert("/Users/me/Desktop/a")
        let folder = try ProjectEditing.resolve(input, home: home, existing: [], fileSystem: fs).get()
        #expect(folder.path == "/Users/me/Desktop/a")
        #expect(ProjectEditing.storedPath(folder, home: home) == "~/Desktop/a")
    }

    @Test("重试路径仍执行原有校验并返回第二次的错误", arguments: [
        ("／etc", AddError.outsideHome), ("～/file", .notDirectory),
        ("～/a", .duplicate), ("～/missing", .notFound), ("～/link", .outsideHome),
        ("～", .outsideHome), ("～/a\0suffix", .notFound),
    ])
    func fullWidthRetryErrors(_ input: String, _ expected: AddError) {
        let fs = EditingFileSystem()
        fs.directories.insert("/etc")
        #expect(ProjectEditing.resolve(input, home: home, existing: ["~/a"], fileSystem: fs) == .failure(expected))
    }

    @Test("原样存在的全角文件名优先，即使半角路径也存在")
    func preservesExistingFullWidthFolder() throws {
        let fs = EditingFileSystem()
        fs.directories.formUnion(["/Users/me/a／b", "/Users/me/a/b"])
        let folder = try ProjectEditing.resolve("~/a／b", home: home, existing: [], fileSystem: fs).get()
        #expect(folder.path == "/Users/me/a／b")
        #expect(ProjectEditing.storedPath(folder, home: home) == "~/a／b")
        #expect(fs.checks == ["exists:/Users/me/a／b", "directory:/Users/me/a／b"])
    }

    @Test("原样得到非 notFound 错误时不重试", arguments: [AddError.notDirectory, .outsideHome, .duplicate])
    func preservesOriginalError(_ expected: AddError) {
        let fs = EditingFileSystem()
        let path = expected == .outsideHome ? "/outside／folder" : "/Users/me/a／b"
        fs.directories.formUnion(["/Users/me/a/b", "/outside/folder"])
        if expected == .notDirectory { fs.files.insert(path) }
        else { fs.directories.insert(path) }
        #expect(ProjectEditing.resolve(path, home: home, existing: [path], fileSystem: fs) == .failure(expected))
        #expect(fs.checks == ["exists:\(path)", "directory:\(path)"])
    }

    @Test("无全角符号的缺失路径只检查一次")
    func unchangedMissingPathIsNotRetried() {
        let fs = EditingFileSystem()
        #expect(ProjectEditing.resolve("~/missing", home: home, existing: [], fileSystem: fs) == .failure(.notFound))
        #expect(fs.checks == ["exists:/Users/me/missing"])
    }

    typealias AddError = ProjectEditing.AddError

    @Test("展开波浪号、标准化和解析符号链接后返回真实文件夹", arguments: [
        "~/a", "/Users/me/a/", "/Users/me/b/../a", "~/alias",
    ])
    func resolvesFolder(_ path: String) throws {
        let result = try ProjectEditing.resolve(path, home: home, existing: [], fileSystem: EditingFileSystem()).get()
        #expect(result.path == "/Users/me/a")
    }

    @Test("真实路径必须在个人目录内部而非自身或同前缀目录", arguments: [
        "~", "~/a/..", "/Users/me2/x", "~/link", "/outside",
    ])
    func rejectsOutsideHome(_ path: String) {
        #expect(ProjectEditing.resolve(path, home: home, existing: [], fileSystem: EditingFileSystem()) == .failure(.outsideHome))
    }

    @Test("按存在、文件夹、home、重复的顺序校验并在失败后停止")
    func validationOrder() {
        let fs = EditingFileSystem()
        #expect(ProjectEditing.resolve("/missing", home: home, existing: ["/missing"], fileSystem: fs) == .failure(.notFound))
        #expect(fs.checks == ["exists:/missing"])
        fs.checks = []
        #expect(ProjectEditing.resolve("/outside-file", home: home, existing: ["/outside-file"], fileSystem: fs) == .failure(.notDirectory))
        #expect(fs.checks == ["exists:/outside-file", "directory:/outside-file"])
        #expect(ProjectEditing.resolve("~/file", home: home, existing: [], fileSystem: fs) == .failure(.notDirectory))
        #expect(ProjectEditing.resolve("/outside", home: home, existing: ["/outside"], fileSystem: fs) == .failure(.outsideHome))
        for input in ["", "relative/path", "~someone/a", "~/a\0suffix"] {
            #expect(ProjectEditing.resolve(input, home: home, existing: [], fileSystem: fs) == .failure(.notFound))
        }
    }

    @Test("已有路径同样展开、标准化和解析链接以判断重复", arguments: [
        "~/a", "/Users/me/a/", "~/b/../a", "~/alias",
    ])
    func rejectsDuplicate(_ existing: String) {
        #expect(ProjectEditing.resolve("~/a", home: home, existing: ["bad-relative", existing], fileSystem: EditingFileSystem()) == .failure(.duplicate))
    }

    @Test("home 自身是链接时按真实 home 判断")
    func symlinkedHome() throws {
        let fs = EditingFileSystem()
        fs.links["/home/me"] = "/Users/me"
        fs.links["/home/me/a"] = "/Users/me/a"
        let result = try ProjectEditing.resolve("~/a", home: URL(fileURLWithPath: "/home/me"), existing: [], fileSystem: fs).get()
        #expect(result.path == "/Users/me/a")
    }

    @Test("仅 home 内部路径缩写为波浪号", arguments: [
        ("/Users/me/a", "~/a"), ("/Users/me/a b/项目", "~/a b/项目"),
        ("/Users/me2/a", "/Users/me2/a"), ("/outside", "/outside"), ("/Users/me", "/Users/me"),
    ])
    func storedPaths(_ path: String, _ expected: String) {
        #expect(ProjectEditing.storedPath(URL(fileURLWithPath: path), home: home) == expected)
    }

    @Test("id 只保留小写 ASCII 字母数字并折叠分隔符", arguments: [
        ("CS61A-master", "cs61a-master"), ("My App", "my-app"),
        ("操作系统原理实验", "project"), ("--a__b--", "a-b"), ("", "project"),
        ("ÄA👨‍👩‍👧‍👦B９9", "a-b-9"),
    ])
    func identifiers(_ name: String, _ expected: String) {
        #expect(ProjectEditing.makeID(name: name, existing: []) == expected)
    }

    @Test("id 冲突从 -2 起取第一个空位")
    func identifierCollisions() {
        #expect(ProjectEditing.makeID(name: "My App", existing: ["my-app"]) == "my-app-2")
        #expect(ProjectEditing.makeID(name: "My App", existing: ["my-app", "my-app-2"]) == "my-app-3")
        #expect(ProjectEditing.makeID(name: "My App", existing: ["my-app", "my-app-3"]) == "my-app-2")
        #expect(ProjectEditing.makeID(name: "中文", existing: ["project", "project-2"]) == "project-3")
    }

    @Test("新项目取文件夹名称和路径，不保存应用关联")
    func newProjectDefaults() {
        var config = AppConfig.example
        config.projects = [.init(id: "my-app", name: "other", path: "~/b", tags: nil)]
        let project = ProjectEditing.newProject(folder: home.appendingPathComponent("My App"), home: home, config: config)
        #expect(project == .init(id: "my-app-2", name: "My App", path: "~/My App", tags: [], remindersList: nil))
    }
}

extension ProjectEditingTests {
    @MainActor @Test("全角输入添加后持久化真实路径，再用半角添加判重复")
    func fullWidthPersistence() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let support = try fixture.directory("support")
        let home = try fixture.directory("home").resolvingSymlinksInPath()
        _ = try fixture.directory("home/Desktop/a")
        let store = ConfigStore(supportDir: support)
        var config = AppConfig.example
        config.projects = []
        try store.save(config)
        let state = AppState(paths: .init(supportDir: support, mediaDir: support, webDir: support), projectHome: home)
        let project = try state.addProject(path: "～／Desktop／a").get()
        #expect(project.path == "~/Desktop/a")
        #expect(project.name == "a")
        #expect(try store.loadUnfiltered().projects == [project])
        #expect(state.addProject(path: "~/Desktop/a") == .failure(.duplicate))
    }

    @MainActor @Test("增删每次读取磁盘最新配置，保留未过滤内容，保存后才通知且不碰项目文件夹")
    func editingPersistence() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let support = try fixture.directory("support")
        let home = try fixture.directory("home").resolvingSymlinksInPath()
        let folder = try fixture.directory("home/My App")
        let marker = try fixture.file("home/My App/keep", contents: "untouched")
        let store = ConfigStore(supportDir: support)
        var original = AppConfig.example
        original.projects = []
        try store.save(original)
        let state = AppState(paths: .init(supportDir: support, mediaDir: support, webDir: support), projectHome: home)
        var disk = original
        disk.character.motto = "edited externally"
        disk.greetings.reverse()
        disk.projects = [.init(id: "bad/id", name: "keep", path: "~/Other", tags: nil),
                         .init(id: "my-app", name: "existing", path: "~/Elsewhere", tags: ["keep"])]
        try store.save(disk)
        var changes = 0
        state.onConfigChanged = {
            #expect(state.config == (try? store.load()))
            changes += 1
        }
        let added = try state.addProject(path: folder.path).get()
        #expect(added == .init(id: "my-app-2", name: "My App", path: "~/My App", tags: []))
        var expected = disk
        expected.projects.append(added)
        #expect(try store.loadUnfiltered() == expected)
        #expect(state.config.projects.map(\.id) == ["my-app", "my-app-2"])
        #expect(changes == 1)
        #expect(state.addProject(path: "~/My App/") == .failure(.duplicate))
        #expect(changes == 1)
        expected.user?.name = "new external edit"
        try store.save(expected)
        try state.removeProject(id: added.id).get()
        expected.projects.removeLast()
        #expect(try store.loadUnfiltered() == expected)
        #expect(state.config.user?.name == "new external edit")
        #expect(changes == 2)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "untouched")
        #expect(FileManager.default.fileExists(atPath: folder.path))
        let bytes = try Data(contentsOf: support.appendingPathComponent("config.json"))
        if case .failure(let error) = state.removeProject(id: "missing") { #expect(error == .notFound) }
        else { Issue.record("Missing project removed successfully") }
        #expect(changes == 2)
        #expect(try Data(contentsOf: support.appendingPathComponent("config.json")) == bytes)
    }

    @MainActor @Test("损坏和缺失配置不被增删覆盖，也不通知或更改内存")
    func editingReadFailures() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let state = AppState(paths: .init(supportDir: fixture.root, mediaDir: fixture.root, webDir: fixture.root), projectHome: fixture.root)
        let before = state.config
        var changes = 0
        state.onConfigChanged = { changes += 1 }
        let file = try fixture.file("config.json", contents: "{broken")
        for missing in [false, true] {
            if missing { try FileManager.default.removeItem(at: file) }
            #expect(state.addProject(path: "~/folder") == .failure(.failed))
            if case .failure(let error) = state.removeProject(id: "desktop-shell") { #expect(error == .failed) }
            else { Issue.record("Removal succeeded without readable configuration") }
            #expect(state.config == before && changes == 0)
            if missing { #expect(!FileManager.default.fileExists(atPath: file.path)) }
            else { #expect(try String(contentsOf: file, encoding: .utf8) == "{broken") }
        }
    }

    @MainActor @Test("配置写入失败时增删保留磁盘、内存且不通知")
    func editingWriteFailures() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let support = try fixture.directory("support")
        let home = try fixture.directory("home").resolvingSymlinksInPath()
        _ = try fixture.directory("home/new")
        let state = AppState(paths: .init(supportDir: support, mediaDir: support, webDir: support), projectHome: home)
        let before = state.config
        let file = support.appendingPathComponent("config.json")
        let bytes = try Data(contentsOf: file)
        var changes = 0
        state.onConfigChanged = { changes += 1 }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: support.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path) }
        #expect(state.addProject(path: "~/new") == .failure(.failed))
        if case .failure(let error) = state.removeProject(id: "desktop-shell") { #expect(error == .failed) }
        else { Issue.record("Removal succeeded without writable configuration") }
        #expect(state.config == before && changes == 0)
        #expect(try Data(contentsOf: file) == bytes)
    }

    @MainActor @Test("被启动过滤的项目路径仍参与重复检测")
    func filteredProjectsStillPreventDuplicates() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let folder = try fixture.directory("home/existing").resolvingSymlinksInPath()
        let support = try fixture.directory("support")
        var config = AppConfig.example
        config.projects = [.init(id: "bad/id", name: "keep", path: "~/existing", tags: nil)]
        let store = ConfigStore(supportDir: support)
        try store.save(config)
        let state = AppState(paths: .init(supportDir: support, mediaDir: support, webDir: support), projectHome: folder.deletingLastPathComponent())
        #expect(state.config.projects.isEmpty)
        #expect(state.addProject(path: folder.path) == .failure(.duplicate))
        #expect(try store.loadUnfiltered() == config)
    }
}

@MainActor
private final class ProjectReminderBackend: RemindersBackend {
    var access = "granted"
    let changeSource: AnyObject = NSObject()
    func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void) { completion(false) }
    func lists() -> [ReminderListSnapshot] { [.init(id: "work-list", title: "Work", sourceTitle: "Test", canWrite: true)] }
    func defaultListID() -> String? { "work-list" }
    func refresh() {}
    func fetch(completedSince: Date?, completion: @escaping @MainActor ([ReminderSnapshot]?) -> Void) {
        completion(completedSince == nil ? [ReminderSnapshot(id: "todo-1", title: "fixture", isCompleted: false,
            completionDate: nil, creationDate: nil, due: nil, listId: "work-list")] : [])
    }
    func add(text: String, listID: String) throws -> ReminderSnapshot { throw BridgeError.failed }
    func setDone(id: String, done: Bool) throws { throw BridgeError.failed }
}

extension ProjectEditingTests {
    @MainActor @Test("增删项目后提醒事项按新配置重映射并推送，不写入提醒后端")
    func editingRepublishesReminders() throws {
        let fixture = try TemporaryTestDirectory(); defer { fixture.cleanup() }
        let support = try fixture.directory("support")
        let home = try fixture.directory("home").resolvingSymlinksInPath()
        _ = try fixture.directory("home/new")
        let store = ConfigStore(supportDir: support)
        var config = AppConfig.example
        config.projects[0].remindersList = "Work"
        try store.save(config)
        let state = AppState(paths: .init(supportDir: support, mediaDir: support, webDir: support), projectHome: home)
        let reminders = RemindersStore(appState: state, backend: ProjectReminderBackend(),
            notifications: NotificationCenter(), workspaceNotifications: NotificationCenter(),
            schedule: { _, _, _, _ in {} })
        state.remindersStore = reminders
        defer { reminders.stop() }
        var events: [[String: Any]] = []
        reminders.onChange = { events.append($0) }
        reminders.start()
        #expect((events.last?["items"] as? [[String: Any]])?.first?["projectId"] as? String == "desktop-shell")
        try state.removeProject(id: "desktop-shell").get()
        #expect(events.count == 2)
        #expect((events.last?["items"] as? [[String: Any]])?.first?["projectId"] is NSNull)
        // An external config edit must also become visible when the next project is added.
        config.projects[0].id = "external-project"
        try store.save(config)
        _ = try state.addProject(path: "~/new").get()
        #expect(events.count == 3)
        #expect((events.last?["items"] as? [[String: Any]])?.first?["projectId"] as? String == "external-project")
        #expect((events.last?["items"] as? [[String: Any]])?.first?["id"] as? String == "todo-1")
    }
}
