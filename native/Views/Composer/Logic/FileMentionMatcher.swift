/// Ranks project files for an `@` query: the query's characters in order (a fuzzy subsequence), with
/// more credit for matches in the file name, at word starts and in runs; changed and recently
/// mentioned files first among equals, then shorter paths.
struct FileMentionMatcher {
    let changed: Set<String>
    /// Most recent first.
    let recent: [String]

    func matches(for query: String, in files: [String], limit: Int) -> [String] {
        let query = query.lowercased()
        guard !query.isEmpty else {
            // Nothing typed yet: what the user is most likely after, then the rest in order.
            let available = Set(files)
            var seen = Set<String>()
            let preferred = (recent + changed.sorted()).filter { available.contains($0) && seen.insert($0).inserted }
            let rest = files.lazy.filter { !seen.contains($0) }.prefix(limit)
            return Array((preferred + rest).prefix(limit))
        }
        return
            files
            .compactMap { path in score(path, for: query).map { (path, $0) } }
            .sorted { ($0.1, -$0.0.count) > ($1.1, -$1.0.count) }
            .prefix(limit)
            .map(\.0)
    }

    /// Nil when the query's characters don't all appear in order.
    func score(_ path: String, for query: String) -> Int? {
        let lower = Array(path.lowercased())
        let nameStart = (lower.lastIndex(of: "/") ?? -1) + 1
        var score = 0
        var position = 0
        var previous: Int?
        for character in query {
            guard let index = lower[position...].firstIndex(of: character) else { return nil }
            score += 1
            if index >= nameStart { score += 2 }
            if index == nameStart || index > 0 && "/_-. ".contains(lower[index - 1]) { score += 3 }
            if let previous, index == previous + 1 { score += 2 }
            previous = index
            position = index + 1
        }
        if changed.contains(path) { score += 4 }
        if let rank = recent.firstIndex(of: path) { score += max(6 - rank, 1) }
        return score
    }
}
