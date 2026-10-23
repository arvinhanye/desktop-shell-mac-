import Foundation

@MainActor
final class AppState {
    var remindersStore: RemindersStore?
    let paths: AppPaths
    private(set) var config: AppConfig
    var uiState: UiState
    var onUiStateChanged: ((UiState) -> Void)?
    var onConfigChanged: (() -> Void)?
    let uiStateStore: UiStateStore
    private let projectHome: URL
    init(paths: AppPaths,
         projectHome: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.paths = paths
        self.projectHome = projectHome.resolvingSymlinksInPath().standardizedFileURL
        uiStateStore = UiStateStore(supportDir: paths.supportDir)
        uiState = uiStateStore.load()
        do {
            config = try ConfigStore(supportDir: paths.supportDir).load()
        } catch {
            Log.error("DesktopShell: configuration load failed, using in-memory example: \(String(describing: error))")
            config = .example
        }
    }

    func saveUiState() throws {
        try uiStateStore.save(uiState)
    }

    func addProject(path: String) -> Result<AppConfig.Project, BridgeError> {
        let store = ConfigStore(supportDir: paths.supportDir)
        do {
            let previous = try store.loadUnfiltered()
            var updated = previous
            let folder: URL
            switch ProjectEditing.resolve(path, home: projectHome, existing: updated.projects.map(\.path),
                                          fileSystem: LocalProjectFileSystem()) {
            case .failure(let error):
                Log.error("DesktopShell project: add rejected code=\(error.bridgeError.rawValue)")
                return .failure(error.bridgeError)
            case .success(let resolved): folder = resolved
            }
            let project = ProjectEditing.newProject(folder: folder, home: projectHome, config: updated)
            updated.projects.append(project)
            if previous.projectOrder != nil {
                updated.projectOrder = ProjectPreferences.orderedProjects(ConfigStore.filtered(previous)).map(\.id) + [project.id]
            }
            try saveProjects(updated, replacing: previous, store: store)
            Log.notice("DesktopShell project: added id=\(project.id) path=\(project.path)")
            return .success(project)
        } catch {
            Log.error("DesktopShell project: add rejected code=failed")
            return .failure(.failed)
        }
    }

    func removeProject(id: String) -> Result<Void, BridgeError> {
        let store = ConfigStore(supportDir: paths.supportDir)
        do {
            let previous = try store.loadUnfiltered()
            var updated = previous
            guard let index = updated.projects.firstIndex(where: { $0.id == id }) else {
                Log.error("DesktopShell project: remove rejected code=not-found")
                return .failure(.notFound)
            }
            updated.projects.remove(at: index)
            updated.projectOrder?.removeAll { $0 == id }
            try saveProjects(updated, replacing: previous, store: store)
            Log.notice("DesktopShell project: removed id=\(id)")
            return .success(())
        } catch {
            Log.error("DesktopShell project: remove rejected code=failed")
            return .failure(.failed)
        }
    }

    private func saveProjects(_ updated: AppConfig, replacing previous: AppConfig, store: ConfigStore) throws {
        try store.saveProjects(updated, replacing: previous)
        config = ConfigStore.filtered(updated)
        remindersStore?.configDidReload()
        onConfigChanged?()
    }

    func projectEditOptions(projectId: String) -> Result<[String: Any], BridgeError> {
        do {
            let latest = ConfigStore.filtered(try ConfigStore(supportDir: paths.supportDir).loadUnfiltered())
            guard let project = latest.projects.first(where: { $0.id == projectId }) else { return .failure(.notFound) }
            if let remindersStore {
                return .success(remindersStore.projectEditOptions(project: project, projects: latest.projects))
            }
            return .success(["project": ["id": project.id, "name": project.name],
                             "access": "unknown", "binding": ["status": "unavailable", "optionId": NSNull()],
                             "lists": []])
        } catch { return .failure(.failed) }
    }

    func updateProject(projectId: String, name: String?,
                       reminderListOption: UiPatch) -> Result<AppConfig.Project, BridgeError> {
        guard name != nil || reminderListOption != .unchanged else { return .failure(.invalid) }
        let store = ConfigStore(supportDir: paths.supportDir)
        do {
            let previous = try store.loadUnfiltered()
            var updated = previous
            guard isValidID(projectId), let index = updated.projects.firstIndex(where: { $0.id == projectId }) else {
                return .failure(.notFound)
            }
            var patch = reminderListOption
            if case .set(let option) = patch {
                guard let remindersStore else { return .failure(.failed) }
                patch = .set(try remindersStore.resolveReminderOption(option, projectId: projectId,
                    projects: ConfigStore.filtered(previous).projects).get())
            }
            let project = try ProjectPreferences.updating(updated.projects[index], name: name,
                reminderList: patch).get()
            updated.projects[index] = project
            try saveProjects(updated, replacing: previous, store: store)
            return .success(project)
        } catch { return .failure(error as? BridgeError ?? .failed) }
    }

    func reorderProjects(projectIds: [String]) -> Result<Void, BridgeError> {
        guard projectIds.allSatisfy(isValidID), Set(projectIds).count == projectIds.count else { return .failure(.invalid) }
        let store = ConfigStore(supportDir: paths.supportDir)
        do {
            let previous = try store.loadUnfiltered()
            guard Set(projectIds) == Set(ConfigStore.filtered(previous).projects.map(\.id)) else { return .failure(.notFound) }
            var updated = previous
            updated.projectOrder = projectIds
            try saveProjects(updated, replacing: previous, store: store)
            return .success(())
        } catch { return .failure(.failed) }
    }

    func reloadConfig() {
        defer { remindersStore?.configDidReload() }
        do {
            // Reload must not use ConfigStore's first-launch example generation.
            guard FileManager.default.fileExists(atPath: paths.supportDir.appendingPathComponent("config.json").path) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            config = try ConfigStore(supportDir: paths.supportDir).load()
        } catch {
            Log.error("DesktopShell: configuration reload failed, keeping current configuration")
        }
    }

    func toggleVoice() {
        uiState.voiceEnabled.toggle()
        do {
            try saveUiState()
        } catch {
            // Persistence failure must not undo an explicit runtime preference.
            Log.error("DesktopShell: voice state save failed")
        }
        Log.notice("DesktopShell: voice enabled=\(uiState.voiceEnabled ? "true" : "false")")
        onUiStateChanged?(uiState)
    }

    func updateAppearance(avatar: UiPatch, background: UiPatch) -> Result<UiState, BridgeError> {
        let avatars = MediaLibrary.scan(mediaDir: paths.mediaDir, subdirectory: "avatars")
        let backgrounds = MediaLibrary.scan(mediaDir: paths.mediaDir, subdirectory: "backgrounds")
        switch UiStateUpdate.apply(to: uiState, avatar: avatar, background: background,
                                  avatars: avatars, backgrounds: backgrounds) {
        case .failure(let error):
            return .failure(error)
        case .success(let updated):
            let previous = uiState
            uiState = updated
            do {
                try saveUiState()
                onUiStateChanged?(updated)
                return .success(updated)
            } catch {
                uiState = previous
                return .failure(.failed)
            }
        }
    }
}

enum UiStateUpdate {
    static func apply(to state: UiState, avatar: UiPatch, background: UiPatch,
                      avatars: [MediaItem], backgrounds: [MediaItem]) -> Result<UiState, BridgeError> {
        guard avatar != .unchanged || background != .unchanged else { return .failure(.invalid) }
        for patch in [avatar, background] {
            if case .set(let id) = patch, !isValidID(id) { return .failure(.invalid) }
        }
        var updated = state
        switch avatar {
        case .unchanged: break
        case .clear: updated.avatarId = nil
        case .set(let id):
            guard avatars.contains(where: { $0.id == id }) else { return .failure(.notFound) }
            updated.avatarId = id
        }
        switch background {
        case .unchanged: break
        case .clear: updated.backgroundId = nil
        case .set(let id):
            guard backgrounds.contains(where: { $0.id == id }) else { return .failure(.notFound) }
            updated.backgroundId = id
        }
        return .success(updated)
    }
}
