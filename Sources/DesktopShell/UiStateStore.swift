import Foundation

struct UiState: Codable, Equatable {
    var avatarId: String? = nil
    var backgroundId: String? = nil
    var voiceEnabled: Bool = true
    var desktopIconsHidden: Bool = false

    private enum CodingKeys: String, CodingKey {
        case avatarId, backgroundId, voiceEnabled, desktopIconsHidden
    }
}

extension UiState {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        avatarId = try values.decodeIfPresent(String.self, forKey: .avatarId)
        backgroundId = try values.decodeIfPresent(String.self, forKey: .backgroundId)
        voiceEnabled = try values.decodeIfPresent(Bool.self, forKey: .voiceEnabled) ?? true
        desktopIconsHidden = try values.decodeIfPresent(Bool.self, forKey: .desktopIconsHidden) ?? false
    }
}

struct UiStateStore {
    let supportDir: URL

    func load() -> UiState {
        do {
            let data = try Data(contentsOf: supportDir.appendingPathComponent("ui.json"))
            return try JSONDecoder().decode(UiState.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return UiState()
        } catch {
            Log.error("DesktopShell: UI state load failed, using defaults: \(String(describing: error))")
            return UiState()
        }
    }

    func save(_ state: UiState) throws {
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: supportDir.appendingPathComponent("ui.json"), options: .atomic)
    }
}
