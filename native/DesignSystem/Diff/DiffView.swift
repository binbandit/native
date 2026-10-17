import SwiftUI

/// A line diff of one file change, shared by the transcript and Git: a header naming the file
/// with its line counts, then the changed lines with a few lines of context, each marked by a
/// colored bar, its line number and a tinted background (the reference app's diff layout).
public struct DiffView: View {
    let path: String
    let oldText: String?
    let newText: String
    let isEmbedded: Bool

    /// - Parameters:
    ///   - oldText: The file before the change; nil for a new file.
    ///   - isEmbedded: Draws only the lines, for frames that already name the file and its counts
    ///     (a tool row's details, a Git pane).
    public init(path: String, oldText: String?, newText: String, isEmbedded: Bool = false) {
        self.path = path
        self.oldText = oldText
        self.newText = newText
        self.isEmbedded = isEmbedded
    }

    public var body: some View {
        let (rows, stats) = DiffRow.rows(oldText: oldText, newText: newText)
        if isEmbedded {
            DiffLines(rows: rows)
        } else {
            let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            VStack(alignment: .leading, spacing: 0) {
                header(stats)
                SeparatorLine()
                DiffLines(rows: rows)
            }
            .background(.dsSurface, in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        }
    }

    private func header(_ stats: DiffStats) -> some View {
        let file = (path as NSString).lastPathComponent
        let directory = (path as NSString).deletingLastPathComponent
        return HStack(spacing: DS.Space.sm) {
            Image(systemName: oldText == nil ? "doc.badge.plus" : "doc.text")
                .foregroundStyle(.dsTextTertiary)
            Text(
                "\(Text(directory.isEmpty ? "" : directory + "/").foregroundStyle(.dsTextTertiary))\(Text(file).foregroundStyle(.dsTextPrimary))"
            )
            .lineLimit(1)
            .truncationMode(.head)
            Spacer(minLength: DS.Space.md)
            DiffStatsText(stats: stats)
        }
        .font(.dsCaption)
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
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
        .padding(.vertical, DS.Space.xs)
        .font(.dsMonoCaption)
        .foregroundStyle(.dsTextPrimary)
        .textSelection(.enabled)
    }
}

/// One line: a colored change marker, the line number, then the text.
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
                .foregroundStyle(.dsTextTertiary)
                .padding(.leading, 10)
                .padding(.trailing, DS.Space.md)
            if row.kind == .gap {
                Text(row.text)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
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
                    .padding(.trailing, DS.Space.md)
                Rectangle()
                    .fill(.dsSeparator)
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
        case .added: .dsSuccess
        case .removed: .dsDanger
        case .context, .gap: nil
        }
    }

    private var background: Color {
        if let tint {
            tint.opacity(0.12)
        } else if row.kind == .gap {
            .dsHover
        } else {
            .clear
        }
    }
}

#Preview("Diff") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            DiffView(
                path: "native/Views/SidebarView.swift",
                oldText:
                    "struct SidebarView {\n    let title = \"Tasks\"\n    var body: some View {\n        List {}\n    }\n}\n",
                newText:
                    "struct SidebarView {\n    let title = \"Projects\"\n    var body: some View {\n        List {}\n            .listStyle(.sidebar)\n    }\n}\n"
            )
            DiffView(path: "README.md", oldText: nil, newText: "# Native\n\nRun coding agents side by side.\n")
        }
        .frame(width: 520)
    }
}
