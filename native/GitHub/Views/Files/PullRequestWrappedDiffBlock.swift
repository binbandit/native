import CodeThemes
import GitHub
import SwiftUI

/// A block drawn line by line so a long line can wrap under its own start, with the line numbers
/// on its first row. Slower than the one-text block, so it's only used where wrapping was asked
/// for: a file set to wrap, or a block with a cut-off line the user opened. In the latter, the
/// block's other long lines stay cut off with their own "…".
struct PullRequestWrappedDiffBlock: View {
    let model: PullRequestPageModel
    let path: String
    let hunk: DiffHunk
    let range: Range<Int>
    let numberWidth: Int
    let highlighted: [[CodeSegment]]?
    let colors: DSCodeColors
    /// Characters of code that fit beside the gutter.
    let columns: Int
    /// The width of one character of code.
    let characterWidth: CGFloat

    @Environment(\.dsCodeFont) private var codeFont

    var body: some View {
        let draftLines = model.draftLines(in: path, hunk: hunk)
        // The one-text block spaces its lines with line spacing; a line per view pads instead.
        let spacing = codeFont.lineSpacing(.compact) / 2
        VStack(alignment: .leading, spacing: 0) {
            ForEach(range, id: \.self) { index in
                let line = hunk.lines[index]
                let code = PullRequestDiffBlockText.code(
                    line, highlighted: highlighted.flatMap { $0.indices.contains(index) ? $0[index] : nil },
                    colors: colors)
                let cut =
                    model.isExpanded(path, hunk, index)
                    ? nil : PullRequestDiffBlockText.cutOff(code, columns: columns)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(PullRequestDiffBlockText.gutter(line, width: numberWidth))
                        .fixedSize()
                        .contentShape(.rect)
                        .onTapGesture { comment(on: index) }
                        .accessibilityHidden(true)
                    Text(cut ?? code)
                        .lineLimit(cut == nil ? nil : 1)
                        .textSelection(.enabled)
                        .simultaneousGesture(
                            SpatialTapGesture().onEnded { value in
                                if cut != nil, value.location.x >= CGFloat(max(columns - 3, 0)) * characterWidth {
                                    model.expandLine(path, hunk, index)
                                }
                            }
                        )
                        .padding(.leading, DS.Space.md + 1)
                        .padding(.trailing, DS.Space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, spacing)
                .background { Rectangle().fill(tint(line.kind, selected: draftLines.contains(index))) }
                .overlay(alignment: .leading) {
                    if let bar = Self.bar(line.kind) { Rectangle().fill(bar).frame(width: 2) }
                }
                .contextMenu {
                    PullRequestDiffLineMenu(model: model, path: path, hunk: hunk, line: index, isCutOff: cut != nil)
                }
                .accessibilityActions {
                    if cut != nil { Button("Show Whole Line") { model.expandLine(path, hunk, index) } }
                }
            }
        }
    }

    private func comment(on index: Int) {
        guard model.page?.isOpen == true, let target = hunk.lines[index].anchor else { return }
        model.beginComment(at: ReviewAnchor(path: path, side: target.side, line: target.line))
    }

    private func tint(_ kind: DiffHunk.Line.Kind, selected: Bool) -> Color {
        if selected { return .dsAccentSubtle }
        return Self.bar(kind).map { $0.opacity(0.12) } ?? .clear
    }

    private static func bar(_ kind: DiffHunk.Line.Kind) -> Color? {
        switch kind {
        case .added: .dsSuccess
        case .removed: .dsDanger
        case .context, .noNewline: nil
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Wrapped diff block - Narrow") {
    DSPreviewPair {
        PullRequestPagePreview { model, _ in
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                ForEach(model.rows.filter(\.isPreviewBlock).prefix(1)) { row in
                    PullRequestFilesRowView(model: model, row: row, width: 420, characterWidth: 7, isShiftDown: false)
                        .onAppear {
                            // How the model keys a wrapped file (PullRequestPageModel+Rows.swift).
                            model.wrappedFiles.insert("github.com/binbandit/native:\(row.path)")
                        }
                }
            }
            .codeTextStyle(.compact)
        }
        .frame(width: 420)
    }
}
#endif
