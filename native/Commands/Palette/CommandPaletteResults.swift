import Foundation
import NativeCommands

/// The palette's list for what's typed: sections of items, best first.
///
/// With nothing typed: what the user ran recently, then a few tasks, then every command, project
/// and Settings page. With text: everything that matches, each kind in its own section, sections
/// ordered by their best match, recently used items nudged up within their tier.
struct CommandPaletteResults {
    struct Section: Identifiable {
        let title: String
        let rows: [Row]

        var id: String { title }
    }

    struct Row: Identifiable {
        let item: CommandPaletteItem
        /// The title's matched characters, as character offsets.
        let highlights: [Range<Int>]

        var id: CommandPaletteItem.ID { item.id }
    }

    let sections: [Section]
    /// The rows in display order, for ↑ and ↓.
    let rows: [Row]

    private static let recentLimit = 5
    /// With nothing typed, how many of each kind show (commands show in full).
    /// With nothing typed, tasks lead: going back to recent work is the most common jump.
    private static let browseOrder: [CommandPaletteItem.Kind] = [.task, .command, .project, .settings]
    private static let browseLimits: [CommandPaletteItem.Kind: Int] = [.task: 6, .project: 6]

    init(items: [CommandPaletteItem], query: String, recents: [CommandPaletteItem.ID]) {
        let query = query.trimmingCharacters(in: .whitespaces)
        sections =
            query.isEmpty ? Self.browse(items, recents: recents) : Self.search(items, query: query, recents: recents)
        rows = sections.flatMap(\.rows)
    }

    private static func browse(_ items: [CommandPaletteItem], recents: [CommandPaletteItem.ID]) -> [Section] {
        var byID: [CommandPaletteItem.ID: CommandPaletteItem] = [:]
        for item in items where byID[item.id] == nil {
            byID[item.id] = item
        }
        let recent = recents.compactMap { byID[$0] }.prefix(recentLimit)
        let recentIDs = Set(recent.map(\.id))
        let kinds = browseOrder.map { kind in
            let listed = items.filter { $0.kind == kind && !recentIDs.contains($0.id) }
            return Section(
                title: kind.title,
                rows: listed.prefix(browseLimits[kind] ?? listed.count).map { Row(item: $0, highlights: []) })
        }
        return ([Section(title: "Recent", rows: recent.map { Row(item: $0, highlights: []) })] + kinds)
            .filter { !$0.rows.isEmpty }
    }

    private static func search(
        _ items: [CommandPaletteItem], query: String, recents: [CommandPaletteItem.ID]
    ) -> [Section] {
        let scored = items.enumerated().compactMap { offset, item -> (row: Row, score: Int, offset: Int)? in
            // "Search transcripts for …" always applies; it goes last.
            if item.kind == .query {
                return (Row(item: item, highlights: []), 0, offset)
            }
            guard let match = FuzzyMatch(query, title: item.title, keywords: item.keywords + [item.subtitle ?? ""])
            else { return nil }
            // A recent item moves ahead of others in its tier, never into a better tier.
            let recency = recents.firstIndex(of: item.id).map { recentLimit - min($0, recentLimit - 1) } ?? 0
            return (Row(item: item, highlights: match.highlights), match.score * 10 + recency, offset)
        }
        let grouped = Dictionary(grouping: scored) { $0.row.item.kind }
        return
            grouped
            .map { kind, entries in
                let sorted = entries.sorted { ($0.score, -$0.offset) > ($1.score, -$1.offset) }
                return (
                    kind: kind, best: sorted.first?.score ?? 0,
                    section: Section(title: kind.title, rows: sorted.map(\.row))
                )
            }
            .sorted { lhs, rhs in
                if (lhs.kind == .query) != (rhs.kind == .query) { return rhs.kind == .query }
                return (lhs.best, -lhs.kind.rawValue) > (rhs.best, -rhs.kind.rawValue)
            }
            .map(\.section)
    }
}
