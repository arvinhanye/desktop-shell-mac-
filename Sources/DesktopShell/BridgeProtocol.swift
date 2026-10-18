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
    case openProject(String)
    case openProjectWith(projectId: String, appId: String)
    case launchApp(String)
    case saveUiState(avatar: UiPatch, background: UiPatch)

    static func parse(_ body: Any) -> Result<BridgeRequest, BridgeError> {
        guard let body = body as? [String: Any], let action = body["action"] as? String else {
            return .failure(.invalid)
        }
        switch action {
        case "getConfig":
            guard Set(body.keys) == ["action"] else { return .failure(.invalid) }
            return .success(.getConfig)
        case "openProject":
            guard Set(body.keys) == ["action", "projectId"],
                  let id = validID(body["projectId"]) else { return .failure(.invalid) }
            return .success(.openProject(id))
        case "openProjectWith":
            guard Set(body.keys) == ["action", "projectId", "appId"],
                  let project = validID(body["projectId"]),
                  let app = validID(body["appId"]) else { return .failure(.invalid) }
            return .success(.openProjectWith(projectId: project, appId: app))
        case "launchApp":
            guard Set(body.keys) == ["action", "appId"],
                  let id = validID(body["appId"]) else { return .failure(.invalid) }
            return .success(.launchApp(id))
        case "saveUiState":
            guard Set(body.keys).isSubset(of: ["action", "avatarId", "backgroundId"]),
                  body.count > 1,
                  let avatar = UiPatch.parse(body["avatarId"]),
                  let background = UiPatch.parse(body["backgroundId"]) else { return .failure(.invalid) }
            return .success(.saveUiState(avatar: avatar, background: background))
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

    private static func validID(_ value: Any?) -> String? {
        guard let id = value as? String, isValidID(id) else { return nil }
        return id
    }
}

enum UiPatch: Equatable {
    case unchanged, clear, set(String)

    static func parse(_ value: Any?) -> UiPatch? {
        guard let value else { return .unchanged }
        if value is NSNull { return .clear }
        guard let id = value as? String, isValidID(id) else { return nil }
        return .set(id)
    }
}

enum ConfigReply {
    static func makeUiState(_ state: UiState) -> [String: Any] {
        ["avatarId": state.avatarId.map { $0 as Any } ?? NSNull(),
         "backgroundId": state.backgroundId.map { $0 as Any } ?? NSNull(),
         "voiceEnabled": state.voiceEnabled]
    }

    static func make(config: AppConfig, avatars: [MediaItem], backgrounds: [MediaItem], uiState: UiState) -> [String: Any] {
        // Build an explicit public projection instead of serializing the private config.
        let projects: [[String: Any]] = config.projects.map {
            ["id": $0.id, "name": $0.name, "tags": $0.tags ?? [], "apps": $0.apps ?? [],
             "hasReminders": !($0.remindersList?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)]
        }
        let greetings: [[String: Any]] = config.greetings.map {
            ["from": $0.from, "title": $0.title, "wish": $0.wish]
        }
        return [
            "config": [
                "character": ["name": config.character.name], "greetings": greetings,
                "projects": projects, "apps": config.apps.map { ["id": $0.id, "name": $0.name] },
            ],
            "media": [
                "avatars": avatars.map { ["id": $0.id, "url": $0.url] },
                "backgrounds": backgrounds.map { ["id": $0.id, "url": $0.url] },
            ],
            "uiState": makeUiState(uiState),
        ]
    }
}

enum PageEvent {
    static func safeArea(_ insets: SafeAreaInsets) -> [String: Any] {
        ["event": "safeArea", "top": insets.top, "right": insets.right,
         "bottom": insets.bottom, "left": insets.left]
    }

    static func paused(_ paused: Bool) -> [String: Any] {
        ["event": "paused", "paused": paused]
    }

    static func uiState(_ state: UiState) -> [String: Any] {
        var event = ConfigReply.makeUiState(state)
        event["event"] = "uiState"
        return event
    }
}

extension PageEvent {
    static func systemStats(battery: BatteryStatus, cpu: Double, memory: MemoryUsage) -> [String: Any] {
        ["event": "systemStats",
         "battery": ["level": battery.level.map { $0 as Any } ?? NSNull(),
                     "charging": battery.isCharging, "onBattery": battery.onBattery],
         "cpu": cpu,
         "memory": ["usedBytes": memory.usedBytes, "totalBytes": memory.totalBytes, "percent": memory.percent]]
    }
}
