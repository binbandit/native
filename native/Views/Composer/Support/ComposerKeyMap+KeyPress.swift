import SwiftUI

// Bridges SwiftUI key presses to the composer's pure key map.

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
