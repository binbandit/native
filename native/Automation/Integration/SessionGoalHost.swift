import ACP
import Foundation
import NativeAutomation

/// A goal's view of its session: goals prompt it the way the user would, through `submit`, so the
/// prompt shows in the transcript and the turn is reported like any other.
final class SessionGoalHost: GoalHost {
    private weak var session: SessionModel?

    init(_ session: SessionModel) {
        self.session = session
    }

    var canSendGoalPrompt: Bool {
        guard let session else { return false }
        return session.acceptsPrompts && session.phase == .idle && !session.isRunningHiddenCommand && session.queuedPrompts.isEmpty
    }

    var goalSessionCost: Double? {
        session?.state.usage?.cost?.amount
    }

    var goalLatestReply: String? {
        session?.state.latestReply
    }

    func sendGoalPrompt(_ text: String) async {
        guard let session, canSendGoalPrompt else { return }
        // A goal prompt that can't go out leaves the goal waiting, which the goal bar shows; the
        // session itself reports why (disconnected, still loading).
        _ = try? await session.submit(text, .queue)
    }
}
