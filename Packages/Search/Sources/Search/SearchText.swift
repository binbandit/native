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
    static func codeParts(of text: String, limit: Int = 4_096) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        var length = 0
        for word in text.split(whereSeparator: { !isWordCharacter($0) }) {
            let humps = humps(of: word)
            guard humps.count > 1 else { continue }
            for hump in humps where hump.count > 1 {
                let lowered = hump.lowercased()
                guard seen.insert(lowered).inserted else { continue }
                length += lowered.count + 1
                guard length <= limit else { return parts.joined(separator: " ") }
                parts.append(lowered)
            }
        }
        return parts.joined(separator: " ")
    }

    /// `parseHTTPHeader2` → `parse`, `HTTP`, `Header`, `2`.
    static func humps(of word: Substring) -> [Substring] {
        var humps: [Substring] = []
        var start = word.startIndex
        var index = word.startIndex
        while index < word.endIndex {
            let next = word.index(after: index)
            if next < word.endIndex, isBoundary(word[index], word[next], after: word[next...].dropFirst().first) {
                humps.append(word[start..<next])
                start = next
            }
            index = next
        }
        if start < word.endIndex {
            humps.append(word[start...])
        }
        return humps
    }

    private static func isBoundary(_ current: Character, _ next: Character, after: Character?) -> Bool {
        if current.isLowercase && next.isUppercase { return true }
        if current.isLetter != next.isLetter { return current.isLetter || current.isNumber }
        // The end of an acronym: the last capital starts the next word (`HTTPHeader`).
        if current.isUppercase && next.isUppercase, let after, after.isLowercase { return true }
        return false
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
