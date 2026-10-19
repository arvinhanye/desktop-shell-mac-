// Run with: swift scripts/window-levels.swift
// Read-only: window bounds, owner, ID and layer only; never reads window titles.
import Foundation
import CoreGraphics

// Match WindowLevels.describe without importing the app into this standalone script.
func describeLevel(_ level: Int, iconLevel: Int) -> String {
    let (offset, overflow) = level.subtractingReportingOverflow(iconLevel)
    guard !overflow, (-16...16).contains(offset) else { return String(level) }
    return "icon\(offset >= 0 ? "+" : "")\(offset)"
}

guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
    as? [[String: Any]] else {
    fputs("Window list unavailable; run in a logged-in graphical session.\n", stderr)
    exit(1)
}

let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
let firstAppIndex = windows.firstIndex { window in
    guard let owner = window[kCGWindowOwnerName as String] as? String else { return false }
    return owner != "DesktopShell" && (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
}

var found = false
for (index, window) in windows.enumerated() {
    guard window[kCGWindowOwnerName as String] as? String == "DesktopShell" else { continue }
    found = true
    guard let number = window[kCGWindowNumber as String] as? NSNumber,
          let layer = window[kCGWindowLayer as String] as? NSNumber,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? NSNumber,
          let height = bounds["Height"] as? NSNumber else {
        fputs("DesktopShell window metadata incomplete.\n", stderr)
        exit(1)
    }

    let order: String
    if let firstAppIndex {
        order = index > firstAppIndex ? "behind app windows" : "in front of app windows"
    } else {
        order = "no app windows to compare"
    }
    let level = describeLevel(layer.intValue, iconLevel: iconLevel)
    print("DesktopShell #\(number.uint32Value) \(width.intValue)x\(height.intValue) level=\(level) \(order)")
}

if !found {
    fputs("No on-screen DesktopShell windows; launch the packaged app first.\n", stderr)
    exit(1)
}
