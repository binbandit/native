import ACP
import SwiftUI

/// A usage limit where it stopped a task's turn, so scrolling back explains the gap: the design
/// system's limit banner, offering Resume at Reset while the limit still holds the task, and a
/// record of what happened once it's passed.
struct UsageLimitTranscriptCard: View {
    let stop: UsageLimitStop
    let agent: AgentDefinition.ID
    let agentName: String
    let session: SessionID
    /// Only the latest turn's card can act; an earlier one is history.
    let isLatestTurn: Bool
    let limits: UsageLimits

    var body: some View {
        if isLatestTurn, let status = limits.limitStatus(agent: agent, session: session), status.level == .reached {
            let id = UsageSessionRef.ID(agent: agent, session: session)
            LimitBanner(
                status: status,
                onResume: { limits.resumeAtReset(id) },
                onCancelResume: { limits.cancelResume(id) },
                onSnooze: { limits.snoozeUntilReset(agent) }
            )
        } else {
            LimitBanner(status: record)
        }
    }

    /// The limit as it was: named when the message says which, in the provider's words.
    private var record: LimitStatus {
        LimitStatus(
            id: agent.rawValue, provider: agentName, level: .reached,
            window: UsageLimitHit(text: stop.message)?.window?.label, message: stop.message)
    }
}
