import Foundation

enum HitTesting {
    static func parseRegions(_ value: Any?, viewport: CGSize) -> [CGRect]? {
        guard let entries = value as? [[Any]], entries.count <= 64,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width >= 0, viewport.height >= 0 else { return nil }
        let bounds = CGRect(origin: .zero, size: viewport)
        var regions: [CGRect] = []
        for entry in entries {
            guard entry.count == 4 else { return nil }
            var numbers: [CGFloat] = []
            for value in entry {
                // JavaScript booleans bridge to NSNumber too; they are not coordinates.
                guard let number = value as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite else { return nil }
                numbers.append(CGFloat(number.doubleValue))
            }
            guard numbers[2] > 0, numbers[3] > 0 else { return nil }
            let clipped = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                .intersection(bounds)
            if !clipped.isEmpty { regions.append(clipped) }
        }
        return regions
    }

    static func isInteractive(mouse: CGPoint, windowFrame: CGRect, regions: [CGRect]) -> Bool {
        let point = CGPoint(x: mouse.x - windowFrame.minX, y: windowFrame.maxY - mouse.y)
        // Check the viewport in web coordinates too, preserving its inclusive top/left edges.
        guard CGRect(origin: .zero, size: windowFrame.size).contains(point) else { return false }
        return regions.contains { $0.contains(point) }
    }
}
