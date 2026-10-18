import GitHub
import SwiftUI

/// What a diff line offers, in its context menu: comment, suggest a change, widen the comment
/// being written, ask an agent, copy. Touch and keyboard users reach every action here.
struct PullRequestDiffLineMenu: View {
    let model: PullRequestPageModel
    let path: String
    let hunk: DiffHunk
    /// The line's index in the hunk.
    let line: Int
    /// Whether the line is cut off at the edge, so "Show Whole Line" applies.
    var isCutOff = false

    var body: some View {
        let diffLine = hunk.lines[line]
        let anchor = diffLine.anchor.map { ReviewAnchor(path: path, side: $0.side, line: $0.line) }
        if let anchor, model.page?.isOpen == true {
            Button("Comment on \(anchor.lineDescription.capitalizedFirst)", systemImage: "text.bubble") {
                model.beginComment(at: anchor)
            }
            if anchor.side == .right {
                Button("Suggest a Change", systemImage: "pencil.line") {
                    model.beginComment(at: anchor)
                    model.draft?.body = SuggestionBlock.fence(model.draft?.lines ?? diffLine.text)
                }
            }
            if let extended = model.extendedDraft(to: diffLine, in: hunk, path: path) {
                Button("Extend Comment to Here", systemImage: "arrow.down.to.line") {
                    model.draft?.anchor = extended
                    model.draft?.lines = model.lineText(for: extended)
                }
            }
        }
        if let anchor, model.canAskAgent {
            Divider()
            let isInDraft = model.draftLines(in: path, hunk: hunk).contains(line)
            PullRequestAskAgentButtons(
                model: model, anchor: isInDraft ? (model.draft?.anchor ?? anchor) : anchor, thread: nil)
        }
        Divider()
        if isCutOff {
            Button("Show Whole Line", systemImage: "arrow.left.and.right.text.vertical") {
                model.expandLine(path, hunk, line)
            }
        }
        Button("Copy Line", systemImage: "doc.on.doc") { model.gitHub?.copy(diffLine.text) }
    }
}

extension String {
    /// "Line 4" from "line 4", for menu titles.
    fileprivate var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
