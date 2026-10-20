import AppKit
import ServiceManagement

enum LoginItemStatus: String {
    case enabled, requiresApproval, notRegistered, notFound, unknown
}

enum LaunchAtLogin {
    static func menuState(_ status: LoginItemStatus) -> NSControl.StateValue {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .mixed
        case .notRegistered, .notFound, .unknown: return .off
        }
    }

    enum Action: String, Equatable {
        case register, unregister, openSettings
    }

    static func action(for status: LoginItemStatus) -> Action {
        switch status {
        case .enabled: return .unregister
        case .requiresApproval: return .openSettings
        case .notRegistered, .notFound, .unknown: return .register
        }
    }
}

/// No local preference or cached status: System Settings can change it independently.
@MainActor
enum LoginItemService {
    static var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    /// Called only in response to the user's menu action, never at startup.
    static func perform(_ action: LaunchAtLogin.Action) {
        do {
            switch action {
            case .register:
                try SMAppService.mainApp.register()
                // ServiceManagement remembers this copy's path, not just its bundle ID.
                Log.notice("DesktopShell login item: registered path=\(Bundle.main.bundleURL.path)")
            case .unregister:
                try SMAppService.mainApp.unregister()
                Log.notice("DesktopShell login item: unregistered")
            case .openSettings:
                SMAppService.openSystemSettingsLoginItems()
                Log.notice("DesktopShell login item: opened settings")
            }
        } catch {
            let error = error as NSError
            Log.error("DesktopShell login item: \(action.rawValue) failed error=\(error.domain)/\(error.code)")
        }
    }
}
