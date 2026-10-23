import Foundation

enum ProjectPreferences {
    static func orderedProjects(_ config: AppConfig) -> [AppConfig.Project] {
        var seen = Set<String>()
        return ((config.projectOrder ?? []).compactMap { id in config.projects.first { $0.id == id } }
            + config.projects).filter { seen.insert($0.id).inserted }
    }

    static func updating(_ project: AppConfig.Project, name: String?,
                         reminderList: UiPatch) -> Result<AppConfig.Project, BridgeError> {
        var result = project
        if let name {
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 100 else { return .failure(.invalid) }
            result.name = value
        }
        switch reminderList {
        case .unchanged: break
        case .clear: result.remindersList = nil; result.remindersListId = nil
        case .set(let id): result.remindersListId = id; result.remindersList = nil
        }
        return .success(result)
    }
}
