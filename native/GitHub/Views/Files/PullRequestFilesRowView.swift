import GitHub
import SwiftUI

/// One row of Files Changed, whatever its kind.
struct PullRequestFilesRowView: View {
    let model: PullRequestPageModel
    let row: PullRequestFilesRow
    /// The list's width, for how many characters of code fit.
    let width: CGFloat
    let characterWidth: CGFloat
    let isShiftDown: Bool

    var body: some View {
        switch row.kind {
        case .header(let file):
            PullRequestFileHeader(model: model, file: file)
        case .loading:
            PullRequestFileNotice(model: model, path: row.path, kind: .loading)
        case .missing(let reason):
            PullRequestFileNotice(model: model, path: row.path, kind: .missing(reason))
        case .large(let lines):
            PullRequestFileNotice(model: model, path: row.path, kind: .large(lines: lines))
        case .hunkHeader(let hunk):
            PullRequestHunkHeaderRow(hunk: hunk)
                .onAppear { model.highlight(row.path) }
        case .block(let hunk, let range):
            PullRequestDiffBlockRow(
                model: model, path: row.path, hunk: hunk, range: range, columns: columns,
                characterWidth: characterWidth, isShiftDown: isShiftDown)
        case .thread(let thread, let showsAnchor):
            PullRequestReviewThreadView(model: model, thread: thread, showsAnchor: showsAnchor)
                .padding(DS.Space.md)
        case .draft:
            PullRequestCommentDraftView(model: model)
                .padding(DS.Space.md)
        case .footer:
            Color.clear.frame(height: DS.Space.xs)
        }
    }

    /// Characters of code that fit beside the file's gutter: the list's width less its padding, the
    /// card's edges, the gutter and the code's own padding.
    private var columns: Int {
        guard characterWidth > 0 else { return Int.max }
        let gutter =
            CGFloat(PullRequestDiffBlockText.gutterColumns(numberWidth: model.numberWidth(row.path))) * characterWidth
        let code = width - DS.Space.lg * 2 - 2 - gutter - 1 - DS.Space.md * 2
        return max(Int(code / characterWidth), 20)
    }
}
