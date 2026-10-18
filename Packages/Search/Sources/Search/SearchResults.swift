import Foundation

/// A search's answer: tasks in order of their best hit, each with its best hits.
public struct SearchResults: Hashable, Sendable, Codable {
    public var groups: [SearchGroup]
    /// Whether more hits matched than were ranked, so the counts are lower bounds.
    public var isTruncated: Bool
    /// How long the query took inside the index.
    public var duration: TimeInterval

    public init(groups: [SearchGroup] = [], isTruncated: Bool = false, duration: TimeInterval = 0) {
        self.groups = groups
        self.isTruncated = isTruncated
        self.duration = duration
    }

    public static let empty = SearchResults()
}

/// One task and its hits.
public struct SearchGroup: Hashable, Sendable, Codable, Identifiable {
    public var session: SearchSessionRecord
    public var hits: [SearchHit]
    /// Every ranked hit in the task, of which `hits` are the best.
    public var hitCount: Int

    public var id: SearchSessionKey { session.key }
}

/// One matching piece of a transcript.
public struct SearchHit: Hashable, Sendable, Codable, Identifiable {
    public var id: Int64
    public var role: SearchRole
    public var anchor: SearchAnchor
    public var date: Date?
    public var hasDiff: Bool
    public var snippet: SearchSnippet
}

/// A short excerpt around a match, split into runs so a client highlights the matched words.
public struct SearchSnippet: Hashable, Sendable, Codable {
    public struct Run: Hashable, Sendable, Codable {
        public var text: String
        public var isMatch: Bool
    }

    public var runs: [Run]

    public var text: String {
        runs.map(\.text).joined()
    }

    /// About `width` characters of `text` around the first match of `words`, with every match
    /// marked. A match starts a word or an identifier's part (`model` in `AppModel`), case- and
    /// diacritic-insensitively; words of three letters or fewer must be whole words, unless
    /// they're in `prefixes` (still being typed), so "the" doesn't light up inside "they".
    /// Matches separated only by spaces or punctuation are marked as one, so a phrase reads as one.
    public init(text: String, words: [String], prefixes: Set<String> = [], width: Int = 180) {
        let words = words.filter { $0.count > 1 || words.count == 1 }
        // The window centers on the most telling word: the longest one that matches.
        let anchor = words.sorted { $0.count > $1.count }.lazy
            .compactMap { Self.matches(of: $0, in: text, prefixes: prefixes, limit: 1).first?.lowerBound }.first
        var window = Substring(text)
        var leading = "", trailing = ""
        // UTF-8 length is free and never less than the character count.
        if text.utf8.count > width, text.count > width {
            let lead = width / 3
            let start =
                anchor.map { text.index($0, offsetBy: -lead, limitedBy: text.startIndex) ?? text.startIndex }
                ?? text.startIndex
            let end = text.index(start, offsetBy: width, limitedBy: text.endIndex) ?? text.endIndex
            window = Self.trimmedToWords(
                text[start..<end], atStart: start != text.startIndex, atEnd: end != text.endIndex)
            leading = start == text.startIndex ? "" : "…"
            trailing = end == text.endIndex ? "" : "…"
        }
        // Tool output that was itself JSON keeps its escapes; they read as line breaks.
        let unescaped = window.replacingOccurrences(of: "\\n", with: " ")
        let excerpt = leading + SearchText.collapsingWhitespace(unescaped) + trailing
        runs = Self.runs(of: excerpt, marking: words, prefixes: prefixes)
    }

    private static func matches(
        of word: String, in text: String, prefixes: Set<String>, limit: Int = .max
    ) -> [Range<String.Index>] {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let isWhole = word.count <= 3 && !prefixes.contains(word)
        var matches: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let range = text.range(of: word, options: options, range: searchStart..<text.endIndex) {
            searchStart = range.upperBound
            guard startsWord(range.lowerBound, in: text), !isWhole || endsWord(range.upperBound, in: text) else {
                continue
            }
            matches.append(range)
            if matches.count == limit { break }
        }
        return matches
    }

    /// Whether a word or an identifier's part begins at `index`.
    private static func startsWord(_ index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)], current = text[index]
        return !SearchText.isWordCharacter(previous) || (previous.isLowercase && current.isUppercase)
            || previous.isLetter != current.isLetter
    }

    private static func endsWord(_ index: String.Index, in text: String) -> Bool {
        index == text.endIndex || !SearchText.isWordCharacter(text[index])
    }

    private static func trimmedToWords(_ window: Substring, atStart: Bool, atEnd: Bool) -> Substring {
        var window = window
        // Don't start or end in the middle of a word, when there's a word boundary close by.
        if atStart, let space = window.prefix(24).firstIndex(where: \.isWhitespace) {
            window = window[window.index(after: space)...]
        }
        if atEnd, let space = window.suffix(24).lastIndex(where: \.isWhitespace) {
            window = window[..<space]
        }
        return window
    }

    private static func runs(of text: String, marking words: [String], prefixes: Set<String>) -> [Run] {
        var marks = words.flatMap { matches(of: $0, in: text, prefixes: prefixes) }
            .sorted { $0.lowerBound < $1.lowerBound }
        // Join marks with only spaces or punctuation between them: `kumquat-lighthouse`.
        var joined: [Range<String.Index>] = []
        for mark in marks {
            if let last = joined.last, mark.lowerBound >= last.upperBound,
                text[last.upperBound..<mark.lowerBound].count <= 2,
                text[last.upperBound..<mark.lowerBound].allSatisfy({ !SearchText.isWordCharacter($0) })
            {
                joined[joined.count - 1] = last.lowerBound..<mark.upperBound
            } else if joined.last.map({ mark.lowerBound >= $0.upperBound }) ?? true {
                joined.append(mark)
            }
        }
        marks = joined
        var runs: [Run] = []
        var cursor = text.startIndex
        for mark in marks {
            if cursor < mark.lowerBound {
                runs.append(Run(text: String(text[cursor..<mark.lowerBound]), isMatch: false))
            }
            runs.append(Run(text: String(text[mark]), isMatch: true))
            cursor = mark.upperBound
        }
        if cursor < text.endIndex {
            runs.append(Run(text: String(text[cursor...]), isMatch: false))
        }
        return runs
    }
}
