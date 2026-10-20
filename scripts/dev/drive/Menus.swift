import ApplicationServices
import Foundation

/// The instance's menu bar, read and pressed through Accessibility. Menus never open on screen.
struct Menus {
    let app: AXUIElement

    /// The item at `path` (`["File", "New Session"]`, or deeper for submenus), matched ignoring case
    /// and a trailing ellipsis.
    func item(_ path: [String]) throws(DriveError) -> AXUIElement {
        var menu = try bar()
        var element: AXUIElement?
        for (depth, title) in path.enumerated() {
            let items = depth == 0 ? Accessibility.children(menu) : entries(menu)
            guard let found = Self.match(title, in: items) else {
                let known = items.compactMap { Self.title($0) }.filter { !$0.isEmpty }
                throw DriveError(
                    "no \(Self.quotedPath(Array(path.prefix(depth + 1)))); there is: "
                        + known.map { Node.quoted($0) }.joined(separator: ", "))
            }
            element = found
            guard depth < path.count - 1 else { break }
            guard let submenu = Accessibility.children(found).first else {
                throw DriveError("\(Self.quotedPath(Array(path.prefix(depth + 1)))) has no submenu")
            }
            menu = submenu
        }
        guard let element else { throw DriveError("menu: give a menu and an item", code: 2) }
        return element
    }

    /// The items of the menu at `path`, one line each: title, shortcut, and whether it's enabled or
    /// opens a submenu.
    func list(_ path: [String]) throws(DriveError) -> [String] {
        let element = try item(path)
        guard let menu = Accessibility.children(element).first else { return [] }
        return entries(menu).map { item in
            let title = Self.title(item) ?? ""
            guard !title.isEmpty else { return "  ----" }
            var line = "  " + title
            if let shortcut = Self.shortcut(item) { line += "  " + shortcut }
            if Accessibility.children(item).first != nil { line += "  ▸" }
            if (Accessibility.attribute(item, kAXEnabledAttribute) as? NSNumber)?.boolValue == false {
                line += "  [disabled]"
            }
            return line
        }
    }

    private func bar() throws(DriveError) -> AXUIElement {
        guard let bar = Accessibility.element(Accessibility.attribute(app, kAXMenuBarAttribute)) else {
            throw DriveError("no menu bar")
        }
        return bar
    }

    /// A menu's items, separators included.
    private func entries(_ menu: AXUIElement) -> [AXUIElement] {
        Accessibility.children(menu).filter {
            Accessibility.attribute($0, kAXRoleAttribute) as? String == kAXMenuItemRole
        }
    }

    private static func title(_ item: AXUIElement) -> String? {
        Accessibility.attribute(item, kAXTitleAttribute) as? String
    }

    private static func match(_ wanted: String, in items: [AXUIElement]) -> AXUIElement? {
        let bare = { (text: String) in
            text.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
                .trimmingCharacters(in: .whitespaces).lowercased()
        }
        return items.first { title($0) == wanted } ?? items.first { title($0).map(bare) == bare(wanted) }
    }

    private static func quotedPath(_ path: [String]) -> String {
        path.joined(separator: " ▸ ")
    }

    /// The item's key equivalent as the menu shows it, like ⌥⌘N.
    private static func shortcut(_ item: AXUIElement) -> String? {
        let character = Accessibility.attribute(item, kAXMenuItemCmdCharAttribute) as? String ?? ""
        let glyph = (Accessibility.attribute(item, kAXMenuItemCmdGlyphAttribute) as? NSNumber)?.intValue ?? 0
        guard let key = keyName(character) ?? glyphs[glyph] else { return nil }
        let modifiers = (Accessibility.attribute(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
        // Bits: 1 Shift, 2 Option, 4 Control, 8 no Command.
        var text = ""
        if modifiers & 4 != 0 { text += "⌃" }
        if modifiers & 2 != 0 { text += "⌥" }
        if modifiers & 1 != 0 { text += "⇧" }
        if modifiers & 8 == 0 { text += "⌘" }
        return text + key
    }

    private static func keyName(_ character: String) -> String? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x0D, 0x03: return "↩"
        case 0x1B: return "⎋"
        case 0x09: return "⇥"
        case 0x08, 0x7F: return "⌫"
        case 0x20: return "Space"
        case 0xF700: return "↑"
        case 0xF701: return "↓"
        case 0xF702: return "←"
        case 0xF703: return "→"
        case 0xF728: return "⌦"
        default: return character.uppercased()
        }
    }

    private static let glyphs: [Int: String] = [
        2: "⇥", 9: "Space", 10: "⌦", 11: "↩", 23: "⌫", 27: "⎋", 100: "←", 101: "→", 104: "↑", 106: "↓",
    ]
}
