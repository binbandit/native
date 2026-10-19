import GitHub
import SwiftUI

/// "Add a comment" at the end of the conversation, with Close or Reopen beside it, as on GitHub.
struct PullRequestConversationComposer: View {
    let model: PullRequestPageModel
    let page: PullRequestPage

    var body: some View {
        @Bindable var model = model
        GitHubCommentComposer(
            text: $model.conversationDraft, placeholder: "Add a comment. Markdown works.",
            isBusy: model.busy.contains("conversation"), focusRequest: model.composerFocusRequest
        ) {
            if page.viewerCanCloseOrReopen {
                stateButton
            }
            Button(model.busy.contains("conversation") ? "Commenting…" : "Comment") {
                Task { await model.addConversationComment() }
            }
            .buttonStyle(.ds(.primary))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.conversationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// Closing keeps the branch and can be undone; a merged pull request can't be reopened.
    private var stateButton: some View {
        let busy = model.busy.contains("state")
        return Button(
            page.isOpen ? (busy ? "Closing…" : "Close Pull Request") : (busy ? "Reopening…" : "Reopen Pull Request"),
            systemImage: page.isOpen ? "xmark.circle" : "arrow.uturn.backward.circle"
        ) {
            Task { await model.setOpen(!page.isOpen) }
        }
        .buttonStyle(.ds(.secondary))
        .disabled(busy)
        .help(page.isOpen ? "Close without merging. You can reopen it." : "Reopen this pull request")
    }
}
