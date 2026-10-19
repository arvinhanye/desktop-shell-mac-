import AppKit
import CoreFoundation
import QuartzCore

struct GlassRegion: Equatable {
    let rect: CGRect
    let radius: CGFloat
}

enum GlassRegions {
    static func parse(_ value: Any?) -> [GlassRegion]? {
        guard let entries = value as? [[Any]], entries.count <= 64 else { return nil }
        var regions: [GlassRegion] = []
        for entry in entries {
            guard entry.count == 5 else { return nil }
            var values: [CGFloat] = []
            for value in entry {
                guard let number = value as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite else { return nil }
                values.append(CGFloat(number.doubleValue))
            }
            let width = values[2], height = values[3], radius = values[4]
            guard width > 0, height > 0, radius >= 0, radius <= min(width, height) / 2 else { return nil }
            regions.append(GlassRegion(
                rect: CGRect(x: values[0], y: values[1], width: width, height: height), radius: radius
            ))
        }
        return regions
    }

    static func clip(_ regions: [GlassRegion], viewport: CGSize) -> [GlassRegion] {
        guard viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0 else { return [] }
        let bounds = CGRect(origin: .zero, size: viewport)
        return regions.compactMap { region in
            let rect = region.rect.intersection(bounds)
            guard !rect.isEmpty else { return nil }
            return GlassRegion(rect: rect, radius: min(region.radius, min(rect.width, rect.height) / 2))
        }
    }
}

@MainActor
final class GlassLayer: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    private var effects: [NSVisualEffectView] = []
    private var masks: [CGFloat: NSImage] = [:]

    func update(_ regions: [GlassRegion]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        while effects.count < regions.count {
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.appearance = NSAppearance(named: .darkAqua)
            addSubview(effect)
            effects.append(effect)
        }
        for (index, effect) in effects.enumerated() {
            guard index < regions.count else { effect.isHidden = true; continue }
            let region = regions[index]
            effect.frame = region.rect
            effect.maskImage = mask(radius: region.radius)
            effect.isHidden = false
        }
    }

    private func mask(radius: CGFloat) -> NSImage {
        if let cached = masks[radius] { return cached }
        let size = NSSize(width: 2 * radius + 1, height: 2 * radius + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        masks[radius] = image
        return image
    }
}
