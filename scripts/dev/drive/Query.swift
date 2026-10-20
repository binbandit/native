import Foundation

/// What `find`, `press`, `set`, `wait` and the rest look for: an identifier or label, optionally
/// narrowed to a role.
struct Query {
    let text: String
    /// A role with or without its `AX` prefix, in any case: `button`, `AXTextArea`, `searchfield`.
    let role: String?

    /// How well `node` matches, best first: its identifier, its exact title or label, any of its
    /// texts ignoring case, any of them containing the query. nil when it doesn't.
    func rank(_ node: Node) -> Int? {
        if let role, !Self.sameRole(role, node.role), !Self.sameRole(role, node.subrole) { return nil }
        if node.identifier == text { return 0 }
        if node.title == text || node.label == text { return 1 }
        let texts = node.texts
        if texts.contains(where: {
            $0.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return 2
        }
        if texts.contains(where: { $0.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
            return 3
        }
        return nil
    }

    /// The nodes that match, best rank first and in reading order within a rank.
    func matches(in nodes: [Node]) -> [Node] {
        nodes.enumerated()
            .compactMap { index, node in rank(node).map { (rank: $0, index: index, node: node) } }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.node)
    }

    private static func sameRole(_ wanted: String, _ role: String?) -> Bool {
        guard let role else { return false }
        let bare = { (name: String) in (name.hasPrefix("AX") ? String(name.dropFirst(2)) : name).lowercased() }
        return bare(wanted) == bare(role)
    }
}
