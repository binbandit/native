import GitHub
import SwiftUI

/// "Add a comment" at the end of the conversation.
struct PullRequestConversationComposer: View {
    let model: PullRequestPageModel
    let page: PullRequestPage

    var body: some View {
        @Bindable var model = model
        GitHubCommentComposer(
            text: $model.conversationDraft, placeholder: "Add a comment. Markdown works.",
            isBusy: model.busy.contains("conversation")
        ) {
            Button(model.busy.contains("conversation") ? "Commenting…" : "Comment") {
                Task { await model.addConversationComment() }
            }
            .buttonStyle(.ds(.primary))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.conversationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
