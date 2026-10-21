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
    private let appIcons: AppIcons
    private let projectHome: URL
    private let iconQueue = DispatchQueue(label: "DesktopShell.app-icons", qos: .userInitiated)
    private var iconGeneration = 0
    private var exportingIcons = false
    private var exportedIconIDs = Set<String>()
    private var iconWaiters: [(Set<String>) -> Void] = []

    init(paths: AppPaths, appIcons: AppIcons = AppIcons(),
         projectHome: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.paths = paths
        self.appIcons = appIcons
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

    func exportAppIcons() {
        iconGeneration += 1
        let generation = iconGeneration
        let apps = config.apps
        let mediaDir = paths.mediaDir
        let exporter = appIcons
        exportingIcons = true
        // Serialize file publication so an older reload can never overwrite newer icons.
        iconQueue.async { [weak self] in
            let ids = exporter.export(apps: apps, mediaDir: mediaDir)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.iconGeneration == generation else { return }
                self.exportedIconIDs = ids
                self.exportingIcons = false
                let waiters = self.iconWaiters
                self.iconWaiters.removeAll()
                for reply in waiters { reply(ids) }
            }
        }
    }

    func withAppIcons(_ reply: @escaping (Set<String>) -> Void) {
        if exportingIcons { iconWaiters.append(reply) }
        else { reply(exportedIconIDs) }
    }

    func saveUiState() throws {
        try uiStateStore.save(uiState)
    }

    func addProject(path: String) -> Result<AppConfig.Project, BridgeError> {
        let store = ConfigStore(supportDir: paths.supportDir)
        do {
            var updated = try store.loadUnfiltered()
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
            try saveProjects(updated, store: store)
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
            var updated = try store.loadUnfiltered()
            guard let index = updated.projects.firstIndex(where: { $0.id == id }) else {
                Log.error("DesktopShell project: remove rejected code=not-found")
                return .failure(.notFound)
            }
            updated.projects.remove(at: index)
            try saveProjects(updated, store: store)
            Log.notice("DesktopShell project: removed id=\(id)")
            return .success(())
        } catch {
            Log.error("DesktopShell project: remove rejected code=failed")
            return .failure(.failed)
        }
    }

    private func saveProjects(_ updated: AppConfig, store: ConfigStore) throws {
        try store.save(updated)
        config = try store.load()
        remindersStore?.configDidReload()
        onConfigChanged?()
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
