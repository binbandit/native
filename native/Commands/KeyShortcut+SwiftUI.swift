import NativeCommands
import SwiftUI

extension KeyShortcut {
    /// For `.keyboardShortcut`, which menus and buttons take.
    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    /// The key a SwiftUI key press reports, with its modifiers; nil for keys a shortcut can't use.
    init?(_ press: KeyPress) {
        let modifiers = Modifiers(press.modifiers)
        if let special = Self.specialEquivalents.first(where: { $0.equivalent == press.key }) {
            self.init(special.key, modifiers: modifiers)
            return
        }
        let character = press.key.character
        guard character.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
            !character.isWhitespace
        else { return nil }
        self.init(.character(character), modifiers: modifiers)
    }

    private var keyEquivalent: KeyEquivalent {
        switch key {
        case .character(let character): KeyEquivalent(character)
        default: Self.specialEquivalents.first { $0.key == key }?.equivalent ?? .escape
        }
    }

    private var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }

    private static let specialEquivalents: [(key: Key, equivalent: KeyEquivalent)] = [
        (.return, .return), (.tab, .tab), (.space, .space), (.delete, .delete), (.forwardDelete, .deleteForward),
        (.escape, .escape), (.upArrow, .upArrow), (.downArrow, .downArrow), (.leftArrow, .leftArrow),
        (.rightArrow, .rightArrow), (.home, .home), (.end, .end), (.pageUp, .pageUp), (.pageDown, .pageDown),
    ]
}

extension KeyShortcut.Modifiers {
    init(_ modifiers: EventModifiers) {
        self = []
        if modifiers.contains(.command) { insert(.command) }
        if modifiers.contains(.shift) { insert(.shift) }
        if modifiers.contains(.option) { insert(.option) }
        if modifiers.contains(.control) { insert(.control) }
    }
}
