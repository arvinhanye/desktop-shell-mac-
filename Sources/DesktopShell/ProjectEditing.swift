import Foundation

protocol ProjectFileSystem {
    func exists(_ url: URL) -> Bool
    func isDirectory(_ url: URL) -> Bool
    func resolvingSymlinks(_ url: URL) -> URL
}

struct LocalProjectFileSystem: ProjectFileSystem {
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    func resolvingSymlinks(_ url: URL) -> URL { url.resolvingSymlinksInPath() }
}

enum ProjectEditing {
    enum AddError: Error, Equatable { case notFound, notDirectory, outsideHome, duplicate }

    static func resolve(_ input: String, home: URL, existing: [String],
                        fileSystem: ProjectFileSystem) -> Result<URL, AddError> {
        func canonical(_ path: String) -> URL? {
            // A NUL must not be truncated by filesystem APIs into a different path.
            guard !path.contains("\0"), let url = ProjectPath.resolve(path, home: home) else { return nil }
            return fileSystem.resolvingSymlinks(url).standardizedFileURL
        }
        guard let folder = canonical(input), fileSystem.exists(folder) else { return .failure(.notFound) }
        guard fileSystem.isDirectory(folder) else { return .failure(.notDirectory) }
        let realHome = fileSystem.resolvingSymlinks(home.standardizedFileURL).standardizedFileURL
        guard isInside(folder, home: realHome) else { return .failure(.outsideHome) }
        guard !existing.contains(where: { canonical($0)?.pathComponents == folder.pathComponents }) else {
            return .failure(.duplicate)
        }
        return .success(folder)
    }

    static func storedPath(_ url: URL, home: URL) -> String {
        guard isInside(url, home: home) else { return url.path }
        return "~/" + url.pathComponents.dropFirst(home.pathComponents.count).joined(separator: "/")
    }

    static func makeID(name: String, existing: Set<String>) -> String {
        let separated = name.unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 65...90: return String(scalar).lowercased()
            case 97...122, 48...57: return String(scalar)
            default: return "-"
            }
        }.joined().split(separator: "-").joined(separator: "-")
        let base = separated.isEmpty ? "project" : separated
        var candidate = base
        var suffix = 2
        while existing.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    static func newProject(folder: URL, home: URL, config: AppConfig) -> AppConfig.Project {
        AppConfig.Project(id: makeID(name: folder.lastPathComponent, existing: Set(config.projects.map(\.id))),
                          name: folder.lastPathComponent, path: storedPath(folder, home: home), tags: [],
                          apps: config.apps.contains(where: { $0.id == "cursor" }) ? ["cursor"] : [])
    }

    private static func isInside(_ url: URL, home: URL) -> Bool {
        let path = url.pathComponents
        let root = home.pathComponents
        return path.count > root.count && path.starts(with: root)
    }
}
