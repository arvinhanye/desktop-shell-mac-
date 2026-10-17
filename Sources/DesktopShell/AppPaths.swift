import Foundation

struct AppPaths: Equatable {
    let supportDir: URL
    let mediaDir: URL
    let webDir: URL

    static func resolve(
        environment: [String: String],
        bundleResourceURL: URL?,
        currentDirectory: URL,
        home: URL,
        fileExists: (URL) -> Bool
    ) -> AppPaths {
        func directoryOverride(_ key: String) -> URL? {
            guard let value = environment[key], !value.isEmpty else { return nil }
            return URL(fileURLWithPath: value, isDirectory: true, relativeTo: currentDirectory)
                .absoluteURL.standardizedFileURL
        }

        let support = directoryOverride("DESKTOPSHELL_SUPPORT_DIR")
            ?? home.appendingPathComponent("Library/Application Support/DesktopShell", isDirectory: true)
        let web: URL
        if let override = directoryOverride("DESKTOPSHELL_WEB_DIR"), fileExists(override) {
            web = override
        } else if let bundled = bundleResourceURL?.appendingPathComponent("web", isDirectory: true), fileExists(bundled) {
            web = bundled
        } else {
            web = currentDirectory.appendingPathComponent("web", isDirectory: true)
        }

        return AppPaths(
            supportDir: support,
            mediaDir: support.appendingPathComponent("media", isDirectory: true),
            webDir: web
        )
    }

    static var current: AppPaths {
        let fileManager = FileManager.default
        return resolve(
            environment: ProcessInfo.processInfo.environment,
            bundleResourceURL: Bundle.main.resourceURL,
            currentDirectory: URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            home: fileManager.homeDirectoryForCurrentUser,
            fileExists: { fileManager.fileExists(atPath: $0.path) }
        )
    }
}
