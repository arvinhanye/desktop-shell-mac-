import Foundation

struct ReminderSnapshot: Equatable {
    var id: String
    var title: String
    var isCompleted: Bool
    var completionDate: Date?
    var creationDate: Date?
    var due: DateComponents?
    var listId: String
}

struct TodoItem: Equatable {
    struct Due: Equatable { var date: String; var time: String? }
    var id: String
    var text: String
    var done: Bool
    var projectId: String?
    var due: Due?
}

enum TodoItems {
    static func listToProject(projects: [AppConfig.Project], lists: [(id: String, title: String)]) -> [String: String] {
        var result: [String: String] = [:]
        for project in projects {
            guard let title = project.remindersList,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let matches = lists.filter { $0.title == title }.sorted { $0.id < $1.id }
            guard let list = matches.first else {
                Log.notice("DesktopShell reminders: list-missing project=\(project.id)")
                continue
            }
            if matches.count > 1 { Log.notice("DesktopShell reminders: list-ambiguous project=\(project.id)") }
            guard result[list.id] == nil else {
                Log.notice("DesktopShell reminders: list-shared project=\(project.id)")
                continue
            }
            result[list.id] = project.id
        }
        return result
    }

    static func due(_ components: DateComponents?) -> TodoItem.Due? {
        guard let components, let year = components.year, let month = components.month,
              let day = components.day else { return nil }
        let time: String?
        if let hour = components.hour, let minute = components.minute {
            time = String(format: "%02d:%02d", hour, minute)
        } else { time = nil }
        return TodoItem.Due(date: String(format: "%04d-%02d-%02d", year, month, day), time: time)
    }

    static func make(_ reminders: [ReminderSnapshot], listToProject: [String: String], now: Date, calendar: Calendar) -> [TodoItem] {
        let sorted = reminders.filter { reminder in
            !reminder.isCompleted || reminder.completionDate.map { calendar.isDate($0, inSameDayAs: now) } == true
        }.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            if a.isCompleted {
                if a.completionDate != b.completionDate { return a.completionDate! > b.completionDate! }
            } else {
                let first = deadline(a.due, calendar: calendar), second = deadline(b.due, calendar: calendar)
                if first != second { return first < second }
                let createdA = a.creationDate ?? .distantPast, createdB = b.creationDate ?? .distantPast
                if createdA != createdB { return createdA < createdB }
            }
            return a.id < b.id
        }
        if sorted.count > 500 { Log.notice("DesktopShell reminders: truncated items=\(sorted.count)") }
        return sorted.prefix(500).map { item($0, listToProject: listToProject) }
    }

    static func item(_ snapshot: ReminderSnapshot, listToProject: [String: String]) -> TodoItem {
        TodoItem(id: snapshot.id, text: snapshot.title, done: snapshot.isCompleted,
                 projectId: listToProject[snapshot.listId], due: due(snapshot.due))
    }

    private static func deadline(_ components: DateComponents?, calendar: Calendar) -> Date {
        guard let components, let year = components.year, let month = components.month,
              let day = components.day else { return .distantFuture }
        var calendar = calendar
        if let zone = components.timeZone { calendar.timeZone = zone }
        let timed = components.hour != nil && components.minute != nil
        let value = DateComponents(year: year, month: month, day: day,
                                   hour: timed ? components.hour : 0, minute: timed ? components.minute : 0)
        guard let date = calendar.date(from: value) else { return .distantFuture }
        if timed { return date }
        // Calendar day boundaries, rather than 24 hours, also cover DST changes.
        return calendar.dateInterval(of: .day, for: date)?.end.addingTimeInterval(-0.001) ?? .distantFuture
    }
}
