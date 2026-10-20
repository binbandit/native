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

#if NATIVE_PREVIEWS_WIP
#Preview("Quick comment") {
    let pullRequest = PullRequestPreviewFixtures.inbox.reviewRequested[0]
    let empty = GitHubModel.preview()
    let drafted = GitHubModel.preview()
    drafted.quickComments[pullRequest.url] = "Looks good once the 60-a-minute limit is per client, not per process."
    return DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            PullRequestQuickComment(pullRequest: pullRequest)
                .environment(empty)
            PullRequestQuickComment(pullRequest: pullRequest)
                .environment(drafted)
        }
        .frame(width: PullRequestsLayout.contentWidth)
    }
}
#endif
