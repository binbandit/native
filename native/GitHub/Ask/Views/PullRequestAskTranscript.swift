import ACP
import GitHub
import SwiftUI

/// The conversation so far, newest at the bottom: each question with its answer, the question on
/// its way while Native prepares, and any follow-ups waiting for the answer in progress.
struct PullRequestAskTranscript: View {
    let conversation: PullRequestAskConversation

    var body: some View {
        let turns = conversation.session.map(PullRequestAskTurn.turns) ?? []
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.xl) {
                ForEach(turns) { turn in
                    PullRequestAskTurnView(
                        conversation: conversation, turn: turn, isLatest: turn.id == turns.last?.id)
                }
                if let question = conversation.pendingQuestion {
                    PullRequestAskQuestionBubble(text: question)
                    PullRequestAskStatusLine(text: preparing)
                }
                ForEach(conversation.session?.queuedPrompts ?? []) { queued in
                    PullRequestAskQuestionBubble(
                        text: PullRequestAskPrompt.message(queued.text)?.question ?? queued.text, isQueued: true)
                }
                if conversation.isRecovering {
                    PullRequestAskStatusLine(
                        text: "\(conversation.agentName) stopped. Restarting it to finish the answer")
                } else if let session = conversation.session, session.phase == .disconnected {
                    ErrorState(
                        "\(conversation.agentName) stopped running",
                        recovery: "Your conversation is saved with \(conversation.agentName).",
                        suggestion: "Ask again to reopen it and carry on.",
                        primary: conversation.lastQuestion.map { _ in
                            .init("Ask Again") { Task { await conversation.askAgain() } }
                        })
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.lg)
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollContentBackground(.hidden)
    }

    private var preparing: String {
        switch conversation.activity {
        case .gathering: "Reading the pull request's diff and comments"
        case .connecting(reopening: true): "Opening your conversation with \(conversation.agentName)"
        case .connecting(reopening: false): "Starting \(conversation.agentName)"
        case .idle: "Sending"
        }
    }
}
