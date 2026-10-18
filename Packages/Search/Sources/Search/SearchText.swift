import Foundation

/// Text handling shared by indexing and querying, so both see words the same way.
///
/// SQLite's `unicode61` tokenizer already splits on everything that isn't a letter or a digit, so
/// `snake_case`, `kebab-case` and `native/Models/AppModel.swift` come apart into words on their
/// own. What it can't do is split `AppModel` into `app` and `model`, so the index keeps those
/// pieces in a second column (`parts`) that queries match too, while the original text stays intact
/// for phrases and snippets.
public enum SearchText {
    /// The words of `text` as the tokenizer sees them, lowercased.
    public static func words(in text: some StringProtocol) -> [String] {
        text.split { !isWordCharacter($0) }.map { $0.lowercased() }
    }

    /// The camelCase pieces of the identifiers in `text`, each once, lowercased and space-separated:
    /// `SessionStore.swift parseHTTPHeader` gives `session store parse http header`.
    ///
    /// Runs over every indexed character, so it works on Unicode scalars with an ASCII fast path
    /// rather than on `Character`s.
    static func codeParts(of text: String, limit: Int = 4_096) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        var length = 0
        var word: [Unicode.Scalar] = []
        var classes: [ScalarClass] = []

        func finishWord() {
            defer {
                word.removeAll(keepingCapacity: true)
                classes.removeAll(keepingCapacity: true)
            }
            var start = 0
            var humps: [Range<Int>] = []
            for index in classes.indices.dropLast() where isBoundary(at: index, in: classes) {
                humps.append(start..<index + 1)
                start = index + 1
            }
            guard !humps.isEmpty, length <= limit else { return }
            humps.append(start..<classes.count)
            for hump in humps where hump.count > 1 {
                var scalars = String.UnicodeScalarView()
                scalars.append(contentsOf: word[hump])
                let part = String(scalars).lowercased()
                guard seen.insert(part).inserted else { continue }
                length += part.utf8.count + 1
                parts.append(part)
            }
        }

        for scalar in text.unicodeScalars {
            let scalarClass = ScalarClass(scalar)
            if scalarClass == .separator {
                if !word.isEmpty { finishWord() }
            } else {
                word.append(scalar)
                classes.append(scalarClass)
            }
        }
        if !word.isEmpty { finishWord() }
        return parts.joined(separator: " ")
    }

    private enum ScalarClass {
        case lower, upper, digit, uncased, separator

        init(_ scalar: Unicode.Scalar) {
            switch scalar.value {
            case 0x61...0x7A: self = .lower
            case 0x41...0x5A: self = .upper
            case 0x30...0x39: self = .digit
            case 0..<0x80: self = .separator
            default:
                let properties = scalar.properties
                if properties.isLowercase {
                    self = .lower
                } else if properties.isUppercase {
                    self = .upper
                } else if properties.numericType != nil {
                    self = .digit
                } else if properties.isAlphabetic {
                    self = .uncased
                } else {
                    self = .separator
                }
            }
        }

        var isLetter: Bool { self != .digit }
    }

    /// Whether a word splits after `index`: `parse|HTTP|Header|2`.
    private static func isBoundary(at index: Int, in classes: [ScalarClass]) -> Bool {
        let current = classes[index], next = classes[index + 1]
        if current == .lower && next == .upper { return true }
        if current.isLetter != next.isLetter { return true }
        // The end of an acronym: its last capital starts the next word (`HTTPHeader`).
        return current == .upper && next == .upper && index + 2 < classes.count && classes[index + 2] == .lower
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// `text` with every run of whitespace (newlines included) turned into one space.
    public static func collapsingWhitespace(_ text: some StringProtocol) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// At most `limit` characters of `text`: its start and, when there's room, its end, which is
    /// where a command's output says how it went.
    static func capped(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let tail = limit / 4
        return text.prefix(limit - tail) + "\n…\n" + text.suffix(tail)
    }
}
