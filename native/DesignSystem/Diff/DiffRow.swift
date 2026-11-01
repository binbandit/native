import Foundation

/// One line of a drawn diff: a change, context, or a gap standing in for folded lines.
nonisolated struct DiffRow: Equatable {
    enum Kind: Equatable { case context, added, removed, gap }

    let kind: Kind
    /// The new file's line number, or the old file's for removed lines.
    var number: Int?
    let text: String
    var oldNumber: Int? = nil

    static let contextLines = 3
    static let maxRows = 400

    /// The rows to draw for a file change (context folded, long diffs truncated) and its counts.
    static func rows(oldText: String?, newText: String) -> (rows: [DiffRow], stats: DiffStats) {
        let oldLines = oldText.map(lines) ?? []
        let newLines = lines(newText)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in newLines.difference(from: oldLines) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        // Walk both files together; at each point removals come before insertions.
        var all: [DiffRow] = []
        var old = 0, new = 0
        while old < oldLines.count || new < newLines.count {
            if old < oldLines.count, removed.contains(old) {
                all.append(DiffRow(kind: .removed, number: old + 1, text: oldLines[old], oldNumber: old + 1))
                old += 1
            } else if new < newLines.count, inserted.contains(new) {
                all.append(DiffRow(kind: .added, number: new + 1, text: newLines[new]))
                new += 1
            } else if old < oldLines.count, new < newLines.count {
                all.append(DiffRow(kind: .context, number: new + 1, text: newLines[new], oldNumber: old + 1))
                old += 1
                new += 1
            } else {
                break
            }
        }
        return (truncated(collapsingContext(all)), DiffStats(added: inserted.count, removed: removed.count))
    }

    /// Keeps a few lines of context around each change and folds the rest into gap rows.
    private static func collapsingContext(_ lines: [DiffRow]) -> [DiffRow] {
        let changed = lines.indices.filter { lines[$0].kind != .context }
        guard !changed.isEmpty else { return lines }
        var visible = IndexSet()
        for index in changed {
            visible.insert(integersIn: max(index - contextLines, 0)...min(index + contextLines, lines.count - 1))
        }
        var rows: [DiffRow] = []
        var hidden = 0
        for index in lines.indices {
            if visible.contains(index) {
                if hidden > 0 { rows.append(.gap(hidden)) }
                hidden = 0
                rows.append(lines[index])
            } else {
                hidden += 1
            }
        }
        if hidden > 0 { rows.append(.gap(hidden)) }
        return rows
    }

    private static func truncated(_ rows: [DiffRow]) -> [DiffRow] {
        guard rows.count > maxRows else { return rows }
        return Array(rows.prefix(maxRows)) + [DiffRow(kind: .gap, text: "\(rows.count - maxRows) more lines not shown")]
    }

    private static func gap(_ count: Int) -> DiffRow {
        DiffRow(kind: .gap, text: count == 1 ? "1 unchanged line" : "\(count) unchanged lines")
    }

    /// Lines without their terminators; a trailing newline doesn't start an extra empty line.
    private static func lines(_ text: String) -> [String] {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }
}
