import ACP
import SwiftUI

/// The design system's limit banner for one session, kept up to date from `UsageLimits`: Resume
/// at Reset when the limit stopped this session, Snooze Until Reset otherwise. Shows nothing while
/// the session's provider has no limit to report.
struct UsageLimitBanner: View {
    let agent: AgentDefinition.ID
    let session: SessionID
    let limits: UsageLimits

    var body: some View {
        if let status = limits.limitStatus(agent: agent, session: session) {
            let id = UsageSessionRef.ID(agent: agent, session: session)
            LimitBanner(
                status: status,
                onResume: { limits.resumeAtReset(id) },
                onCancelResume: { limits.cancelResume(id) },
                onSnooze: { limits.snoozeUntilReset(agent) },
                onDismiss: { limits.dismiss(agent) }
            )
            .transition(.opacity)
        }
    }
}
