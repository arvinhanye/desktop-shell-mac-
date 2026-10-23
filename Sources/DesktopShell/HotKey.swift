import Carbon
import Foundation

/// Pure US physical-key mapping. Registration belongs to the terminal panel.
struct HotKey: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let display: String
    let usedDefaultBecauseInvalid: Bool

    static func resolve(_ shortcut: AppConfig.Terminal.Shortcut?) -> HotKey {
        func fallback(invalid: Bool) -> HotKey {
            HotKey(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(optionKey),
                   display: "⌥`", usedDefaultBecauseInvalid: invalid)
        }
        guard let shortcut else { return fallback(invalid: false) }
        let key = shortcut.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let requested = Set(shortcut.modifiers)
        let ordered: [(String, Int, String)] = [
            ("control", controlKey, "⌃"), ("option", optionKey, "⌥"),
            ("shift", shiftKey, "⇧"), ("command", cmdKey, "⌘")
        ]
        guard let code = keyCodes[key], !requested.isEmpty, requested != ["shift"],
              requested.count == shortcut.modifiers.count,
              requested.isSubset(of: Set(ordered.map { $0.0 })) else { return fallback(invalid: true) }
        let selected = ordered.filter { requested.contains($0.0) }
        let label = ["space": "Space", "tab": "Tab", "return": "↩", "escape": "⎋"][key] ?? key.uppercased()
        return HotKey(keyCode: UInt32(code), modifiers: selected.reduce(0) { $0 | UInt32($1.1) },
                      display: selected.map { $0.2 }.joined() + label, usedDefaultBecauseInvalid: false)
    }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1,
        "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
        "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "`": kVK_ANSI_Grave, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket,
        "]": kVK_ANSI_RightBracket, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma,
        ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash, "space": kVK_Space,
        "tab": kVK_Tab, "return": kVK_Return, "escape": kVK_Escape, "f1": kVK_F1,
        "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
        "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9,
        "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]
}
