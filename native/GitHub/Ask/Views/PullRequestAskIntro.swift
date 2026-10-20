import SwiftUI

/// Before the first question: what this is, who answers and from what, and a few questions to
/// start with.
struct PullRequestAskIntro: View {
    let conversation: PullRequestAskConversation

    /// Questions worth asking about most pull requests.
    static let suggestions = [
        "What does this change, and what's risky?",
        "What did reviewers ask for, and what's still open?",
        "What should I test before approving this?",
    ]

    var body: some View {
        EmptyStateView(
            "Ask about this pull request", systemImage: "questionmark.bubble",
            message:
                "\(conversation.agentName) answers from its description, conversation, review comments and diff, without changing anything."
        ) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button(suggestion) { Task { await conversation.ask(suggestion) } }
                        .buttonStyle(.ds(.ghost))
                        .multilineTextAlignment(.leading)
                }
            }
            .disabled(conversation.isBusy || conversation.center.app == nil)
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Ask intro") {
    let center = PullRequestAskPreviewFixtures.center()
    DSPreviewPair {
        PullRequestAskIntro(conversation: center.conversation(for: PullRequestPreviewRunner.reference))
            .frame(width: PullRequestAskMetrics.panelIdealWidth, height: 420)
    }
    .environment(center)
}
#endif
