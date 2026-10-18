import Foundation

@MainActor
final class AppState {
    let paths: AppPaths
    private(set) var config: AppConfig
    var uiState: UiState
    var onUiStateChanged: ((UiState) -> Void)?
    let uiStateStore: UiStateStore

    init(paths: AppPaths) {
        self.paths = paths
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

    func reloadConfig() {
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
