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

#if NATIVE_PREVIEWS_WIP
#Preview("Limit transcript card") {
    let limits = UsagePreviewFixtures.limits()
    let scheduled = UsagePreviewFixtures.limits(resumeScheduled: true)
    DSPreviewPair {
        if let stop = UsagePreviewFixtures.limitStop {
            VStack(spacing: DS.Space.lg) {
                UsageLimitTranscriptCard(
                    stop: stop, agent: UsagePreviewFixtures.claude, agentName: "Claude Code",
                    session: UsagePreviewFixtures.limitedSession, isLatestTurn: true, limits: limits)
                UsageLimitTranscriptCard(
                    stop: stop, agent: UsagePreviewFixtures.claude, agentName: "Claude Code",
                    session: UsagePreviewFixtures.limitedSession, isLatestTurn: true, limits: scheduled)
                // An earlier turn's card, or one whose limit has passed: a record of what happened.
                UsageLimitTranscriptCard(
                    stop: stop, agent: UsagePreviewFixtures.claude, agentName: "Claude Code",
                    session: UsagePreviewFixtures.limitedSession, isLatestTurn: false, limits: limits)
            }
            .frame(width: 640)
        }
    }
}
#endif
