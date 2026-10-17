import Foundation

/// What settings search can find: every pane, and every row a pane lists. Matching follows
/// Conductor's settings search: each query word must match a field as a substring or, failing that,
/// as an in-order subsequence; substrings and word starts rank higher, and titles outrank
/// descriptions, which outrank keywords.
struct SettingsSearchIndex {
    struct Item: Identifiable {
        let paneID: SettingsPane.ID
        let paneTitle: String
        let systemImage: String
        /// Nil for the pane itself.
        let rowID: SettingsRowID?
        let title: String
        let description: String
        let keywords: [String]

        var id: String { "\(paneID.rawValue)/\(rowID?.rawValue ?? "")" }
    }

    struct Result: Identifiable {
        let item: Item
        let score: Double
        /// Offsets into the title's characters that the query matched, for highlighting.
        let titleMatches: Set<Int>

        var id: String { item.id }
    }

    let items: [Item]

    @MainActor
    init(panes: [SettingsPane]) {
        items = panes.flatMap { pane in
            let paneItem = Item(paneID: pane.id, paneTitle: pane.title, systemImage: pane.systemImage, rowID: nil, title: pane.title, description: "", keywords: pane.keywords)
            return [paneItem] + pane.searchEntries().map { entry in
                Item(paneID: pane.id, paneTitle: pane.title, systemImage: pane.systemImage, rowID: entry.id, title: entry.title, description: entry.description, keywords: entry.keywords)
            }
        }
    }

    func results(for query: String, limit: Int) -> [Result] {
        let words = Self.words(in: query)
        guard !words.isEmpty else { return [] }
        let ranked = items.compactMap { item -> Result? in
            let fields = [item.title, item.description, item.keywords.joined(separator: " ")]
            var score = 0.0
            for word in words {
                let best = fields.enumerated().compactMap { rank, field in
                    Self.match(word, in: field).map { $0.score / (1 + Double(rank) * 0.25) }
                }.max()
                guard let best else { return nil }
                score += best
            }
            return Result(item: item, score: score, titleMatches: Self.highlights(for: words, in: item.title))
        }
        // A stable sort keeps equal scores in pane order.
        return ranked.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .prefix(limit)
            .map(\.element)
    }

    private static func words(in query: String) -> [[Character]] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(Array.init)
    }

    private static func highlights(for words: [[Character]], in text: String) -> Set<Int> {
        var offsets = Set<Int>()
        for word in words {
            guard let hit = match(word, in: text) else { return [] }
            offsets.formUnion(hit.offsets)
        }
        return offsets
    }

    private static func match(_ word: [Character], in text: String) -> (score: Double, offsets: [Int])? {
        let haystack = text.map { $0.lowercased().first ?? $0 }
        if let start = firstIndex(of: word, in: haystack) {
            let isWordStart = start == 0 || " -_/.".contains(haystack[start - 1])
            return (2 + (isWordStart ? 1 : 0) + (start == 0 ? 1 : 0), Array(start..<start + word.count))
        }
        var offsets: [Int] = []
        var from = 0
        for character in word {
            guard let found = haystack[from...].firstIndex(of: character) else { return nil }
            offsets.append(found)
            from = found + 1
        }
        // Scattered subsequences are weak matches; tighter spans score better.
        let span = (offsets.last ?? 0) - (offsets.first ?? 0) + 1
        return (Double(word.count) / Double(span), offsets)
    }

    private static func firstIndex(of word: [Character], in haystack: [Character]) -> Int? {
        guard !word.isEmpty, word.count <= haystack.count else { return nil }
        return (0...haystack.count - word.count).first { start in
            haystack[start..<start + word.count].elementsEqual(word)
        }
    }
}
