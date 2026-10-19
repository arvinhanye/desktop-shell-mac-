enum WindowLevels {
    static func widget(iconLevel: Int) -> Int {
        iconLevel + 3
    }

    static func video(iconLevel: Int, iconsHidden: Bool) -> Int {
        iconsHidden ? widget(iconLevel: iconLevel) : iconLevel - 1
    }

    static func describe(_ level: Int, iconLevel: Int) -> String {
        let (offset, overflow) = level.subtractingReportingOverflow(iconLevel)
        // Keep nearby desktop layers readable without disguising a normal/floating window.
        guard !overflow, (-16...16).contains(offset) else { return String(level) }
        return "icon\(offset >= 0 ? "+" : "")\(offset)"
    }
}
