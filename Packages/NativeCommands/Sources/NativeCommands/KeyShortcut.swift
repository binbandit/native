import Foundation

/// A key and its modifiers: what a command is bound to. Menus print it as glyphs ("⇧⌘A"), and
/// preferences, exports and configuration profiles spell it in words ("shift+cmd+a"). Both parse,
/// with the modifiers in any order.
public struct KeyShortcut: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public enum Key: Hashable, Sendable {
        /// A key that types a character, lowercased: "a", "1", "[", "`".
        case character(Character)
        case `return`, tab, space, delete, forwardDelete, escape
        case upArrow, downArrow, leftArrow, rightArrow
        case home, end, pageUp, pageDown
    }

    public let key: Key
    public let modifiers: Modifiers

    public init(_ key: Key, modifiers: Modifiers = []) {
        if case .character(let character) = key {
            self.key = .character(character.lowercased().first ?? character)
        } else {
            self.key = key
        }
        self.modifiers = modifiers
    }

    /// Parses "⇧⌘A", "⌘⇧⌫", "⌃Tab", "shift+cmd+a" or "ctrl+`"; nil for anything else.
    public init?(_ text: String) {
        var rest = Substring(text.filter { !$0.isWhitespace })
        var modifiers: Modifiers = []
        while !rest.isEmpty {
            if let first = rest.first, let modifier = Self.modifierNames.first(where: { $0.glyph == first }) {
                modifiers.insert(modifier.modifier)
                rest = rest.dropFirst()
            } else if let plus = rest.firstIndex(of: "+"), plus != rest.startIndex,
                let modifier = Self.modifierNames.first(where: { $0.words.contains(rest[..<plus].lowercased()) })
            {
                modifiers.insert(modifier.modifier)
                rest = rest[rest.index(after: plus)...]
            } else {
                break
            }
        }
        guard let key = Self.key(named: String(rest)) else { return nil }
        self.init(key, modifiers: modifiers)
    }

    /// As menus print it, modifiers in the menu bar's order: "⌃⌥⇧⌘K".
    public var displayString: String {
        Self.modifierNames.filter { modifiers.contains($0.modifier) }.map { String($0.glyph) }.joined() + keyGlyph
    }

    /// As preferences and exported files spell it: "shift+cmd+k".
    public var serialized: String {
        (Self.modifierNames.filter { modifiers.contains($0.modifier) }.compactMap(\.words.first) + [keyWord])
            .joined(separator: "+")
    }

    /// Words that find this shortcut in a search: its glyphs, its spelling, and the keys' names.
    public var searchTerms: [String] {
        let modifierWords = Self.modifierNames.filter { modifiers.contains($0.modifier) }.flatMap(\.spoken)
        let keyWords = Self.specialKeys.first { $0.key == key }.map { [$0.word] + $0.aliases } ?? []
        return [displayString, serialized] + modifierWords + keyWords
    }

    private var keyGlyph: String {
        switch key {
        case .character(let character): character.uppercased()
        default: Self.specialKeys.first { $0.key == key }?.glyph ?? ""
        }
    }

    private var keyWord: String {
        switch key {
        case .character(let character): String(character)
        default: Self.specialKeys.first { $0.key == key }?.word ?? ""
        }
    }

    private static func key(named name: String) -> Key? {
        let lowered = name.lowercased()
        if let special = specialKeys.first(where: {
            $0.glyph.lowercased() == lowered || $0.word == lowered || $0.aliases.contains(lowered)
        }) {
            return special.key
        }
        guard name.count == 1, let character = name.first,
            !character.isWhitespace, character.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return .character(character)
    }

    private static let modifierNames:
        [(modifier: Modifiers, glyph: Character, words: [String], spoken: [String])] = [
            (.control, "⌃", ["ctrl", "control"], ["control", "ctrl"]),
            (.option, "⌥", ["opt", "option", "alt"], ["option", "opt", "alt"]),
            (.shift, "⇧", ["shift"], ["shift"]),
            (.command, "⌘", ["cmd", "command"], ["command", "cmd"]),
        ]

    /// Keys that don't type a character: the menu's glyph, the word files use, and other names
    /// people write (`docs/keyboard.md` says "Esc" and "↵").
    private static let specialKeys: [(key: Key, glyph: String, word: String, aliases: [String])] = [
        (.return, "↩", "return", ["↵", "⏎", "enter"]),
        (.tab, "⇥", "tab", []),
        (.space, "Space", "space", ["␣"]),
        (.delete, "⌫", "delete", ["backspace"]),
        (.forwardDelete, "⌦", "forwarddelete", []),
        (.escape, "⎋", "escape", ["esc"]),
        (.upArrow, "↑", "up", ["uparrow"]),
        (.downArrow, "↓", "down", ["downarrow"]),
        (.leftArrow, "←", "left", ["leftarrow"]),
        (.rightArrow, "→", "right", ["rightarrow"]),
        (.home, "↖", "home", []),
        (.end, "↘", "end", []),
        (.pageUp, "⇞", "pageup", []),
        (.pageDown, "⇟", "pagedown", []),
    ]
}

extension KeyShortcut: CustomStringConvertible {
    public var description: String { displayString }
}

extension KeyShortcut: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let shortcut = KeyShortcut(text) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "\(text) isn't a shortcut"))
        }
        self = shortcut
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(serialized)
    }
}
