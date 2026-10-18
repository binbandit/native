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

    /// About `width` characters of `text` around the first of `words`, with every occurrence of
    /// them marked. Matches are case- and diacritic-insensitive, and inside identifiers too, so
    /// `model` lights up in `AppModel`.
    public init(text: String, words: [String], width: Int = 180) {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let firstMatch = words.compactMap { text.range(of: $0, options: options)?.lowerBound }.min()
        var window = Substring(text)
        var leading = "", trailing = ""
        if text.count > width {
            let lead = width / 3
            let start = firstMatch.map { text.index($0, offsetBy: -lead, limitedBy: text.startIndex) ?? text.startIndex }
                ?? text.startIndex
            let end = text.index(start, offsetBy: width, limitedBy: text.endIndex) ?? text.endIndex
            window = Self.trimmedToWords(text[start..<end], atStart: start != text.startIndex, atEnd: end != text.endIndex)
            leading = start == text.startIndex ? "" : "…"
            trailing = end == text.endIndex ? "" : "…"
        }
        let excerpt = leading + SearchText.collapsingWhitespace(window) + trailing
        runs = Self.runs(of: excerpt, marking: words.filter { $0.count > 1 || words.count == 1 }, options: options)
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

    private static func runs(of text: String, marking words: [String], options: String.CompareOptions) -> [Run] {
        var marks: [Range<String.Index>] = []
        for word in words {
            var searchStart = text.startIndex
            while let range = text.range(of: word, options: options, range: searchStart..<text.endIndex) {
                marks.append(range)
                searchStart = range.upperBound
            }
        }
        marks.sort { $0.lowerBound < $1.lowerBound }
        var runs: [Run] = []
        var cursor = text.startIndex
        for mark in marks where mark.lowerBound >= cursor {
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
