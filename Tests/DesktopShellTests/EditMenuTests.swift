import AppKit
import Testing
@testable import DesktopShell

@MainActor
struct EditMenuTests {
    @Test("主菜单只有编辑子菜单，快捷键沿响应链分派且顺序完整")
    func menuStructure() throws {
        _ = NSApplication.shared
        let main = EditMenu.makeMainMenu()
        #expect(main.items.count == 1)
        let parent = try #require(main.items.first)
        #expect(parent.title == "编辑")
        // AppKit assigns submenuAction: and a menu target to the parent on attachment.
        // The editable commands below, not the submenu container, use nil targets.
        #expect(parent.keyEquivalent.isEmpty)
        let edit = try #require(parent.submenu)
        #expect(edit.title == "编辑")
        #expect(edit.autoenablesItems)
        #expect(edit.items.count == 7)
        #expect(edit.items.map(\.title) == ["撤销", "重做", "", "剪切", "拷贝", "粘贴", "全选"])
        #expect(edit.items.enumerated().filter { $0.element.isSeparatorItem }.map(\.offset) == [2])
        let commands = edit.items.filter { !$0.isSeparatorItem }
        #expect(commands.map { $0.action.map(NSStringFromSelector) } == ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:"])
        #expect(commands.map(\.keyEquivalent) == ["z", "z", "x", "c", "v", "a"])
        #expect(commands.map(\.keyEquivalentModifierMask) == [.command, [.shift, .command], .command, .command, .command, .command])
        #expect(edit.items.allSatisfy { $0.target == nil && $0.submenu == nil })
        let separator = edit.items[2]
        #expect(separator.action == nil && separator.keyEquivalent.isEmpty)
    }

    @Test("菜单工厂每次创建独立菜单，不替换应用当前主菜单")
    func independentMenus() throws {
        let app = NSApplication.shared
        let previous = app.mainMenu
        let first = EditMenu.makeMainMenu()
        let second = EditMenu.makeMainMenu()
        #expect(first !== second)
        let firstEdit = try #require(first.items.first?.submenu)
        let secondEdit = try #require(second.items.first?.submenu)
        #expect(firstEdit !== secondEdit)
        firstEdit.removeAllItems()
        #expect(secondEdit.items.count == 7)
        #expect(app.mainMenu === previous)
    }
}
