/// Ranks a project's files and folders for an `@` query: the query's characters in order (a fuzzy
/// subsequence), with more credit for matches in the last path component, at word starts and in
/// runs; changed and recently mentioned paths first among equals, then shorter paths. Folders are
/// written with a trailing "/" (`FileMention.entries(forFiles:)`).
public struct FileMentionMatcher: Sendable {
    public let changed: Set<String>
    /// Most recent first.
    public let recent: [String]

    public init(changed: Set<String>, recent: [String]) {
        self.changed = changed
        self.recent = recent
    }

    public func matches(for query: String, in paths: [String], limit: Int) -> [String] {
        let query = query.lowercased()
        guard !query.isEmpty else {
            // Nothing typed yet: what the user is most likely after, then the rest in order.
            let available = Set(paths)
            var seen = Set<String>()
            let preferred = (recent + changed.sorted()).filter { available.contains($0) && seen.insert($0).inserted }
            let rest = paths.lazy.filter { !seen.contains($0) }.prefix(limit)
            return Array((preferred + rest).prefix(limit))
        }
        return
            paths
            .compactMap { path in score(path, for: query).map { (path, $0) } }
            .sorted { ($0.1, -$0.0.count) > ($1.1, -$1.0.count) }
            .prefix(limit)
            .map(\.0)
    }

    /// Nil when the query's characters don't all appear in order.
    public func score(_ path: String, for query: String) -> Int? {
        let lower = Array(path.lowercased())
        // A folder's name is the component before its trailing slash.
        let nameEnd = lower.last == "/" ? lower.count - 1 : lower.count
        let nameStart = (lower[..<nameEnd].lastIndex(of: "/") ?? -1) + 1
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

extension FileMention {
    /// What the `@` list offers for a project's files: each file, and each folder they're in, written
    /// with a trailing "/". Sorted by path, so a folder comes just before what's in it.
    public static func entries(forFiles files: [String]) -> [String] {
        var folders = Set<String>()
        for file in files {
            var folder = Substring(file)
            while let slash = folder.lastIndex(of: "/") {
                folder = folder[..<slash]
                guard folders.insert(folder + "/").inserted else { break }
            }
        }
        return (files + folders).sorted { $0.lexicographicallyPrecedes($1) }
    }

    /// Whether a path in the `@` list is a folder.
    public static func isFolder(_ path: String) -> Bool {
        path.hasSuffix("/")
    }
}
