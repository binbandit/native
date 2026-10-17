import ACP
import SwiftUI

/// A line diff of one file change from a tool call.
struct DiffView: View {
    let diff: FileDiff
    /// Inside a tool row's detail frame the row already names the file and its line stats, so
    /// only the lines are drawn.
    var isEmbedded = false

    var body: some View {
        let (rows, stats) = DiffRow.rows(for: diff)
        if isEmbedded {
            DiffLines(rows: rows)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header(stats)
                Divider()
                DiffLines(rows: rows)
            }
            .nestedSurface(Color(nsColor: .textBackgroundColor), minimumRadius: 8)
        }
    }

    private func header(_ stats: DiffStats) -> some View {
        let path = diff.path as NSString
        let directory = path.deletingLastPathComponent.isEmpty ? "" : path.deletingLastPathComponent + "/"
        return HStack(spacing: 6) {
            Image(systemName: diff.oldText == nil ? "doc.badge.plus" : "doc.text")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("\(Text(directory).foregroundStyle(.secondary))\(Text(path.lastPathComponent).fontWeight(.medium))")
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 8)
            DiffStatsText(stats: stats)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

extension FileDiff {
    /// Lines added and removed, as the diff view counts them.
    var stats: DiffStats { DiffRow.rows(for: self).stats }
}

/// `+3 -1` in green and red; zero counts are left out.
struct DiffStatsText: View {
    let stats: DiffStats

    var body: some View {
        HStack(spacing: 4) {
            if stats.added > 0 {
                Text(verbatim: "+\(stats.added)").foregroundStyle(.green)
            }
            if stats.removed > 0 {
                Text(verbatim: "-\(stats.removed)").foregroundStyle(.red)
            }
        }
        .monospacedDigit()
    }
}

private struct DiffLines: View {
    let rows: [DiffRow]

    var body: some View {
        // A hidden template reserves the gutter width for the longest line number.
        let largest = rows.compactMap(\.number).max() ?? 0
        let numberTemplate = String(repeating: "8", count: max(String(largest).count, 2))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                DiffRowView(row: rows[index], numberTemplate: numberTemplate)
            }
        }
        .padding(.vertical, 4)
        .font(.subheadline.monospaced())
        .textSelection(.enabled)
    }
}

private struct DiffRow {
    enum Kind { case context, added, removed, gap }

    let kind: Kind
    /// The new file's line number, or the old file's for removed lines.
    var number: Int?
    let text: String

    static let contextLines = 3
    static let maxRows = 400

    static func rows(for diff: FileDiff) -> (rows: [DiffRow], stats: DiffStats) {
        let oldLines = diff.oldText?.lines ?? []
        let newLines = diff.newText.lines
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in newLines.difference(from: oldLines) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        // Walk both files together; at each point removals come before insertions.
        var lines: [DiffRow] = []
        var old = 0, new = 0
        while old < oldLines.count || new < newLines.count {
            if old < oldLines.count, removed.contains(old) {
                lines.append(DiffRow(kind: .removed, number: old + 1, text: oldLines[old]))
                old += 1
            } else if new < newLines.count, inserted.contains(new) {
                lines.append(DiffRow(kind: .added, number: new + 1, text: newLines[new]))
                new += 1
            } else if old < oldLines.count, new < newLines.count {
                lines.append(DiffRow(kind: .context, number: new + 1, text: newLines[new]))
                old += 1
                new += 1
            } else {
                break
            }
        }
        return (truncated(collapsingContext(lines)), DiffStats(added: inserted.count, removed: removed.count))
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
}

/// One line: a colored change marker, the line number, then the text (the reference app's diff layout).
private struct DiffRowView: View {
    let row: DiffRow
    let numberTemplate: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: numberTemplate)
                .hidden()
                .overlay(alignment: .trailing) {
                    if row.kind == .gap {
                        Image(systemName: "ellipsis")
                    } else if let number = row.number {
                        Text(verbatim: String(number))
                    }
                }
                .foregroundStyle(.tertiary)
                .padding(.leading, 10)
                .padding(.trailing, 8)
            if row.kind == .gap {
                Text(row.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Empty text has no baseline or height, so blank lines need a space to stay one line tall.
                Text(verbatim: row.text.isEmpty ? " " : row.text)
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.trailing, 10)
        .padding(.vertical, row.kind == .gap ? 3 : 1)
        .background(alignment: .leading) {
            // The gutter's hairline spans the full row height, also for wrapped lines.
            HStack(spacing: 0) {
                Text(verbatim: numberTemplate)
                    .hidden()
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
            }
        }
        .background(background)
        .overlay(alignment: .leading) {
            if let tint {
                Rectangle()
                    .fill(tint)
                    .frame(width: 2)
            }
        }
    }

    private var tint: Color? {
        switch row.kind {
        case .added: .green
        case .removed: .red
        case .context, .gap: nil
        }
    }

    private var background: Color {
        if let tint { tint.opacity(0.12) } else if row.kind == .gap { Color.primary.opacity(0.04) } else { .clear }
    }
}

private extension String {
    /// Lines without their terminators; a trailing newline doesn't start an extra empty line.
    var lines: [String] {
        var lines = split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }
}

#if DEBUG
#Preview("Diffs") {
    ScrollView {
        VStack(spacing: 16) {
            DiffView(diff: TranscriptFixtures.editDiff)
            DiffView(diff: TranscriptFixtures.newFileDiff)
        }
        .padding(20)
    }
    .frame(width: 640, height: 600)
}
#endif
