import Foundation

enum WebNavigationPolicy {
    static func allows(url: URL?, targetIsMainFrame: Bool?, sourceScheme: String, sourceHost: String) -> Bool {
        if url?.scheme == "shell" { return true }
        // The native self-check needs a loaded child frame to verify Bridge's
        // main-frame restriction. Do not broaden this to other about URLs.
        return url?.absoluteString == "about:srcdoc" && targetIsMainFrame == false
            && sourceScheme == "shell" && sourceHost == "app"
    }
}

enum BridgeOrigin {
    static func isTrusted(isMainFrame: Bool, scheme: String, host: String) -> Bool {
        isMainFrame && scheme == "shell" && host == "app"
    }
}

enum BridgeError: String, Error {
    case untrusted, invalid, unknownAction = "unknown-action", notFound = "not-found", failed
}

enum BridgeRequest: Equatable {
    case getConfig
    case setHitRegions([[Double]])

    static func parse(_ body: Any) -> Result<BridgeRequest, BridgeError> {
        guard let body = body as? [String: Any], let action = body["action"] as? String else {
            return .failure(.invalid)
        }
        switch action {
        case "getConfig":
            guard Set(body.keys) == ["action"] else { return .failure(.invalid) }
            return .success(.getConfig)
        case "setHitRegions":
            // Validate with the existing parser, but retain raw coordinates until the
            // receiving web view's actual viewport is available for clipping.
            guard Set(body.keys) == ["action", "regions"],
                  HitTesting.parseRegions(body["regions"], viewport: .zero) != nil,
                  let rows = body["regions"] as? [[NSNumber]] else { return .failure(.invalid) }
            return .success(.setHitRegions(rows.map { $0.map(\.doubleValue) }))
        default:
            return .failure(.unknownAction)
        }
    }
}

enum ConfigReply {
    static func make(config: AppConfig, avatars: [MediaItem], backgrounds: [MediaItem], uiState: UiState) -> [String: Any] {
        // Build an explicit public projection instead of serializing the private config.
        let projects: [[String: Any]] = config.projects.map {
            ["id": $0.id, "name": $0.name, "tags": $0.tags ?? [], "apps": $0.apps ?? [],
             "hasReminders": !($0.remindersList?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)]
        }
        let greetings: [[String: Any]] = config.greetings.map {
            ["from": $0.from, "title": $0.title, "wish": $0.wish]
        }
        let publicUI: [String: Any] = [
            "avatarId": uiState.avatarId.map { $0 as Any } ?? NSNull(),
            "backgroundId": uiState.backgroundId.map { $0 as Any } ?? NSNull(),
            "voiceEnabled": uiState.voiceEnabled,
        ]
        return [
            "config": [
                "character": ["name": config.character.name], "greetings": greetings,
                "projects": projects, "apps": config.apps.map { ["id": $0.id, "name": $0.name] },
            ],
            "media": [
                "avatars": avatars.map { ["id": $0.id, "url": $0.url] },
                "backgrounds": backgrounds.map { ["id": $0.id, "url": $0.url] },
            ],
            "uiState": publicUI,
        ]
    }
}
