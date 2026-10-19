import Foundation

struct MediaItem: Codable, Equatable {
    let id: String
    let url: String
}

enum MediaLibrary {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]

    static func scan(mediaDir: URL, subdirectory: String, extensions: Set<String> = imageExtensions) -> [MediaItem] {
        guard isValidID(subdirectory) else { return [] }
        let directory = mediaDir.appendingPathComponent(subdirectory, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let info = try? directory.resourceValues(forKeys: keys),
              info.isDirectory == true, info.isSymbolicLink != true else { return [] }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            var seen = Set<String>()
            var items: [MediaItem] = []
            for file in files {
                let name = file.lastPathComponent
                guard !name.hasPrefix("."), extensions.contains(file.pathExtension.lowercased()) else { continue }
                guard let values = try? file.resourceValues(forKeys: keys),
                      values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                let id = file.deletingPathExtension().lastPathComponent
                guard isValidID(id) else {
                    Log.error("DesktopShell media: id rejected: invalid")
                    continue
                }
                guard seen.insert(id).inserted else {
                    Log.notice("DesktopShell media: duplicate id=\(id) skipped")
                    continue
                }
                items.append(MediaItem(id: id, url: "/media/\(subdirectory)/\(name)"))
            }
            return items.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        } catch {
            Log.error("DesktopShell media: scan rejected: failed")
            return []
        }
    }
}
