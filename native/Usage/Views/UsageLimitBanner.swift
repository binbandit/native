import ACP
import SwiftUI

/// The design system's limit banner above a session's composer, kept up to date from `UsageLimits`:
/// a limit that's close, or one that stopped the provider's other tasks, with Snooze Until Reset.
/// When the limit stopped this task, the card in its transcript says so where the work stopped
/// and offers Resume at Reset, so this stays out of the way. Shows nothing otherwise.
struct UsageLimitBanner: View {
    let agent: AgentDefinition.ID
    let session: SessionID
    let limits: UsageLimits

    var body: some View {
        if let status = limits.limitStatus(agent: agent, session: session), status.resume == .notNeeded {
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
