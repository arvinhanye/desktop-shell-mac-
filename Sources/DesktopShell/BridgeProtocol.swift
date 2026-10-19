import Foundation
import CoreFoundation

enum WebNavigationPolicy {
    static func allows(url: URL?, targetIsMainFrame: Bool?, sourceScheme: String, sourceHost: String) -> Bool {
        url?.scheme == "shell"
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
    case focusInput
    case blurInput
    case addTodo(text: String, projectId: String?)
    case setTodoDone(id: String, done: Bool)
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
        case "addTodo":
            guard Set(body.keys).isSubset(of: ["action", "text", "projectId"]),
                  let rawText = body["text"] as? String else { return .failure(.invalid) }
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 500 else { return .failure(.invalid) }
            var projectId: String?
            if let value = body["projectId"], !(value is NSNull) {
                guard let id = validID(value) else { return .failure(.invalid) }
                projectId = id
            }
            return .success(.addTodo(text: text, projectId: projectId))
        case "setTodoDone":
            guard Set(body.keys) == ["action", "todoId", "done"], let id = validID(body["todoId"]),
                  let done = body["done"] as? NSNumber,
                  CFGetTypeID(done) == CFBooleanGetTypeID() else { return .failure(.invalid) }
            return .success(.setTodoDone(id: id, done: done.boolValue))
        case "getConfig":
            guard Set(body.keys) == ["action"] else { return .failure(.invalid) }
            return .success(.getConfig)
        case "focusInput":
            guard Set(body.keys) == ["action"] else { return .failure(.invalid) }
            return .success(.focusInput)
        case "blurInput":
            guard Set(body.keys) == ["action"] else { return .failure(.invalid) }
            return .success(.blurInput)
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

    static func make(config: AppConfig, avatars: [MediaItem], backgrounds: [MediaItem], voices: [MediaItem] = [], iconIDs: Set<String> = [], uiState: UiState) -> [String: Any] {
        // Build an explicit public projection instead of serializing the private config.
        func trimmedOrNull(_ value: String?) -> Any {
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return NSNull() }
            return text
        }
        let projects: [[String: Any]] = config.projects.map {
            ["id": $0.id, "name": $0.name, "tags": $0.tags ?? [], "apps": $0.apps ?? [],
             "hasReminders": !($0.remindersList?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)]
        }
        let greetings: [[String: Any]] = config.greetings.map {
            ["from": $0.from, "title": $0.title, "wish": $0.wish]
        }
        return [
            "config": [
                "user": ["name": trimmedOrNull(config.user?.name)],
                "character": ["name": config.character.name, "motto": trimmedOrNull(config.character.motto)],
                "greetings": greetings, "projects": projects,
                "apps": config.apps.map { app -> [String: Any] in
                    ["id": app.id, "name": app.name,
                     "iconUrl": iconIDs.contains(app.id) ? "/media/app-icons/\(app.id).png" as Any : NSNull()]
                },
            ],
            "media": [
                "avatars": avatars.map { ["id": $0.id, "url": $0.url] },
                "backgrounds": backgrounds.map { ["id": $0.id, "url": $0.url] },
                "voices": voices.map { ["id": $0.id, "url": $0.url] },
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

extension PageEvent {
    static func todos(access: String, items: [TodoItem]) -> [String: Any] {
        ["event": "todos", "access": access, "items": access == "granted" ? items.map(todoItem) : []]
    }

    static func todoItem(_ item: TodoItem) -> [String: Any] {
        let due: Any = item.due.map {
            ["date": $0.date, "time": $0.time.map { $0 as Any } ?? NSNull()] as [String: Any]
        } ?? NSNull()
        return ["id": item.id, "text": item.text, "done": item.done,
                "projectId": item.projectId.map { $0 as Any } ?? NSNull(), "due": due]
    }
}
