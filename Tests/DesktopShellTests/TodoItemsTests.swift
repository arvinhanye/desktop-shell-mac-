import Foundation
import Testing
@testable import DesktopShell

struct TodoItemsTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func reminder(_ id: String, done: Bool = false, completed: Date? = nil,
                          created: Date? = nil, due: DateComponents? = nil) -> ReminderSnapshot {
        ReminderSnapshot(id: id, title: "", isCompleted: done, completionDate: completed,
                         creationDate: created, due: due, listId: "list")
    }
    @Test("到期日期原样补零；不补造缺失的日期或时间")
    func dueComponents() {
        #expect(TodoItems.due(nil) == nil)
        #expect(TodoItems.due(DateComponents(year: 2026, month: 1)) == nil)
        #expect(TodoItems.due(DateComponents(year: 2026, month: 1, day: 5)) == .init(date: "2026-01-05", time: nil))
        #expect(TodoItems.due(DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 5)) == .init(date: "2026-01-05", time: "09:05"))
        #expect(TodoItems.due(DateComponents(year: 2026, month: 1, day: 5, hour: 9)) == .init(date: "2026-01-05", time: nil))
        #expect(TodoItems.due(DateComponents(timeZone: TimeZone(secondsFromGMT: -36000), year: 2026, month: 1, day: 5, hour: 23, minute: 5)) == .init(date: "2026-01-05", time: "23:05"))
    }
    @Test("只保留未完成与日历里今天完成的提醒，空标题不丢弃")
    func filteringAndProjection() {
        let input = [reminder("open"), reminder("today", done: true, completed: date(18)),
                     reminder("yesterday", done: true, completed: date(17, 23)), reminder("missing", done: true)]
        let result = TodoItems.make(input, listToProject: ["list": "project"], now: date(18, 10), calendar: calendar)
        #expect(result == [TodoItem(id: "open", text: "", done: false, projectId: "project", due: nil),
                           TodoItem(id: "today", text: "", done: true, projectId: "project", due: nil)])
        #expect(TodoItems.make([reminder("orphan")], listToProject: [:], now: date(18), calendar: calendar).first?.projectId == nil)
    }
    @Test("排序按时间、全天末尾、无期限，再按创建时间和 id；完成项逆序")
    func sorting() {
        let input = [reminder("none"), reminder("day", due: DateComponents(year: 2026, month: 10, day: 18)),
                     reminder("late", due: DateComponents(year: 2026, month: 10, day: 18, hour: 23, minute: 59)),
                     reminder("early-b", created: date(17), due: DateComponents(year: 2026, month: 10, day: 18, hour: 9, minute: 0)),
                     reminder("early-a", created: date(17), due: DateComponents(year: 2026, month: 10, day: 18, hour: 9, minute: 0)),
                     reminder("early-old", created: date(16), due: DateComponents(year: 2026, month: 10, day: 18, hour: 9, minute: 0)),
                     reminder("done-old", done: true, completed: date(18, 1)), reminder("done-new", done: true, completed: date(18, 2))]
        #expect(TodoItems.make(input, listToProject: [:], now: date(18, 12), calendar: calendar).map(\.id)
                == ["early-old", "early-a", "early-b", "late", "day", "none", "done-new", "done-old"])
    }
    @Test("今天按传入时区判断，全天截止跨夏令时仍落在当地当天末尾")
    func calendarBoundaries() {
        var local = calendar; local.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 18))!
        let input = [reminder("day", due: DateComponents(year: 2026, month: 11, day: 1)),
                     reminder("timed", due: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 59)),
                     reminder("yesterday", done: true, completed: now.addingTimeInterval(-15 * 3600))]
        #expect(TodoItems.make(input, listToProject: [:], now: now, calendar: local).map(\.id) == ["timed", "day"])
    }
    @Test("先排序再截断为五百条，输入反序仍确定")
    func limit() {
        let input = (0..<501).reversed().map { reminder(String(format: "%04d", $0)) }
        let result = TodoItems.make(input, listToProject: [:], now: date(18), calendar: calendar)
        #expect(result.count == 500 && result.first?.id == "0000" && result.last?.id == "0499")
    }
    @Test("列表精确匹配、不折叠空白或大小写，同名取排序最前 id，冲突取首项目")
    func mapping() {
        func project(_ id: String, _ list: String?) -> AppConfig.Project { .init(id: id, name: id, path: "", remindersList: list) }
        let projects = [project("first", "Work"), project("duplicate", "Work"), project("case", "work"),
                        project("spaces", " Work "), project("blank", " \n"), project("none", nil)]
        #expect(TodoItems.listToProject(projects: projects, lists: [("z", "Work"), ("a", "Work")]) == ["a": "first"])
        #expect(TodoItems.listToProject(projects: [project("x", "Work")], lists: [("a", "Work ")]).isEmpty)
        #expect(TodoItems.listToProject(projects: [project("x", " Work ")], lists: [("a", " Work ")]) == ["a": "x"])
    }
}

import AppKit
import EventKit

@MainActor
struct RemindersStoreTests {
    private final class Backend: RemindersBackend {
        var access = "granted"
        let changeSource: AnyObject = NSObject()
        var calendars: [(id: String, title: String)] = [("list", "Work"), ("default", "Default")]
        var defaultID: String? = "default"
        var permission: (@MainActor (Bool) -> Void)?
        var requests = 0, refreshes = 0
        var reads: [(Date?, @MainActor ([ReminderSnapshot]?) -> Void)] = []
        var writes: [(String, String)] = []
        var updates: [(String, Bool)] = []
        var writeError: BridgeError?
        func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void) { requests += 1; permission = completion }
        func lists() -> [(id: String, title: String)] { calendars }
        func defaultListID() -> String? { defaultID }
        func refresh() { refreshes += 1 }
        func fetch(completedSince: Date?, completion: @escaping @MainActor ([ReminderSnapshot]?) -> Void) { reads.append((completedSince, completion)) }
        func add(text: String, listID: String) throws -> ReminderSnapshot {
            if let writeError { throw writeError }
            writes.append((text, listID))
            return ReminderSnapshot(id: "new-id", title: text, isCompleted: false, completionDate: nil, creationDate: nil, due: nil, listId: listID)
        }
        func setDone(id: String, done: Bool) throws {
            if let writeError { throw writeError }
            updates.append((id, done))
        }
    }
    private final class Job {
        let delay: TimeInterval, repeating: Bool, tolerance: TimeInterval
        let action: @MainActor () -> Void
        var cancelled = false
        init(_ delay: TimeInterval, _ repeating: Bool, _ tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) {
            self.delay = delay; self.repeating = repeating; self.tolerance = tolerance; self.action = action
        }
    }
    @MainActor private final class Fixture {
        let directory: TemporaryTestDirectory
        let state: AppState
        let backend = Backend()
        let center = NotificationCenter(), workspace = NotificationCenter()
        var jobs: [Job] = []
        var events: [[String: Any]] = []
        var now = Date(timeIntervalSince1970: 1_792_324_800) // 2026-10-18 12:00 UTC
        var store: RemindersStore!
        init(_ access: String = "granted") throws {
            directory = try TemporaryTestDirectory()
            var config = AppConfig.example
            config.projects[0].remindersList = "Work"
            try JSONEncoder().encode(config).write(to: directory.root.appendingPathComponent("config.json"))
            state = AppState(paths: AppPaths(supportDir: directory.root, mediaDir: directory.root, webDir: directory.root))
            backend.access = access
            store = RemindersStore(appState: state, backend: backend, notifications: center, workspaceNotifications: workspace,
                                   now: { [unowned self] in self.now }, calendar: {
                                       var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
                                   }, schedule: { [unowned self] delay, repeating, tolerance, action in
                                       let job = Job(delay, repeating, tolerance, action); self.jobs.append(job)
                                       return { job.cancelled = true }
                                   })
            state.remindersStore = store
            store.onChange = { [unowned self] in self.events.append($0) }
        }
        func cleanup() { store.stop(); store.onChange = nil; state.remindersStore = nil; directory.cleanup() }
        func complete(_ index: Int = 0, open: [ReminderSnapshot] = [], done: [ReminderSnapshot] = []) throws {
            try #require(backend.reads.count >= index + 2)
            backend.reads[index].1(open); backend.reads[index + 1].1(done)
        }
        var item: ReminderSnapshot { .init(id: "todo-1", title: "fixture-only", isCompleted: false, completionDate: nil, creationDate: nil, due: nil, listId: "list") }
    }

    @Test("首次推送 notDetermined 空列表，权限结果后才同步读取且重复启动不重询问")
    func permissionFlow() throws {
        let f = try Fixture("notDetermined"); defer { f.cleanup() }
        f.store.start(); f.store.start()
        #expect(f.backend.requests == 1 && f.backend.reads.isEmpty)
        #expect(f.events.count == 1 && f.events.first?["access"] as? String == "notDetermined")
        f.backend.access = "granted"; f.backend.permission?(false)
        #expect(f.backend.refreshes == 1) // Authorization status, not callback's boolean, is authoritative.
        try f.complete(open: [f.item])
        #expect(f.events.last?["access"] as? String == "granted")
        #expect((f.events.last?["items"] as? [[String: Any]])?.first?["projectId"] as? String == "desktop-shell")
    }
    @Test("拒绝或受限权限只发空列表，新增和勾选失败且不调用写入")
    func deniedWrites() throws {
        for access in ["denied", "restricted", "writeOnly"] {
            let f = try Fixture(access); defer { f.cleanup() }
            f.store.start()
            #expect(f.backend.requests == 0 && f.backend.reads.isEmpty && f.backend.refreshes == 0)
            #expect(f.events.last?["access"] as? String == access)
            #expect((f.events.last?["items"] as? [[String: Any]])?.isEmpty == true)
            var add: Result<TodoItem, BridgeError>?; var doneError: BridgeError?
            f.store.add(text: "fixture", projectId: nil) { add = $0 }
            f.store.setDone(id: "todo-1", done: true) { if case .failure(let e) = $0 { doneError = e } }
            #expect(add == .failure(.failed) && doneError == .failed)
            #expect(f.backend.writes.isEmpty && f.backend.updates.isEmpty)
        }
    }
    @Test("读取合并两次查询且等待完整结果，相同状态不重推，nil 查询不伪造空列表")
    func pairedReadsAndDedupe() throws {
        let f = try Fixture(); defer { f.cleanup() }; f.store.start()
        try #require(f.backend.reads.count == 2)
        #expect(f.backend.reads[0].0 == nil)
        #expect(f.backend.reads[1].0 == Date(timeIntervalSince1970: 1_792_281_600))
        f.backend.reads[1].1([]); #expect(f.events.isEmpty)
        f.backend.reads[0].1([f.item]); #expect(f.events.count == 1)
        f.store.configDidReload(); try f.complete(2, open: [f.item]); #expect(f.events.count == 1)
        f.store.configDidReload(); try #require(f.backend.reads.count == 6)
        f.backend.reads[4].1(nil); f.backend.reads[5].1([]); #expect(f.events.count == 1)
        f.store.configDidReload(); try f.complete(6); #expect(f.events.count == 2)
    }
    @Test("配置重载淘汰旧查询，应用配置入口触发新映射")
    func configReloadInvalidatesReads() throws {
        let f = try Fixture(); defer { f.cleanup() }; f.store.start()
        var config = f.state.config; config.projects[0].remindersList = "Default"
        try JSONEncoder().encode(config).write(to: f.directory.root.appendingPathComponent("config.json"))
        f.state.reloadConfig()
        try #require(f.backend.reads.count == 4)
        try f.complete(2, open: [f.item]); try f.complete(0, open: [f.item])
        #expect(f.events.count == 1)
        #expect((f.events.last?["items"] as? [[String: Any]])?.first?["projectId"] is NSNull)
    }
    @Test("事件变化防抖零点五秒，旧回调无效，日期变更立即读取")
    func debounceAndDayChange() throws {
        let f = try Fixture(); defer { f.cleanup() }; f.store.start(); try f.complete()
        f.center.post(name: .EKEventStoreChanged, object: f.backend.changeSource)
        try #require(f.jobs.count == 2)
        let old = f.jobs[1]
        f.center.post(name: .EKEventStoreChanged, object: f.backend.changeSource)
        try #require(f.jobs.count == 3)
        #expect(old.cancelled && !f.jobs[2].repeating && f.jobs[2].delay == 0.5)
        old.action(); #expect(f.backend.reads.count == 2)
        f.jobs[2].action(); #expect(f.backend.reads.count == 4)
        f.center.post(name: .NSCalendarDayChanged, object: nil)
        #expect(f.backend.reads.count == 6)
    }
    @Test("醒屏和会话恢复及五分钟计时器只主动同步，不重复读取")
    func periodicSync() throws {
        let f = try Fixture(); defer { f.cleanup() }; f.store.start()
        try #require(f.jobs.count == 1)
        #expect(f.jobs[0].delay == 300 && f.jobs[0].repeating && f.jobs[0].tolerance == 60)
        f.jobs[0].action()
        f.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        f.workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(f.backend.refreshes == 4 && f.backend.reads.count == 2)
    }
    @Test("停止取消计时、防抖与观察；过期查询和权限回调不推送，重启可正常读")
    func stopAndRestart() throws {
        let f = try Fixture(); defer { f.cleanup() }; f.store.start()
        f.center.post(name: .EKEventStoreChanged, object: f.backend.changeSource)
        f.store.stop(); f.store.stop()
        #expect(f.jobs.allSatisfy { $0.cancelled })
        for job in f.jobs { job.action() }
        try f.complete(open: [f.item])
        f.center.post(name: .NSCalendarDayChanged, object: nil)
        f.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #expect(f.events.isEmpty && f.backend.reads.count == 2 && f.backend.refreshes == 1)
        f.store.start(); try f.complete(2, open: [f.item]); #expect(f.events.count == 1)
        let pending = try Fixture("notDetermined"); defer { pending.cleanup() }
        pending.store.start(); pending.store.stop(); pending.backend.access = "granted"; pending.backend.permission?(false)
        #expect(pending.backend.reads.isEmpty && pending.events.count == 1)
    }
    @Test("权限撤销后的异步读取不泄露旧项目，重新允许后恢复")
    func revocationDuringRead() throws {
        let f = try Fixture(); defer { f.cleanup() }; f.store.start(); f.backend.access = "denied"
        try f.complete(open: [f.item])
        #expect(f.events.last?["access"] as? String == "denied")
        #expect((f.events.last?["items"] as? [[String: Any]])?.isEmpty == true)
        f.backend.access = "granted"; f.store.configDidReload(); try f.complete(2, open: [f.item])
        #expect(f.events.last?["access"] as? String == "granted")
    }
    @Test("新增路由到项目或默认列表，返回目标列表对应项目，错误只回复一次")
    func addRouting() throws {
        let f = try Fixture(); defer { f.cleanup() }; f.store.start()
        var results: [Result<TodoItem, BridgeError>] = []
        f.store.add(text: "  fixture \n", projectId: "desktop-shell") { results.append($0) }
        #expect(results == [.success(TodoItem(id: "new-id", text: "fixture", done: false, projectId: "desktop-shell", due: nil))])
        #expect(f.backend.writes.first?.1 == "list")
        f.backend.defaultID = "list"
        f.store.add(text: "default", projectId: nil) { results.append($0) }
        #expect(try results.last?.get().projectId == "desktop-shell")
        f.backend.calendars = [("default", "Default")]; f.backend.defaultID = "default"
        f.store.add(text: "fallback", projectId: "desktop-shell") { results.append($0) }
        #expect(f.backend.writes.last?.1 == "default")
        f.store.add(text: "x", projectId: "missing") { results.append($0) }; #expect(results.last == .failure(.notFound))
        f.backend.defaultID = nil
        f.store.add(text: "x", projectId: nil) { results.append($0) }; #expect(results.last == .failure(.failed))
        f.backend.defaultID = "default"; f.backend.writeError = .failed
        f.store.add(text: "x", projectId: nil) { results.append($0) }; #expect(results.last == .failure(.failed))
        #expect(results.count == 6 && f.backend.writes.count == 3)
    }
    @Test("勾选与取消只传递指定 id 和状态，缺失和保存错误区分，停止后拒绝")
    func setDoneErrors() throws {
        let f = try Fixture(); defer { f.cleanup() }; f.store.start()
        var successes = 0; var failures: [BridgeError] = []
        let reply: (Result<Void, BridgeError>) -> Void = { if case .failure(let e) = $0 { failures.append(e) } else { successes += 1 } }
        f.store.setDone(id: "todo-1", done: true, reply: reply); f.store.setDone(id: "todo-1", done: false, reply: reply)
        #expect(f.backend.updates.map { $0.0 } == ["todo-1", "todo-1"] && f.backend.updates.map { $0.1 } == [true, false])
        f.backend.writeError = .notFound; f.store.setDone(id: "missing", done: true, reply: reply)
        f.backend.writeError = .failed; f.store.setDone(id: "todo-1", done: true, reply: reply)
        f.store.stop(); f.backend.writeError = nil; f.store.setDone(id: "todo-1", done: true, reply: reply)
        #expect(successes == 2 && failures == [.notFound, .failed, .failed] && f.backend.updates.count == 2)
    }
    @Test("EventKit 授权状态映射含未来值降为 denied")
    func accessMapping() {
        #expect(EventKitRemindersBackend.accessName(.notDetermined) == "notDetermined")
        #expect(EventKitRemindersBackend.accessName(.restricted) == "restricted")
        #expect(EventKitRemindersBackend.accessName(.denied) == "denied")
        #expect(EventKitRemindersBackend.accessName(.fullAccess) == "granted")
        #expect(EventKitRemindersBackend.accessName(.writeOnly) == "writeOnly")
        #expect(EventKitRemindersBackend.accessName(EKAuthorizationStatus(rawValue: 1000)!) == "denied")
    }
}
