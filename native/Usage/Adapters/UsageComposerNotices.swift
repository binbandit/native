import SwiftUI

/// The usage notices above a task's composer, in its column: a limit that's close or holds the
/// provider's other tasks, and a context window that's nearly full. Takes no room when there's
/// nothing to say.
struct UsageComposerNotices: View {
    let session: SessionModel

    @Environment(\.transcriptColumnMaxWidth) private var columnWidth
    @State private var pressureDismissedAt: Double?

    var body: some View {
        let source = SessionContextSource(session: session)
        let limits = BuiltInPlugins.usage.limits
        let showsLimit = limits.limitStatus(agent: session.agent.id, session: session.id)?.resume == .notNeeded
        let showsPressure = ContextPressureBanner<SessionContextSource>.shows(
            fraction: source.fractionUsed, dismissedAt: pressureDismissedAt)
        if showsLimit || showsPressure {
            VStack(spacing: DS.Space.md) {
                if showsLimit {
                    UsageLimitBanner(session: session)
                }
                if showsPressure {
                    ContextPressureBanner(source: source, dismissedAt: pressureDismissedAt) { pressureDismissedAt = $0 }
                }
            }
            .frame(maxWidth: columnWidth)
            .padding(.horizontal, DS.Space.xxl)
            .padding(.top, DS.Space.md)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
    }
}
