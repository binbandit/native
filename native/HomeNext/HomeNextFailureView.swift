import ACP
import SwiftUI

struct HomeNextFailureView: View {
    let session: SessionModel
    let openTask: () -> Void
    let retry: () -> Void

    var body: some View {
        let failure = TurnFailureContext(state: session.state)
        ErrorState(
            session.lastStopReason == .refusal
                ? "\(session.agentName) declined this task" : "\(session.agentName) stopped before finishing",
            recovery: failure.recovery ?? "Native kept the task's conversation and left the next step to you.",
            suggestion: session.canRetryHomeNext
                ? "Retry asks it to check what completed and continue."
                : "Open the task to reconnect its agent and continue.",
            details: failure.details,
            primary: session.canRetryHomeNext
                ? .init("Retry", shortcut: KeyboardShortcut("r", modifiers: .command), perform: retry) : nil,
            secondary: .init("Open Task", shortcut: KeyboardShortcut(.return, modifiers: .command), perform: openTask),
            layout: .reading)
    }
}

#if DEBUG
#Preview("Next failure - Retry") { HomeNextPreviewFixtures.page(.failure) }
#Preview("Next failure - Disconnected") { HomeNextPreviewFixtures.page(.recovery) }
#endif
