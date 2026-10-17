import ACP
import SwiftUI

/// The limit banner for a session, kept up to date from `UsageLimits`. Shows nothing while the
/// session's provider has no limit to report.
struct UsageLimitBanner: View {
    let agent: AgentDefinition.ID
    let session: SessionID
    var chrome: UsageBannerChrome = .section
    let limits: UsageLimits

    var body: some View {
        if let notice = limits.notice(agent: agent, session: session) {
            let id = LimitTarget.ID(agent: agent, session: session)
            LimitBanner(
                notice: notice,
                onResumeAtReset: { limits.resumeAtReset(id) },
                onCancelResume: { limits.cancelResume(id) },
                onSnooze: { limits.snoozeUntilReset(agent) },
                onDismiss: { limits.dismiss(agent) }
            )
            .usageBannerChrome(chrome)
            .transition(.opacity)
        }
    }
}
