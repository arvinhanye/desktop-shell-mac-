import Foundation

enum RangeResult: Equatable {
    case full
    case partial(ClosedRange<Int>)
    case unsatisfiable
}

struct SchemeResolver {
    let webRoot: URL
    let mediaRoot: URL

    /// The caller supplies URL.path, already percent-decoded. Do not decode again.
    func fileURL(forPath path: String) -> URL? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }

        let root: URL
        let relativePath: String
        if path == "/" {
            root = webRoot
            relativePath = "index.html"
        } else if path.hasPrefix("/media/") {
            root = mediaRoot
            relativePath = String(path.dropFirst("/media/".count))
        } else {
            root = webRoot
            relativePath = String(path.dropFirst())
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard root.isFileURL,
              components.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") }) else { return nil }

        // Resolve both sides (including aliases such as /tmp -> /private/tmp).
        // The trailing slash prevents a sibling such as web2 from matching web.
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = resolvedRoot.appendingPathComponent(relativePath)
            .resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = resolvedRoot.path == "/" ? "/" : resolvedRoot.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }

        guard let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else { return nil }
        return candidate
    }

    static func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "mp3": return "audio/mpeg"
        case "mp4": return "video/mp4"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    static func parseRange(_ header: String?, fileSize: Int) -> RangeResult {
        guard fileSize > 0 else { return .unsatisfiable }
        guard let header, !header.isEmpty else { return .full }
        // Multipart ranges deliberately fall back to the whole resource.
        if header.contains(",") { return .full }
        guard header.hasPrefix("bytes=") else { return .unsatisfiable }
        let bounds = header.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2 else { return .unsatisfiable }

        func unsignedInteger(_ text: Substring) -> Int? {
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(text)
        }

        let lastByte = fileSize - 1
        if bounds[0].isEmpty {
            guard let count = unsignedInteger(bounds[1]), count > 0 else { return .unsatisfiable }
            return .partial((fileSize - min(count, fileSize))...lastByte)
        }
        guard let start = unsignedInteger(bounds[0]), start < fileSize else { return .unsatisfiable }
        if bounds[1].isEmpty { return .partial(start...lastByte) }
        guard let end = unsignedInteger(bounds[1]), start <= end else { return .unsatisfiable }
        return .partial(start...min(end, lastByte))
    }
}
