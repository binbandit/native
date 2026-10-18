import SwiftUI

/// Renders agent Markdown (block-level structure included) with native SwiftUI views.
///
/// Foundation parses the source; each run's `presentationIntent` locates it in the block tree
/// (paragraph inside list item inside list, ...), and the tree renders recursively. Inline styles
/// (emphasis, code spans, links) stay on the `AttributedString` and render natively in `Text`.
struct MarkdownView: View, Equatable {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        #if DEBUG
        let _ = RenderProbe.hit("MarkdownView")
        #endif
        if let blocks = MarkdownParseCache.blocks(for: source) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(blocks) { block in
                    MarkdownBlockView(node: block)
                        .padding(.top, block.id == blocks.first?.id ? 0 : block.spacingAbove)
                }
            }
            .textSelection(.enabled)
        } else {
            Text(verbatim: source)
                .textSelection(.enabled)
        }
    }
}

/// Parsed documents by source, so a message is parsed once per text it has had: finished
/// messages never re-parse, and a streaming one only when a chunk arrives.
private enum MarkdownParseCache {
    private static var documents: [String: [MarkdownNode]] = [:]
    private static var bytes = 0
    /// Plenty for every message on screen; past either limit the cache starts over rather than
    /// tracking age. The byte limit matters while a long reply streams: every chunk is a new
    /// source, and each one holds the whole reply so far.
    private static let capacity = 512
    private static let byteCapacity = 4 << 20

    static func blocks(for source: String) -> [MarkdownNode]? {
        if let blocks = documents[source] { return blocks }
        guard let blocks = MarkdownNode.blocks(from: source.keepingLineBreaks) else { return nil }
        if documents.count >= capacity || bytes >= byteCapacity {
            documents.removeAll(keepingCapacity: true)
            bytes = 0
        }
        documents[source] = blocks
        bytes += source.utf8.count
        return blocks
    }
}

extension String {
    /// Agents write chat, where a single newline is a line break (as in GitHub comments): "one
    /// number per line" must not collapse into one line. Markdown would join those lines into a
    /// paragraph, so every line followed by another non-blank line ends in a hard break. Fenced
    /// code keeps its text as is, and blank lines still separate paragraphs.
    fileprivate var keepingLineBreaks: String {
        var lines = components(separatedBy: "\n")
        var fence: Substring?
        for index in lines.indices {
            let trimmed = lines[index].drop { $0 == " " }
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = trimmed.prefix(3)
                continue
            }
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            let isBlank = { (line: String) in line.allSatisfy(\.isWhitespace) }
            if !isBlank(lines[index]), !isBlank(next), !lines[index].hasSuffix("  "), !lines[index].hasSuffix("\\") {
                lines[index] += "  "
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Block tree

private struct MarkdownNode: Identifiable {
    /// The parser's identity for this block, unique within one document.
    let id: Int
    let kind: PresentationIntent.Kind
    /// Inline content; only innermost blocks (paragraphs, headers, code, table cells) have any.
    var text = AttributedString()
    var children: [MarkdownNode] = []

    static func blocks(from source: String) -> [MarkdownNode]? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let attributed = try? AttributedString(markdown: source, options: options) else { return nil }
        var root = MarkdownNode(id: -1, kind: .paragraph)
        for run in attributed.runs {
            let intent = run.presentationIntent ?? PresentationIntent(.paragraph, identity: -2)
            // `components` runs innermost first; insert from the outermost container down.
            root.insert(styled(attributed[run.range]), along: intent.components.reversed()[...])
        }
        return root.children
    }

    private mutating func insert(_ text: AttributedString, along path: ArraySlice<PresentationIntent.IntentType>) {
        guard let component = path.first else {
            self.text.append(text)
            return
        }
        // Runs arrive in document order, so a block's runs are contiguous.
        if children.last?.id != component.identity {
            children.append(MarkdownNode(id: component.identity, kind: component.kind))
        }
        children[children.count - 1].insert(text, along: path.dropFirst())
    }

    /// Gives code spans a faint backdrop so they read as code, not just a font change.
    private static func styled(_ run: AttributedSubstring) -> AttributedString {
        var text = AttributedString(run)
        if text.inlinePresentationIntent?.contains(.code) == true {
            text.backgroundColor = .dsFill
        }
        return text
    }

    var spacingAbove: CGFloat {
        if case .header = kind { DS.Space.xl } else { DS.Space.md }
    }
}

// MARK: - Rendering

private struct MarkdownBlockView: View {
    let node: MarkdownNode
    var listDepth = 0

    var body: some View {
        #if DEBUG
        let _ = RenderProbe.hit("MarkdownBlock")
        #endif
        switch node.kind {
        case .header(let level):
            Text(node.text)
                .font(Self.headerFont(level))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .codeBlock(let language):
            CodeBlockView(code: String(node.text.characters), language: language)
        case .thematicBreak:
            Divider()
                .padding(.vertical, DS.Space.xs)
        case .blockQuote:
            children
                .foregroundStyle(.dsTextSecondary)
                .padding(.leading, DS.Space.lg)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.dsTextTertiary)
                        .frame(width: TranscriptMetrics.quoteRailWidth)
                }
        case .orderedList, .unorderedList:
            list
        case .table(let columns):
            MarkdownTableView(rows: node.children, columns: columns)
        default:
            // Paragraphs, plus containers (list items) holding nested blocks.
            if node.children.isEmpty {
                Text(node.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                children
            }
        }
    }

    private var children: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ForEach(node.children) { child in
                MarkdownBlockView(node: child, listDepth: listDepth)
            }
        }
    }

    private var list: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Space.sm, verticalSpacing: DS.Space.xs) {
            ForEach(node.children) { item in
                GridRow(alignment: .firstTextBaseline) {
                    Text(marker(for: item))
                        .monospacedDigit()
                        .foregroundStyle(.dsTextSecondary)
                        .gridColumnAlignment(.trailing)
                    MarkdownBlockView(node: item, listDepth: listDepth + 1)
                }
            }
        }
        .padding(.leading, DS.Space.xs)
    }

    private func marker(for item: MarkdownNode) -> String {
        guard node.kind == .orderedList, case .listItem(let ordinal) = item.kind else {
            return ["•", "◦", "▪︎"][listDepth % 3]
        }
        return "\(ordinal)."
    }

    private static func headerFont(_ level: Int) -> Font {
        switch level {
        case 1: .ds(17, weight: .semibold)
        case 2: .ds(15, weight: .semibold)
        default: .dsCalloutSemibold
        }
    }
}

private struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.dsMicro)
                    .foregroundStyle(.dsTextSecondary)
            }
            ScrollView(.horizontal) {
                HighlightedCode(code.hasSuffix("\n") ? String(code.dropLast()) : code, language: language)
                    .codeTextStyle()
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedSurface(.dsCodeBlockBackground, minimumRadius: DS.Radius.card)
    }
}

private struct MarkdownTableView: View {
    let rows: [MarkdownNode]
    let columns: [PresentationIntent.TableColumn]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Space.xl, verticalSpacing: DS.Space.sm) {
            ForEach(rows) { row in
                let isHeader = row.kind == .tableHeaderRow
                GridRow {
                    // Empty cells produce no runs, so place cells by column index.
                    let cells = row.cellsByColumn
                    ForEach(columns.indices, id: \.self) { column in
                        Text(cells[column] ?? AttributedString())
                            .fontWeight(isHeader ? .semibold : nil)
                            .gridColumnAlignment(Self.alignment(columns[column].alignment))
                    }
                }
                if isHeader || row.id != rows.last?.id {
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
        }
    }

    private static func alignment(_ alignment: PresentationIntent.TableColumn.Alignment) -> HorizontalAlignment {
        switch alignment {
        case .center: .center
        case .right: .trailing
        default: .leading
        }
    }
}

private extension MarkdownNode {
    var cellsByColumn: [Int: AttributedString] {
        Dictionary(
            children.compactMap { cell in
                guard case .tableCell(let column) = cell.kind else { return nil }
                return (column, cell.text)
            }, uniquingKeysWith: { first, _ in first })
    }
}

#if DEBUG
#Preview("Markdown") {
    ScrollView {
        MarkdownView(TranscriptFixtures.markdown)
            .padding(20)
    }
    .frame(width: 640, height: 720)
}
#endif
