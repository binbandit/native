import GitHub
import SwiftUI

/// A comment on a pull request's conversation, written under its row in the list without opening
/// it. ⌘Return posts; Escape or Cancel closes the box and keeps the text for next time.
struct PullRequestQuickComment: View {
    let pullRequest: PullRequestSummary

    @Environment(GitHubModel.self) private var model

    var body: some View {
        let isPosting = model.isPostingComment(pullRequest)
        let text = Binding(
            get: { model.quickComments[pullRequest.url] ?? "" },
            set: { model.quickComments[pullRequest.url] = $0 })
        GitHubCommentComposer(
            text: text, placeholder: "Comment on \(pullRequest.reference). Markdown works.", isBusy: isPosting,
            focusesOnAppear: true
        ) {
            Button("Cancel") { model.commentingOn = nil }
                .buttonStyle(.ds(.ghost))
                .keyboardShortcut(.cancelAction)
            Button(isPosting ? "Commenting…" : "Comment") {
                Task { await model.postQuickComment(pullRequest) }
            }
            .buttonStyle(.ds(.primary))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
