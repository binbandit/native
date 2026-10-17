import Git

/// A file as the commit form lists it: once, even when part of it is staged and part isn't.
struct GitCommitFile: Identifiable, Hashable {
    let path: String
    let kind: FileChange.Kind
    let stats: LineStats
    /// Every change to the file, across areas; committing the file commits all of them.
    let changes: [FileChange]

    var id: String { path }

    /// One entry per path, in the order the changes come (conflicts, staged, unstaged, untracked).
    static func files(from changes: [FileChange]) -> [GitCommitFile] {
        var order: [String] = []
        var byPath: [String: [FileChange]] = [:]
        for change in changes {
            if byPath[change.path] == nil { order.append(change.path) }
            byPath[change.path, default: []].append(change)
        }
        return order.compactMap { path in
            guard let changes = byPath[path], let first = changes.first else { return nil }
            return GitCommitFile(
                path: path,
                kind: first.kind,
                stats: changes.reduce(LineStats.zero) { $0 + ($1.stats ?? .zero) },
                changes: changes
            )
        }
    }

    /// What's staged when anything is, as `git commit` would take; otherwise everything.
    static func defaultSelection(from changes: [FileChange]) -> Set<String> {
        let staged = changes.filter { $0.area == .staged }
        return Set((staged.isEmpty ? changes : staged).map(\.path))
    }
}
