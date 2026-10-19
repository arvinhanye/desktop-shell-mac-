import AppKit

struct AppIcons {
    var loadIcon: (String) -> NSImage? = { bundleID in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func export(apps: [AppConfig.App], mediaDir: URL) -> Set<String> {
        let directory = mediaDir.appendingPathComponent("app-icons", isDirectory: true)
        let fileManager = FileManager.default
        var exported = Set<String>()
        defer { Log.notice("DesktopShell icons: exported=\(exported.count)/\(apps.count)") }
        do {
            // Inspect the directory itself, including dangling links, before creating it.
            if let info = try? directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
                guard info.isSymbolicLink != true, info.isDirectory == true else {
                    Log.error("DesktopShell icons: invalid-directory")
                    return []
                }
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Log.error("DesktopShell icons: directory-failed")
            return []
        }
        for app in apps {
            guard isValidID(app.id) else {
                Log.error("DesktopShell icons: invalid-id")
                continue
            }
            let succeeded: Bool = autoreleasepool {
                guard let image = loadIcon(app.bundleId) else {
                    Log.notice("DesktopShell icons: app=\(app.id) not-installed")
                    return false
                }
                guard let data = Self.png(image) else {
                    Log.error("DesktopShell icons: app=\(app.id) render-failed")
                    return false
                }
                let temporary = directory.appendingPathComponent(".icon-\(UUID().uuidString).png")
                defer { try? fileManager.removeItem(at: temporary) }
                do {
                    try data.write(to: temporary)
                    let destination = directory.appendingPathComponent("\(app.id).png")
                    // Same-directory rename is atomic and replaces a symlink, not its target.
                    guard rename(temporary.path, destination.path) == 0 else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    return true
                } catch {
                    Log.error("DesktopShell icons: app=\(app.id) write-failed")
                    return false
                }
            }
            if succeeded { exported.insert(app.id) }
            else { exported.remove(app.id) }
        }
        return exported
    }

    private static func png(_ image: NSImage) -> Data? {
        guard image.isValid,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = NSSize(width: 128, height: 128)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: 128, height: 128), from: .zero,
                   operation: .copy, fraction: 1)
        return bitmap.representation(using: .png, properties: [:])
    }
}
