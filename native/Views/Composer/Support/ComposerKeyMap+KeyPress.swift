import ACP
import SwiftUI

// Bridges SwiftUI key presses to the composer's pure key maps.

extension ComposerKeyMap.Key {
    init?(_ key: KeyEquivalent) {
        switch key {
        case .upArrow: self = .up
        case .downArrow: self = .down
        case .return: self = .return
        // Shift-Tab arrives as backtab.
        case .tab, KeyEquivalent("\u{19}"): self = .tab
        case .escape: self = .escape
        default: return nil
        }
    }
}

extension DraftAttachmentKeys.Key {
    /// Only bare keys reach the chips: Shift-← extends the text's selection, Option-← moves by words.
    init(_ press: KeyPress) {
        guard press.modifiers.isDisjoint(with: [.shift, .option, .command, .control]) else {
            self = .other
            return
        }
        self =
            switch press.key {
            case .leftArrow: .left
            case .rightArrow: .right
            // Backspace: iPadOS reports SwiftUI's `.delete` (U+0008), but the Mac reports the
            // character its key types (U+007F), which matches neither `.delete` nor `.deleteForward`.
            case .delete, KeyEquivalent("\u{7F}"): .backspace
            case .deleteForward: .forwardDelete
            case .escape: .escape
            default: .other
            }
    }
}

extension ComposerKeyMap.Modifiers {
    init(_ press: KeyPress) {
        var modifiers: Self = []
        if press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}") { modifiers.insert(.shift) }
        if press.modifiers.contains(.option) { modifiers.insert(.option) }
        if press.modifiers.contains(.command) { modifiers.insert(.command) }
        if press.modifiers.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }
}
