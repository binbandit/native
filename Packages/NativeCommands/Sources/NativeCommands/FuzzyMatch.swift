/// How well a query matches a title, ranked in tiers as the reference app's palette ranks them: the whole
/// title, its start, a word's start, its initials, anywhere in it, then the keywords, then the
/// query's letters in order ("nwse" finds "New Session").
public struct FuzzyMatch: Equatable, Sendable {
    public let score: Int
    /// The title's matched characters, as character offsets, for highlighting.
    public let highlights: [Range<Int>]

    /// Matches `query` against `title`, and `keywords` when the title doesn't match. An empty query
    /// matches everything with a score of 0; nil means no match.
    public init?(_ query: String, title: String, keywords: [String] = []) {
        let query = Self.folded(query.trimmingCharacters(in: .whitespaces))
        guard !query.isEmpty else {
            self.init(score: 0, highlights: [])
            return
        }
        let text = Self.folded(title)
        let terms = query.split(separator: " ").map(Array.init)
        if let match = Self.titleMatch(query, terms: terms, in: text) {
            self = match
            return
        }
        let keywords = keywords.map(Self.folded)
        if keywords.contains(where: { $0.starts(with: query) || Self.wordStarts(in: $0).contains { Array($0).starts(with: query) } }) {
            self.init(score: Tier.keywordPrefix, highlights: [])
        } else if keywords.contains(where: { $0.firstRange(of: query) != nil }) {
            self.init(score: Tier.keywordSubstring, highlights: [])
        } else if terms.count > 1, terms.allSatisfy({ term in ([text] + keywords).contains { $0.firstRange(of: term) != nil } }) {
            self.init(score: Tier.allTermsAnywhere, highlights: Self.termRanges(terms, in: text))
        } else if let subsequence = Self.subsequence(query.filter { $0 != " " }, in: text) {
            self = subsequence
        } else {
            return nil
        }
    }

    private init(score: Int, highlights: [Range<Int>]) {
        self.score = score
        self.highlights = highlights
    }

    enum Tier {
        static let exact = 100
        static let prefix = 90
        static let wordPrefix = 80
        static let initials = 75
        static let substring = 70
        static let allTermsInTitle = 65
        static let keywordPrefix = 50
        static let keywordSubstring = 40
        static let allTermsAnywhere = 35
        /// Letters in order score between this and `allTermsAnywhere`, more when they're together.
        static let subsequence = 10
    }

    private static func titleMatch(_ query: [Character], terms: [[Character]], in text: [Character]) -> FuzzyMatch? {
        if text == query {
            return FuzzyMatch(score: Tier.exact, highlights: [0..<text.count])
        }
        if text.starts(with: query) {
            return FuzzyMatch(score: Tier.prefix, highlights: [0..<query.count])
        }
        if let start = wordStartOffsets(in: text).first(where: { text[$0...].starts(with: query) }) {
            return FuzzyMatch(score: Tier.wordPrefix, highlights: [start..<start + query.count])
        }
        let starts = wordStartOffsets(in: text)
        if query.count >= 2, !query.contains(" "), starts.map({ text[$0] }).starts(with: query) {
            return FuzzyMatch(score: Tier.initials, highlights: starts.prefix(query.count).map { $0..<$0 + 1 })
        }
        if let range = text.firstRange(of: query) {
            return FuzzyMatch(score: Tier.substring, highlights: [range])
        }
        if terms.count > 1, terms.allSatisfy({ text.firstRange(of: $0) != nil }) {
            return FuzzyMatch(score: Tier.allTermsInTitle, highlights: termRanges(terms, in: text))
        }
        return nil
    }

    /// The query's letters in order, scored by how many sit next to each other or start a word.
    private static func subsequence(_ query: [Character], in text: [Character]) -> FuzzyMatch? {
        guard !query.isEmpty else { return nil }
        let starts = Set(wordStartOffsets(in: text))
        var offsets: [Int] = []
        var next = 0
        for character in query {
            guard let found = text[next...].firstIndex(of: character) else { return nil }
            offsets.append(found)
            next = found + 1
        }
        let adjacent = zip(offsets, offsets.dropFirst()).filter { $1 == $0 + 1 }.count
        let atWordStarts = offsets.filter(starts.contains).count
        let bonus = min(adjacent * 2 + atWordStarts * 3, Tier.allTermsAnywhere - Tier.subsequence - 1)
        return FuzzyMatch(score: Tier.subsequence + bonus, highlights: merged(offsets.map { $0..<$0 + 1 }))
    }

    private static func termRanges(_ terms: [[Character]], in text: [Character]) -> [Range<Int>] {
        merged(terms.compactMap { text.firstRange(of: $0) }.sorted { $0.lowerBound < $1.lowerBound })
    }

    private static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        ranges.reduce(into: []) { result, range in
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
    }

    /// Lowercased one character at a time, so offsets stay the title's.
    private static func folded(_ text: String) -> [Character] {
        text.map { $0.lowercased().first ?? $0 }
    }

    private static func isDelimiter(_ character: Character) -> Bool {
        character.isWhitespace || "-_/.·›()…:,'\u{2019}\u{201C}\u{201D}\"".contains(character)
    }

    private static func wordStartOffsets(in text: [Character]) -> [Int] {
        text.indices.filter { index in
            !isDelimiter(text[index]) && (index == 0 || isDelimiter(text[index - 1]))
        }
    }

    private static func wordStarts(in text: [Character]) -> [ArraySlice<Character>] {
        wordStartOffsets(in: text).map { text[$0...] }
    }
}
