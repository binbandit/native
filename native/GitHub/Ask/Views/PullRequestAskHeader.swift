import GitHub
import SwiftUI

/// The panel's top: what it is, that it's private, and its two actions: start over and close.
struct PullRequestAskHeader: View {
    let conversation: PullRequestAskConversation

    @Environment(PullRequestAskCenter.self) private var center: PullRequestAskCenter?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                Text(verbatim: "Ask About #\(conversation.reference.number)")
                    .font(.dsCalloutSemibold)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.md)
                if conversation.record != nil {
                    IconButton("New Conversation", systemImage: "square.and.pencil") {
                        conversation.startOver()
                    }
                    .disabled(conversation.isBusy)
                }
                IconButton("Close", systemImage: "xmark") {
                    withAnimation(.dsStandard) { center?.setPanelOpen(false, for: conversation.reference) }
                }
            }
            Label(privacyLine, systemImage: "lock")
                .font(.dsCaption)
                .foregroundStyle(.dsTextSecondary)
                .labelStyle(PullRequestAskCaptionLabelStyle())
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.md)
    }

    private var privacyLine: String {
        let base = "Only you see this. Nothing is posted to GitHub."
        return conversation.isReadOnly
            ? base + " \(conversation.agentName) can read the pull request but not change anything."
            : base + " \(conversation.agentName) has no read-only mode here, so it asks before running anything."
    }
}
