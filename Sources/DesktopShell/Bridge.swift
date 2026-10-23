import WebKit

@MainActor
final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var window: WidgetWindow?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        let origin = message.frameInfo.securityOrigin
        guard BridgeOrigin.isTrusted(isMainFrame: message.frameInfo.isMainFrame, scheme: origin.protocol, host: origin.host) else {
            // Do not inspect an untrusted frame's body, even for logging.
            reject(.untrusted, action: "?", replyHandler: replyHandler)
            return
        }
        let candidate = (message.body as? [String: Any])?["action"] as? String
        let action = candidate.flatMap { isValidID($0) && $0.count <= 64 ? $0 : nil } ?? "?"
        switch BridgeRequest.parse(message.body) {
        case .failure(let error):
            reject(error, action: action, replyHandler: replyHandler)
        case .success(.getProjectEditOptions(let id)):
            switch appState.projectEditOptions(projectId: id) {
            case .success(let options): replyHandler(options, nil)
            case .failure(let error): reject(error, action: action, replyHandler: replyHandler)
            }
        case .success(.updateProject(let id, let name, let patch)):
            switch appState.updateProject(projectId: id, name: name, reminderListOption: patch) {
            case .success(let project): replyHandler(ConfigReply.makeProject(project), nil)
            case .failure(let error): reject(error, action: action, replyHandler: replyHandler)
            }
        case .success(.reorderProjects(let ids)):
            switch appState.reorderProjects(projectIds: ids) {
            case .success: replyHandler(NSNull(), nil)
            case .failure(let error): reject(error, action: action, replyHandler: replyHandler)
            }
        case .success(.addProject(let path)):
            switch appState.addProject(path: path) {
            case .success(let project): replyHandler(ConfigReply.makeProject(project), nil)
            case .failure(let error): reject(error, action: action, replyHandler: replyHandler)
            }
        case .success(.removeProject(let id)):
            switch appState.removeProject(id: id) {
            case .success: replyHandler(NSNull(), nil)
            case .failure(let error): reject(error, action: action, replyHandler: replyHandler)
            }
        case .success(.addTodo(let text, let projectId)):
            guard let reminders = appState.remindersStore else {
                reject(.failed, action: action, replyHandler: replyHandler)
                return
            }
            reminders.add(text: text, projectId: projectId) { result in
                switch result {
                case .success(let item):
                    Log.notice("DesktopShell bridge: addTodo ok")
                    replyHandler(PageEvent.todoItem(item), nil)
                case .failure(let error): self.reject(error, action: action, replyHandler: replyHandler)
                }
            }
        case .success(.setTodoDone(let id, let done)):
            guard let reminders = appState.remindersStore else {
                reject(.failed, action: action, replyHandler: replyHandler)
                return
            }
            reminders.setDone(id: id, done: done) { result in
                switch result {
                case .success:
                    Log.notice("DesktopShell bridge: setTodoDone ok")
                    replyHandler(NSNull(), nil)
                case .failure(let error): self.reject(error, action: action, replyHandler: replyHandler)
                }
            }
        case .success(.getConfig):
            let avatars = MediaLibrary.scan(mediaDir: appState.paths.mediaDir, subdirectory: "avatars")
            let backgrounds = MediaLibrary.scan(mediaDir: appState.paths.mediaDir, subdirectory: "backgrounds")
            let voices = MediaLibrary.scan(mediaDir: appState.paths.mediaDir, subdirectory: "voice", extensions: ["mp3"])
            Log.notice("DesktopShell bridge: getConfig avatars=\(avatars.count) backgrounds=\(backgrounds.count) voices=\(voices.count)")
            replyHandler(ConfigReply.make(config: appState.config, avatars: avatars,
                backgrounds: backgrounds, voices: voices, uiState: appState.uiState), nil)
        case .success(.focusInput):
            guard let window, let webView = message.webView else {
                reject(.failed, action: action, replyHandler: replyHandler)
                return
            }
            window.acceptsKeyboard = true
            window.makeKey()
            window.makeFirstResponder(webView)
            Log.notice("DesktopShell bridge: focusInput ok")
            replyHandler(nil, nil)
        case .success(.blurInput):
            guard let window else {
                reject(.failed, action: action, replyHandler: replyHandler)
                return
            }
            window.acceptsKeyboard = false
            if window.isKeyWindow { NSApp.deactivate() }
            Log.notice("DesktopShell bridge: blurInput ok")
            replyHandler(nil, nil)
        case .success(.setGlassRegions(let regions)):
            guard let window, let webView = message.webView else {
                reject(.failed, action: action, replyHandler: replyHandler)
                return
            }
            window.setGlassRegions(GlassRegions.clip(regions, viewport: webView.bounds.size))
            replyHandler(nil, nil)
        case .success(.setDropRegions(let values)):
            guard let window, let webView = message.webView else {
                reject(.failed, action: action, replyHandler: replyHandler)
                return
            }
            guard let regions = HitTesting.parseRegions(values, viewport: webView.bounds.size) else {
                reject(.invalid, action: action, replyHandler: replyHandler)
                return
            }
            window.setDropRegions(regions)
            replyHandler(nil, nil)
        case .success(.setHitRegions(let values)):
            guard let window, let webView = message.webView else {
                reject(.failed, action: action, replyHandler: replyHandler)
                return
            }
            guard let regions = HitTesting.parseRegions(values, viewport: webView.bounds.size) else {
                reject(.invalid, action: action, replyHandler: replyHandler)
                return
            }
            window.setHitRegions(regions)
            replyHandler(nil, nil)
        case .success(.openProject(let projectId)):
            guard let directory = projectDirectory(projectId) else {
                reject(.notFound, action: action, replyHandler: replyHandler)
                return
            }
            completeOpen(action: action, ids: projectId, failed: !NSWorkspace.shared.open(directory), replyHandler: replyHandler)
        case .success(.saveUiState(let avatar, let background)):
            switch appState.updateAppearance(avatar: avatar, background: background) {
            case .failure(let error):
                reject(error, action: action, replyHandler: replyHandler)
            case .success(let state):
                Log.notice("DesktopShell bridge: saveUiState ok")
                replyHandler(ConfigReply.makeUiState(state), nil)
            }
        }
    }

    private func projectDirectory(_ id: String) -> URL? {
        guard let project = appState.config.projects.first(where: { $0.id == id }),
              let url = ProjectPath.resolve(project.path, home: FileManager.default.homeDirectoryForCurrentUser) else { return nil }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { return nil }
        return url
    }

    private func completeOpen(action: String, ids: String, failed: Bool, replyHandler: @MainActor @Sendable (Any?, String?) -> Void) {
        if failed {
            reject(.failed, action: action, replyHandler: replyHandler)
        } else {
            Log.notice("DesktopShell bridge: \(action) \(ids) ok")
            replyHandler(nil, nil)
        }
    }

    private func reject(_ error: BridgeError, action: String, replyHandler: @MainActor @Sendable (Any?, String?) -> Void) {
        Log.error("DesktopShell bridge: \(action) rejected: \(error.rawValue)")
        replyHandler(nil, error.rawValue)
    }
}

// WKUserContentController retains this proxy, not the window's bridge.
@MainActor
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    private weak var target: WKScriptMessageHandlerWithReply?

    init(_ target: WKScriptMessageHandlerWithReply) { self.target = target }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let target else {
            Log.error("DesktopShell bridge: ? rejected: failed")
            replyHandler(nil, BridgeError.failed.rawValue)
            return
        }
        target.userContentController(userContentController, didReceive: message, replyHandler: replyHandler)
    }
}
