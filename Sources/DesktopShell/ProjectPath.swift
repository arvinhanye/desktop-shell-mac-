import Foundation

enum ProjectPath {
    static func resolve(_ path: String, home: URL) -> URL? {
        let url: URL
        if path == "~" {
            url = home
        } else if path.hasPrefix("~/") {
            url = home.appendingPathComponent(String(path.dropFirst(2)))
        } else if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            return nil
        }
        return url.standardizedFileURL
    }
}
