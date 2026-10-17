import WebKit

@MainActor
final class ShellSchemeHandler: NSObject, WKURLSchemeHandler {
    private let resolver: SchemeResolver
    private let readQueue = DispatchQueue(label: "DesktopShell.resources", qos: .userInitiated)
    private struct ActiveTask {
        let generation: UUID
        let task: WKURLSchemeTask
    }
    private var activeTasks: [ObjectIdentifier: ActiveTask] = [:]

    init(resolver: SchemeResolver) {
        self.resolver = resolver
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        let generation = UUID()
        activeTasks[id] = ActiveTask(generation: generation, task: urlSchemeTask)
        let request = urlSchemeTask.request
        let resolver = resolver

        // File I/O stays off the UI thread. Task state and every WebKit callback
        // stay on the main queue, serialized with stop (including reentrant stops).
        readQueue.async { [weak self] in
            let result = Self.response(for: request, resolver: resolver)
            DispatchQueue.main.async { [weak self] in
                guard let self, let active = self.activeTasks[id], active.generation == generation else { return }
                let task = active.task
                switch result {
                case .success(let (response, data)):
                    task.didReceive(response)
                    guard self.activeTasks[id]?.generation == generation else { return }
                    if !data.isEmpty {
                        task.didReceive(data)
                        guard self.activeTasks[id]?.generation == generation else { return }
                    }
                    self.activeTasks.removeValue(forKey: id)
                    task.didFinish()
                case .failure(let error):
                    self.activeTasks.removeValue(forKey: id)
                    task.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Absence marks a stopped task; no permanent set of cancelled tasks grows.
        activeTasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))
    }

    nonisolated private static func response(
        for request: URLRequest, resolver: SchemeResolver
    ) -> Result<(HTTPURLResponse, Data), Error> {
        guard let url = request.url else { return .failure(URLError(.badURL)) }
        var status = 404
        var body = Data()
        var headers = [
            "Content-Type": "text/plain; charset=utf-8",
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache"
        ]

        if url.scheme == "shell", url.host == "app",
           let fileURL = resolver.fileURL(forPath: url.path) {
            do {
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                let mime = SchemeResolver.mimeType(forPathExtension: fileURL.pathExtension)
                let isText = mime.hasPrefix("text/") || mime == "application/json" || mime == "image/svg+xml"
                headers["Content-Type"] = mime + (isText ? "; charset=utf-8" : "")
                switch SchemeResolver.parseRange(request.value(forHTTPHeaderField: "Range"), fileSize: data.count) {
                case .full:
                    status = 200
                    body = data
                case .partial(let range):
                    status = 206
                    body = data.subdata(in: range.lowerBound..<(range.upperBound + 1))
                    headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound)/\(data.count)"
                case .unsatisfiable:
                    status = 416
                    headers["Content-Range"] = "bytes */\(data.count)"
                }
            } catch {
                NSLog("DesktopShell: resource read failed for %@: %@", fileURL.path, String(describing: error))
            }
        }

        headers["Content-Length"] = String(body.count)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            return .failure(URLError(.badServerResponse))
        }
        return .success((response, body))
    }
}
