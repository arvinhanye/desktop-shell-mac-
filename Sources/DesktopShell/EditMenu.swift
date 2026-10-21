import AppKit

@MainActor
enum EditMenu {
    /// Supplies standard editing shortcuts even though LSUIElement has no visible menu bar.
    static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let parent = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        func add(_ title: String, action: String, key: String, modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key)
            // Let the current first responder (WebKit's editor) validate and handle it.
            item.target = nil
            item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)
        }
        add("撤销", action: "undo:", key: "z")
        add("重做", action: "redo:", key: "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        add("剪切", action: "cut:", key: "x")
        add("拷贝", action: "copy:", key: "c")
        add("粘贴", action: "paste:", key: "v")
        add("全选", action: "selectAll:", key: "a")
        parent.submenu = edit
        main.addItem(parent)
        return main
    }
}
