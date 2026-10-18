import Foundation

@MainActor
final class AppState {
    let paths: AppPaths
    private(set) var config: AppConfig
    var uiState: UiState
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
}
