import CodeThemes
import GitHub
import SwiftUI

/// A block drawn line by line so long lines wrap under their own start, with the line numbers on
/// the first row of each. Slower than the one-text block, so it's only used where wrapping was
/// asked for: a file set to wrap, or a block with a cut-off line the user opened.
struct PullRequestWrappedDiffBlock: View {
    let model: PullRequestPageModel
    let path: String
    let hunk: DiffHunk
    let range: Range<Int>
    let numberWidth: Int
    let highlighted: [[CodeSegment]]?
    let colors: DSCodeColors

    var body: some View {
        let draftLines = model.draftLines(in: path, hunk: hunk)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(range, id: \.self) { index in
                let line = hunk.lines[index]
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(PullRequestDiffBlockText.gutter(line, width: numberWidth))
                        .fixedSize()
                        .contentShape(.rect)
                        .onTapGesture { comment(on: index) }
                        .accessibilityHidden(true)
                    Text(
                        PullRequestDiffBlockText.code(
                            line, highlighted: highlighted.flatMap { $0.indices.contains(index) ? $0[index] : nil },
                            colors: colors)
                    )
                    .padding(.leading, DS.Space.md + 1)
                    .padding(.trailing, DS.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .background { Rectangle().fill(tint(line.kind, selected: draftLines.contains(index))) }
                .overlay(alignment: .leading) {
                    if let bar = Self.bar(line.kind) { Rectangle().fill(bar).frame(width: 2) }
                }
                .contextMenu { PullRequestDiffLineMenu(model: model, path: path, hunk: hunk, line: index) }
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
