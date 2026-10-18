import SwiftUI

/// A listed task that couldn't be opened, in its place: what went wrong and the way on. Retrying
/// shows the opening state again until it opens or fails anew.
struct SessionOpenFailureView: View {
    let failure: SessionOpenFailure
    let onRetry: () -> Void
    let onGoBack: () -> Void

    var body: some View {
        switch failure.reason {
        case .agentMissing:
            ErrorState(
                "Native has no \(failure.agent) agent",
                suggestion:
                    "This task belongs to an agent that's turned off or was removed. Turn it on in Settings, then try again.",
                primary: .init("Try Again", perform: onRetry),
                secondary: .init("Go Back", perform: onGoBack),
                layout: .pane
            )
        case .notRunning:
            ErrorState(
                "Couldn't open this task",
                recovery: "\(failure.agent) stopped before the task opened.",
                suggestion: "Try again to start it.",
                details: failure.details,
                primary: .init("Try Again", perform: onRetry),
                layout: .pane
            )
        case .cannotLoad:
            // Trying again can't help: the agent has no way to load a past task.
            ErrorState(
                "\(failure.agent) can't reopen this task",
                suggestion:
                    "It lists its past tasks but can't load one back into Native. Continue it in \(failure.agent) itself.",
                primary: .init("Go Back", perform: onGoBack),
                layout: .pane
            )
        case .failed:
            ErrorState(
                "Couldn't open this task",
                suggestion: "Try again, or go back to what you were doing.",
                details: failure.details,
                primary: .init("Try Again", perform: onRetry),
                secondary: .init("Go Back", perform: onGoBack),
                layout: .pane
            )
        }
    }
}

#Preview("Open failures") {
    DSPreviewPair {
        VStack {
            SessionOpenFailureView(
                failure: SessionOpenFailure(.cannotLoad, agent: "Pi"), onRetry: {}, onGoBack: {})
            SessionOpenFailureView(
                failure: SessionOpenFailure(.notRunning, agent: "Codex", details: "Codex isn't running."),
                onRetry: {}, onGoBack: {})
        }
        .frame(width: 560, height: 640)
    }
}
