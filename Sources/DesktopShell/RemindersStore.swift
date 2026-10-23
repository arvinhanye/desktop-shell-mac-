import AppKit
import EventKit

struct ReminderListSnapshot: Equatable {
    var id: String
    var title: String
    var sourceTitle: String
    var canWrite: Bool
}

@MainActor
protocol RemindersBackend: AnyObject {
    var access: String { get }
    var changeSource: AnyObject { get }
    func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void)
    func lists() -> [ReminderListSnapshot]
    func defaultListID() -> String?
    func refresh()
    func fetch(completedSince: Date?, completion: @escaping @MainActor ([ReminderSnapshot]?) -> Void)
    func add(text: String, listID: String) throws -> ReminderSnapshot
    func setDone(id: String, done: Bool) throws
}

// All native objects stay inside this boundary; tests substitute an in-memory backend.
@MainActor
final class EventKitRemindersBackend: RemindersBackend {
    private let store = EKEventStore()
    var access: String { Self.accessName(EKEventStore.authorizationStatus(for: .reminder)) }
    var changeSource: AnyObject { store }

    static func accessName(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .fullAccess: return "granted"
        case .writeOnly: return "writeOnly"
        @unknown default:
            Log.error("DesktopShell reminders: unknown-access code=\(status.rawValue)")
            return "denied"
        }
    }

    func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void) {
        store.requestFullAccessToReminders { _, error in
            let failed = error != nil
            Task { @MainActor in completion(failed) }
        }
    }
    func lists() -> [ReminderListSnapshot] {
        store.calendars(for: .reminder).map {
            ReminderListSnapshot(id: $0.calendarIdentifier, title: $0.title,
                sourceTitle: $0.source.title, canWrite: $0.allowsContentModifications)
        }
    }
    func defaultListID() -> String? { store.defaultCalendarForNewReminders()?.calendarIdentifier }
    func refresh() { store.refreshSourcesIfNecessary() }

    func fetch(completedSince: Date?, completion: @escaping @MainActor ([ReminderSnapshot]?) -> Void) {
        let predicate: NSPredicate
        if let completedSince {
            predicate = store.predicateForCompletedReminders(withCompletionDateStarting: completedSince, ending: nil, calendars: nil)
        } else {
            predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        }
        store.fetchReminders(matching: predicate) { reminders in
            let snapshots = reminders?.map(Self.snapshot)
            Task { @MainActor in completion(snapshots) }
        }
    }

    func add(text: String, listID: String) throws -> ReminderSnapshot {
        guard let calendar = store.calendar(withIdentifier: listID) else { throw BridgeError.failed }
        let reminder = EKReminder(eventStore: store)
        reminder.title = text
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
        return Self.snapshot(reminder)
    }
    func setDone(id: String, done: Bool) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { throw BridgeError.notFound }
        reminder.isCompleted = done
        try store.save(reminder, commit: true)
    }
    private nonisolated static func snapshot(_ reminder: EKReminder) -> ReminderSnapshot {
        ReminderSnapshot(id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                         isCompleted: reminder.isCompleted, completionDate: reminder.completionDate,
                         creationDate: reminder.creationDate, due: reminder.dueDateComponents,
                         listId: reminder.calendar.calendarIdentifier)
    }
}

@MainActor
final class RemindersStore {
    typealias Schedule = (TimeInterval, Bool, TimeInterval, @escaping @MainActor () -> Void) -> () -> Void
    var onChange: (([String: Any]) -> Void)?
    private weak var appState: AppState?
    private let backend: RemindersBackend
    private let notifications: NotificationCenter
    private let workspaceNotifications: NotificationCenter
    private let now: () -> Date
    private let calendar: () -> Calendar
    private let schedule: Schedule
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var cancelSync: (() -> Void)?
    private var cancelDebounce: (() -> Void)?
    private var lifecycle: UUID?
    private var readID: UUID?
    private var debounceID: UUID?
    private var lastAccess: String?
    private var lastItems: [TodoItem]?
    private var lastEmittedAccess: String?
    private var optionTokens: [String: String] = [:]

    init(appState: AppState, backend: RemindersBackend? = nil,
         notifications: NotificationCenter = .default,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         now: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .current },
         schedule: @escaping Schedule = { interval, repeats, tolerance, action in
             let timer = Timer(timeInterval: interval, repeats: repeats) { _ in MainActor.assumeIsolated { action() } }
             timer.tolerance = tolerance
             RunLoop.main.add(timer, forMode: .common)
             return { timer.invalidate() }
         }) {
        self.appState = appState
        self.backend = backend ?? EventKitRemindersBackend()
        self.notifications = notifications
        self.workspaceNotifications = workspaceNotifications
        self.now = now; self.calendar = calendar; self.schedule = schedule
    }

    func start() {
        guard lifecycle == nil else { return }
        let id = UUID(); lifecycle = id
        processAccess()
        if backend.access == "notDetermined" {
            backend.requestAccess { [weak self] failed in
                guard let self, self.lifecycle == id else { return }
                if failed { Log.error("DesktopShell reminders: access-request failed") }
                self.processAccess()
            }
        }
    }

    func stop() {
        lifecycle = nil; readID = nil; debounceID = nil
        cancelSync?(); cancelSync = nil
        cancelDebounce?(); cancelDebounce = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        lastAccess = nil; lastItems = nil; lastEmittedAccess = nil
    }
    deinit {
        cancelSync?(); cancelDebounce?()
        for (center, token) in observers { center.removeObserver(token) }
    }

    func configDidReload() {
        guard lifecycle != nil else { return }
        processAccess()
    }

    private func checkAccess() -> Bool {
        let access = backend.access
        if access != lastAccess { Log.notice("DesktopShell reminders: access=\(access)"); lastAccess = access }
        guard access == "granted" else {
            readID = nil; debounceID = nil; cancelDebounce?(); cancelDebounce = nil
            publish(access: access, items: [])
            return false
        }
        return true
    }

    private func processAccess() {
        let previous = lastAccess
        guard checkAccess() else { return }
        observeChanges()
        if previous != "granted" { backend.refresh() }
        read()
    }

    private func observeChanges() {
        guard observers.isEmpty, let id = lifecycle else { return }
        observe(notifications, .EKEventStoreChanged, object: backend.changeSource) { $0.debounceRead() }
        observe(notifications, .NSCalendarDayChanged) { $0.processAccess() }
        observe(workspaceNotifications, NSWorkspace.screensDidWakeNotification) { $0.synchronize() }
        observe(workspaceNotifications, NSWorkspace.sessionDidBecomeActiveNotification) { $0.synchronize() }
        cancelSync = schedule(300, true, 60) { [weak self] in
            guard let self, self.lifecycle == id else { return }
            self.synchronize()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil,
                         action: @escaping @MainActor (RemindersStore) -> Void) {
        let id = lifecycle
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.lifecycle == id, id != nil else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    private func synchronize() {
        let previous = lastAccess
        guard checkAccess() else { return }
        backend.refresh()
        // Ordinary sync relies on EventKit's change event; restored access needs an initial read.
        if previous != "granted" { read() }
    }

    private func debounceRead() {
        guard lifecycle != nil, checkAccess() else { return }
        cancelDebounce?()
        let id = UUID(); debounceID = id
        cancelDebounce = schedule(0.5, false, 0) { [weak self] in
            guard let self, self.lifecycle != nil, self.debounceID == id else { return }
            self.debounceID = nil; self.cancelDebounce = nil
            self.read()
        }
    }

    private func read() {
        guard lifecycle != nil, checkAccess(), let appState else { return }
        let id = UUID(); readID = id
        let instant = now(), calendar = calendar()
        let mapping = TodoItems.listToProject(projects: appState.config.projects, lists: backend.lists().map { ($0.id, $0.title) })
        var batches: [Int: [ReminderSnapshot]] = [:]
        let receive: @MainActor (Int, [ReminderSnapshot]?) -> Void = { [weak self] index, snapshots in
            guard let self, self.lifecycle != nil, self.readID == id, self.checkAccess() else { return }
            guard let snapshots else {
                self.readID = nil
                Log.error("DesktopShell reminders: read failed")
                return
            }
            batches[index] = snapshots
            guard let open = batches[0], let completed = batches[1] else { return }
            self.readID = nil
            // A reminder can move between the two asynchronous query results.
            var unique: [String: ReminderSnapshot] = [:]
            for snapshot in open + completed { unique[snapshot.id] = snapshot }
            let items = TodoItems.make(Array(unique.values), listToProject: mapping, now: instant, calendar: calendar)
            self.publish(access: "granted", items: items)
        }
        backend.fetch(completedSince: nil) { receive(0, $0) }
        backend.fetch(completedSince: calendar.startOfDay(for: instant)) { receive(1, $0) }
    }

    private func publish(access: String, items: [TodoItem]) {
        guard lastEmittedAccess != access || lastItems != items else { return }
        lastEmittedAccess = access; lastItems = items
        onChange?(PageEvent.todos(access: access, items: items))
        Log.notice("DesktopShell reminders: pushed items=\(items.count)")
    }

    private func refreshOptions(_ lists: [ReminderListSnapshot]) {
        let ids = Set(lists.map(\.id))
        optionTokens = optionTokens.filter { ids.contains($0.key) }
        for list in lists where optionTokens[list.id] == nil { optionTokens[list.id] = UUID().uuidString }
    }

    func projectEditOptions(project: AppConfig.Project, projects: [AppConfig.Project]) -> [String: Any] {
        let access = lifecycle == nil ? "unknown" : backend.access
        let lists = access == "granted" ? backend.lists() : []
        refreshOptions(lists)
        let pairs = lists.map { ($0.id, $0.title) }
        let mapping = TodoItems.listToProject(projects: projects, lists: pairs)
        let bound = TodoItems.boundListID(project, lists: pairs)
        let status: String
        if access != "granted" { status = "unavailable" }
        else if let bound, let list = lists.first(where: { $0.id == bound }) {
            if projects.filter({ TodoItems.boundListID($0, lists: pairs) == bound }).count > 1 { status = "shared" }
            else { status = list.canWrite ? "linked" : "read-only" }
        } else {
            let hasBinding = project.remindersListId != nil
                || !(project.remindersList?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            status = hasBinding ? "missing" : "none"
        }
        return ["project": ["id": project.id, "name": project.name],
                "access": access,
                "binding": ["status": status, "optionId": bound.flatMap { optionTokens[$0] }.map { $0 as Any } ?? NSNull()],
                "lists": lists.map { list -> [String: Any] in
                    ["id": optionTokens[list.id]!, "title": list.title, "source": list.sourceTitle,
                     "canWrite": list.canWrite, "assignedProjectId": mapping[list.id].map { $0 as Any } ?? NSNull()]
                }]
    }

    func resolveReminderOption(_ optionID: String, projectId: String,
                               projects: [AppConfig.Project]) -> Result<String, BridgeError> {
        guard lifecycle != nil, backend.access == "granted" else { return .failure(.failed) }
        let lists = backend.lists()
        refreshOptions(lists)
        guard let raw = optionTokens.first(where: { $0.value == optionID })?.key,
              let list = lists.first(where: { $0.id == raw }) else { return .failure(.notFound) }
        let pairs = lists.map { ($0.id, $0.title) }
        // Check every claimant, not just the first legacy owner in the public mapping.
        guard list.canWrite, !projects.contains(where: {
            $0.id != projectId && TodoItems.boundListID($0, lists: pairs) == raw
        }) else { return .failure(.failed) }
        return .success(raw)
    }

    func add(text: String, projectId: String?, reply: @escaping (Result<TodoItem, BridgeError>) -> Void) {
        guard lifecycle != nil, checkAccess(), let appState else { reply(.failure(.failed)); return }
        let projects = appState.config.projects
        if let projectId, !projects.contains(where: { $0.id == projectId }) { reply(.failure(.notFound)); return }
        let lists = backend.lists()
        let mapping = TodoItems.listToProject(projects: projects, lists: lists.map { ($0.id, $0.title) })
        var projectList = projectId.flatMap { id in mapping.first { $0.value == id }?.key }
        if let project = projects.first(where: { $0.id == projectId }), let id = project.remindersListId {
            guard let list = lists.first(where: { $0.id == id }) else { reply(.failure(.notFound)); return }
            guard list.canWrite else { reply(.failure(.failed)); return }
            projectList = id
        }
        guard let list = projectList ?? backend.defaultListID() else { reply(.failure(.failed)); return }
        do {
            let snapshot = try backend.add(text: text.trimmingCharacters(in: .whitespacesAndNewlines), listID: list)
            reply(.success(TodoItems.item(snapshot, listToProject: mapping)))
            debounceRead()
        } catch {
            Log.error("DesktopShell reminders: add failed")
            reply(.failure(.failed))
        }
    }

    func setDone(id: String, done: Bool, reply: @escaping (Result<Void, BridgeError>) -> Void) {
        guard lifecycle != nil, checkAccess() else { reply(.failure(.failed)); return }
        do {
            try backend.setDone(id: id, done: done)
            reply(.success(()))
            debounceRead()
        } catch {
            let code: BridgeError = (error as? BridgeError) == .notFound ? .notFound : .failed
            Log.error("DesktopShell reminders: setDone \(code.rawValue)")
            reply(.failure(code))
        }
    }
}
