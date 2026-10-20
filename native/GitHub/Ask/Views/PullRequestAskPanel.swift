import GitHub
import SwiftUI

/// A small private conversation about a pull request, docked beside its page: answers from the
/// user's default agent, working read-only from the pull request's context. Only the user sees
/// it, and nothing is posted to GitHub; an answer becomes a comment draft only when they ask.
struct PullRequestAskPanel: View {
    let conversation: PullRequestAskConversation

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        VStack(spacing: 0) {
            PullRequestAskHeader(conversation: conversation)
            SeparatorLine()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: DS.Space.md) {
                if conversation.startedOverFrom != nil {
                    NoticeBanner(
                        tone: .info, systemImage: "square.and.pencil", title: "Started a new conversation",
                        detail: "The earlier one stays in \(conversation.agentName)'s history and in Search."
                    ) {
                        Button("Undo") { conversation.undoStartOver() }
                            .buttonStyle(.ds(.secondary))
                    }
                }
                if let failure = conversation.failure {
                    PullRequestAskFailureView(conversation: conversation, failure: failure)
                }
                PullRequestAskComposer(conversation: conversation)
            }
            .padding(DS.Space.md)
        }
        .background(.dsBackground)
        .task(id: conversation.reference) { await conversation.restore() }
    }

    @ViewBuilder private var content: some View {
        let page = gitHub.pageModel(for: conversation.reference)
        if page.page == nil, let error = page.loadError {
            PullRequestAskPageUnavailable(page: page, error: error)
        } else if conversation.session != nil || conversation.pendingQuestion != nil {
            PullRequestAskTranscript(conversation: conversation)
        } else if conversation.activity == .connecting(reopening: true) {
            LoadingStateView("Opening your earlier conversation…")
        } else if conversation.record != nil {
            // The earlier conversation couldn't be reopened; the failure above the composer says why.
            EmptyStateView(
                "Your earlier conversation isn't open", systemImage: "questionmark.bubble",
                message: "Try again, or start a new conversation about this pull request.")
        } else {
            PullRequestAskIntro(conversation: conversation)
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Ask panel") {
    let center = PullRequestAskPreviewFixtures.center()
    DSPreviewPair {
        PullRequestAskPanel(conversation: center.conversation(for: PullRequestPreviewRunner.reference))
            .frame(width: PullRequestAskMetrics.panelIdealWidth, height: 640)
    }
    .environment(center)
    .environment(GitHubModel.preview())
}
#endif
