import CodeThemes
import SwiftUI

/// A line diff of one file change, shared by the transcript and Git: a header naming the file
/// with its line counts, then the changed lines with a few lines of context, each marked by a
/// colored bar, its line number and a tinted background (the reference app's diff layout). Lines are
/// highlighted in the user's code theme for the language the path implies.
public struct DiffView: View {
    let path: String
    let oldText: String?
    let newText: String
    let isEmbedded: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsLightTone) private var lightTone
    @Environment(\.dsCodeThemes) private var codeThemes

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
        let language = CodeLanguage.forPath(path)
        let lines = DiffHighlightedLines(
            colors: DSCodeColors(.code(colorScheme: colorScheme, lightTone: lightTone, themes: codeThemes), on: .surface),
            new: CodeHighlighter.lines(newText, language: language),
            old: oldText.map { CodeHighlighter.lines($0, language: language) } ?? []
        )
        if isEmbedded {
            DiffLines(rows: rows, lines: lines)
        } else {
            let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            VStack(alignment: .leading, spacing: 0) {
                header(stats)
                SeparatorLine()
                DiffLines(rows: rows, lines: lines)
            }
            .background(.dsDiffBackground, in: shape)
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

/// Each file's lines highlighted, and the colors to draw them in.
private struct DiffHighlightedLines {
    let colors: DSCodeColors
    let new: [[CodeSegment]]
    let old: [[CodeSegment]]

    /// A row's text in color: removed lines come from the old file, the rest from the new one.
    func text(for row: DiffRow) -> AttributedString? {
        guard let number = row.number, row.kind != .gap else { return nil }
        let file = row.kind == .removed ? old : new
        return file.indices.contains(number - 1) ? colors.text(file[number - 1]) : nil
    }
}

private struct DiffLines: View {
    let rows: [DiffRow]
    let lines: DiffHighlightedLines

    var body: some View {
        // A hidden template reserves the gutter width for the longest line number.
        let largest = rows.compactMap(\.number).max() ?? 0
        let numberTemplate = String(repeating: "8", count: max(String(largest).count, 2))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                DiffRowView(row: rows[index], numberTemplate: numberTemplate, text: lines.text(for: rows[index]), colors: lines.colors)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .font(.dsMonoCaption)
        .foregroundStyle(lines.colors.isNative ? Color.dsTextPrimary : lines.colors.color(.foreground))
        // A themed diff draws on its theme's background wherever it's embedded.
        .background(lines.colors.isNative ? AnyShapeStyle(.clear) : AnyShapeStyle(.dsDiffBackground))
        .textSelection(.enabled)
    }
}

/// One line: a colored change marker, the line number, then the text.
private struct DiffRowView: View {
    let row: DiffRow
    let numberTemplate: String
    /// The line in the code theme's colors, when it's a line of the file.
    let text: AttributedString?
    let colors: DSCodeColors

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
                .foregroundStyle(colors.isNative ? Color.dsTextTertiary : colors.color(.comment))
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
                Group {
                    if let text, !row.text.isEmpty {
                        Text(text)
                    } else {
                        Text(verbatim: row.text.isEmpty ? " " : row.text)
                    }
                }
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
